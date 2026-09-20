param(
    [Parameter(Mandatory=$true)][string]$RunDir,
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [int]$ActivePercent = 25,
    [int]$PacketBytes = 160,
    [int]$PacketIntervalMs = 20,
    [int]$TelemetryIntervalMs = 100,
    [int]$FlushIntervalMs = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function UtcIso([DateTime]$Value) { return $Value.ToUniversalTime().ToString('o') }
function Write-JsonAtomicLocal($Object, [string]$Path) {
    $tmp = $Path + '.tmp'
    $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Percentile([double[]]$Values, [double]$P) {
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $idx = [int][math]::Ceiling(($P / 100.0) * $sorted.Count) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $sorted.Count) { $idx = $sorted.Count - 1 }
    return [math]::Round([double]$sorted[$idx], 3)
}

$readyPath = Join-Path $RunDir 'load-worker.ready'
$stopPath = Join-Path $RunDir 'load-worker.stop'
$metricsPath = Join-Path $RunDir 'load-worker-metrics.json'
$summaryPath = Join-Path $RunDir 'load-worker-summary.json'
$eventLogPath = Join-Path $RunDir 'runtime-events.jsonl'
$dbPath = Join-Path $RunDir 'runtime-index.sqlite'

$streams = New-Object System.Collections.ArrayList
$db = [IntPtr]::Zero
$result = 'FAIL'
$failure = $null
$failureStage = 'INITIALIZE'
$dbLatencies = New-Object System.Collections.Generic.List[double]
$packetWrites = [int64]0
$bytesWritten = [int64]0
$logEvents = [int64]0
$dbTransactions = [int64]0
$dbRows = [int64]0
$loopLagMaxMs = 0.0
$startedUtc = [DateTime]::UtcNow
$manifest = @()
$activeCount = 0

try {
    $failureStage = 'LOAD_MANIFEST'
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest not found: $ManifestPath" }
    $manifestRaw = Get-Content -LiteralPath $ManifestPath -Raw
    $manifestDoc = $manifestRaw | ConvertFrom-Json
    if ($null -eq $manifestDoc) { throw 'Current-window manifest JSON decoded to null.' }

    $schemaProp = $manifestDoc.PSObject.Properties['schema']
    if ($null -eq $schemaProp -or [string]$schemaProp.Value -ne 'recorder-poc.current-window-file-manifest.v2') {
        throw ("Unsupported current-window manifest schema: {0}" -f $(if ($null -eq $schemaProp) { '<missing>' } else { [string]$schemaProp.Value }))
    }
    $filesProp = $manifestDoc.PSObject.Properties['files']
    if ($null -eq $filesProp -or $null -eq $filesProp.Value) { throw 'Current-window manifest has no files array.' }
    $manifest = @($filesProp.Value | ForEach-Object { $_ })
    if ($manifest.Count -lt 1) { throw 'Current-window manifest is empty.' }

    $declaredCountProp = $manifestDoc.PSObject.Properties['file_count']
    if ($null -eq $declaredCountProp) { throw 'Current-window manifest has no file_count.' }
    $declaredCount = [int]$declaredCountProp.Value
    if ($declaredCount -ne $manifest.Count) {
        throw ("Current-window manifest count mismatch: declared={0} decoded={1}" -f $declaredCount,$manifest.Count)
    }

    $activeCount = [int][math]::Ceiling($manifest.Count * ($ActivePercent / 100.0))
    if ($activeCount -lt 1) { $activeCount = 1 }
    if ($activeCount -gt $manifest.Count) { $activeCount = $manifest.Count }

    $failureStage = 'OPEN_CURRENT_FILES'
    $openIndex = 0
    foreach ($row in $manifest) {
        $openIndex++
        $slotProp = $row.PSObject.Properties['slot']
        $pathProp = $row.PSObject.Properties['partial_path']
        $slot = if ($null -eq $slotProp) { '<missing>' } else { [string]$slotProp.Value }
        if ($null -eq $pathProp -or $null -eq $pathProp.Value) {
            throw ("Manifest row missing partial_path: index={0} slot={1}" -f $openIndex,$slot)
        }

        $rawPath = $pathProp.Value
        if ($rawPath -is [System.Array]) {
            throw ("Manifest partial_path unexpectedly decoded as array: index={0} slot={1} count={2}" -f $openIndex,$slot,@($rawPath).Count)
        }
        $pathText = ([string]$rawPath).Trim()
        if ([string]::IsNullOrWhiteSpace($pathText)) {
            throw ("Manifest partial_path is empty: index={0} slot={1}" -f $openIndex,$slot)
        }
        if ($pathText.Contains('"')) {
            throw ("Manifest partial_path contains quote characters: index={0} slot={1} value=[{2}]" -f $openIndex,$slot,$pathText)
        }

        try { $normalizedPath = [System.IO.Path]::GetFullPath($pathText) }
        catch {
            throw ("Manifest path normalization failed: index={0} slot={1} raw_type={2} raw=[{3}] error={4}" -f $openIndex,$slot,$rawPath.GetType().FullName,$pathText,$_.Exception.Message)
        }
        if (-not [System.IO.Path]::IsPathRooted($normalizedPath)) {
            throw ("Manifest path is not rooted: index={0} slot={1} normalized=[{2}]" -f $openIndex,$slot,$normalizedPath)
        }
        if (-not (Test-Path -LiteralPath $normalizedPath -PathType Leaf)) {
            throw ("Manifest file does not exist before open: index={0} slot={1} normalized=[{2}]" -f $openIndex,$slot,$normalizedPath)
        }

        try {
            $fs = [System.IO.File]::Open(
                $normalizedPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::Read)
        } catch {
            throw ("Open current file failed: index={0} slot={1} raw_type={2} raw=[{3}] normalized=[{4}] error={5}" -f $openIndex,$slot,$rawPath.GetType().FullName,$pathText,$normalizedPath,$_.Exception.Message)
        }
        $fs.Position = $fs.Length
        [void]$streams.Add($fs)
    }

    $failureStage = 'SQLITE_BINDINGS'
    # Use the inbox Windows SQLite library so this gate exercises a real SQLite
    # database without adding a package/runtime dependency to the PoC.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PocWinSqlite {
    const int SQLITE_OK = 0;
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Ansi)]
    static extern int sqlite3_open(string filename, out IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Ansi)]
    static extern int sqlite3_exec(IntPtr db, string sql, IntPtr callback, IntPtr arg, out IntPtr errmsg);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern void sqlite3_free(IntPtr p);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern int sqlite3_close(IntPtr db);

    public static IntPtr Open(string path) {
        IntPtr db;
        int rc = sqlite3_open(path, out db);
        if (rc != SQLITE_OK) throw new InvalidOperationException("sqlite3_open rc=" + rc);
        return db;
    }
    public static void Exec(IntPtr db, string sql) {
        IntPtr err;
        int rc = sqlite3_exec(db, sql, IntPtr.Zero, IntPtr.Zero, out err);
        if (rc != SQLITE_OK) {
            string msg = err == IntPtr.Zero ? ("sqlite3_exec rc=" + rc) : Marshal.PtrToStringAnsi(err);
            if (err != IntPtr.Zero) sqlite3_free(err);
            throw new InvalidOperationException(msg);
        }
    }
    public static void Close(IntPtr db) { if (db != IntPtr.Zero) sqlite3_close(db); }
}
'@ | Out-Null

    $failureStage = 'SQLITE_OPEN_AND_WAL'
    $systemSqlite = Join-Path $env:WINDIR 'System32\winsqlite3.dll'
    if (-not (Test-Path -LiteralPath $systemSqlite)) {
        throw ("winsqlite3.dll not found at expected Windows system path: {0}" -f $systemSqlite)
    }
    $db = [PocWinSqlite]::Open($dbPath)
    [PocWinSqlite]::Exec($db, 'PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA temp_store=MEMORY;')
    [PocWinSqlite]::Exec($db, 'CREATE TABLE IF NOT EXISTS runtime_sample (id INTEGER PRIMARY KEY AUTOINCREMENT, ts_utc TEXT NOT NULL, active_streams INTEGER NOT NULL, packet_writes INTEGER NOT NULL, bytes_written INTEGER NOT NULL, log_seq INTEGER NOT NULL);')

    $packet = New-Object byte[] $PacketBytes
    for ($i = 0; $i -lt $packet.Length; $i++) { $packet[$i] = [byte](0xD5 -band 0xFF) }

    $failureStage = 'FIRST_DB_TRANSACTION'
    $preflightTs = [DateTime]::UtcNow.ToString('o')
    [PocWinSqlite]::Exec($db, ("BEGIN IMMEDIATE; INSERT INTO runtime_sample(ts_utc,active_streams,packet_writes,bytes_written,log_seq) VALUES('{0}',{1},0,0,0); COMMIT;" -f $preflightTs,$activeCount))
    $dbTransactions++
    $dbRows++

    $failureStage = 'FIRST_LOG_WRITE'
    $preflightEvent = ('{{"ts_utc":"{0}","event":"LOAD_WORKER_PREFLIGHT","active_streams":{1}}}' -f $preflightTs,$activeCount)
    [IO.File]::AppendAllText($eventLogPath, $preflightEvent + [Environment]::NewLine, (New-Object Text.UTF8Encoding -ArgumentList $false))
    $logEvents++

    $failureStage = 'FIRST_MEDIA_WRITE'
    if ($activeCount -gt 0) {
        $preflightPacket = New-Object byte[] $PacketBytes
        for ($i = 0; $i -lt $activeCount; $i++) {
            $streams[$i].Write($preflightPacket, 0, $preflightPacket.Length)
            $packetWrites++
            $bytesWritten += $preflightPacket.Length
        }
    }

    $failureStage = 'READY_HANDSHAKE'
    Write-JsonAtomicLocal ([ordered]@{
        ts_utc = [DateTime]::UtcNow.ToString('o')
        elapsed_ms = 0
        packet_writes = $packetWrites
        bytes_written = $bytesWritten
        log_events = $logEvents
        db_transactions = $dbTransactions
        db_rows = $dbRows
        db_exec_ms_total = 0
        db_exec_ms_max = 0
        loop_lag_max_ms = 0
    }) $metricsPath

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $nextPacketMs = 0.0
    $nextTelemetryMs = 0.0
    $nextFlushMs = $FlushIntervalMs
    $seq = [int64]0

    Write-JsonAtomicLocal ([ordered]@{
        ready_utc = [DateTime]::UtcNow.ToString('o')
        total_files_open = $streams.Count
        active_files = $activeCount
        packet_bytes = $PacketBytes
        packet_interval_ms = $PacketIntervalMs
        sqlite = $dbPath
        sqlite_ready = $true
        wal_enabled = $true
        preflight_packet_writes = $packetWrites
        preflight_log_events = $logEvents
        preflight_db_transactions = $dbTransactions
    }) $readyPath

    $failureStage = 'RUNNING_LOAD'
    while (-not (Test-Path -LiteralPath $stopPath)) {
        $nowMs = $sw.Elapsed.TotalMilliseconds

        if ($nowMs -ge $nextPacketMs) {
            $lag = $nowMs - $nextPacketMs
            if ($lag -gt $loopLagMaxMs) { $loopLagMaxMs = $lag }
            $seq++
            # Change a few bytes so writes are not identical cache-only payloads.
            if ($packet.Length -ge 8) {
                $b = [BitConverter]::GetBytes($seq)
                [Array]::Copy($b, 0, $packet, 0, [math]::Min(8, $packet.Length))
            }
            for ($i = 0; $i -lt $activeCount; $i++) {
                $streams[$i].Write($packet, 0, $packet.Length)
                $packetWrites++
                $bytesWritten += $packet.Length
            }
            $nextPacketMs += $PacketIntervalMs
        }

        if ($nowMs -ge $nextTelemetryMs) {
            $ts = [DateTime]::UtcNow.ToString('o')
            $event = ('{{"ts_utc":"{0}","event":"MEDIA_SNAPSHOT","active_streams":{1},"packet_writes":{2},"bytes_written":{3}}}' -f $ts, $activeCount, $packetWrites, $bytesWritten)
            [IO.File]::AppendAllText($eventLogPath, $event + [Environment]::NewLine, (New-Object Text.UTF8Encoding -ArgumentList $false))
            $logEvents++

            $dbSw = [Diagnostics.Stopwatch]::StartNew()
            $sql = New-Object Text.StringBuilder
            [void]$sql.Append('BEGIN IMMEDIATE;')
            for ($i = 0; $i -lt $activeCount; $i++) {
                [void]$sql.AppendFormat("INSERT INTO runtime_sample(ts_utc,active_streams,packet_writes,bytes_written,log_seq) VALUES('{0}',{1},{2},{3},{4});", $ts, $activeCount, $packetWrites, $bytesWritten, $logEvents)
            }
            [void]$sql.Append('COMMIT;')
            [PocWinSqlite]::Exec($db, $sql.ToString())
            $dbSw.Stop()
            $dbLatencies.Add($dbSw.Elapsed.TotalMilliseconds)
            $dbTransactions++
            $dbRows += $activeCount

            Write-JsonAtomicLocal ([ordered]@{
                ts_utc = $ts
                elapsed_ms = [math]::Round($nowMs, 3)
                packet_writes = $packetWrites
                bytes_written = $bytesWritten
                log_events = $logEvents
                db_transactions = $dbTransactions
                db_rows = $dbRows
                db_exec_ms_total = [math]::Round((($dbLatencies | Measure-Object -Sum).Sum), 3)
                db_exec_ms_max = if ($dbLatencies.Count) { [math]::Round((($dbLatencies | Measure-Object -Maximum).Maximum), 3) } else { 0 }
                loop_lag_max_ms = [math]::Round($loopLagMaxMs, 3)
            }) $metricsPath
            $nextTelemetryMs += $TelemetryIntervalMs
        }

        if ($nowMs -ge $nextFlushMs) {
            for ($i = 0; $i -lt $activeCount; $i++) { $streams[$i].Flush() }
            $nextFlushMs += $FlushIntervalMs
        }

        Start-Sleep -Milliseconds 1
    }

    $failureStage = 'FINAL_FLUSH'
    for ($i = 0; $i -lt $activeCount; $i++) { $streams[$i].Flush() }
    $failureStage = 'COMPLETE'
    $result = 'PASS'
}
catch {
    $failure = $_.Exception.Message
}
finally {
    if ($db -ne [IntPtr]::Zero) {
        try { [PocWinSqlite]::Close($db) } catch {}
    }
    foreach ($fs in $streams) { try { $fs.Dispose() } catch {} }
    $endedUtc = [DateTime]::UtcNow
    $summary = [ordered]@{
        schema = 'recorder-poc.current-window-load-worker.v1'
        result = $result
        failure_stage = $failureStage
        failure_reason = $failure
        started_utc = UtcIso $startedUtc
        ended_utc = UtcIso $endedUtc
        total_files = if ($null -ne $manifest) { @($manifest).Count } else { 0 }
        active_percent = $ActivePercent
        active_files = if ($null -ne $activeCount) { $activeCount } else { 0 }
        packet_bytes = $PacketBytes
        packet_interval_ms = $PacketIntervalMs
        packet_writes = $packetWrites
        bytes_written = $bytesWritten
        log_events = $logEvents
        db_transactions = $dbTransactions
        db_rows = $dbRows
        db_latency_ms = [ordered]@{
            p50 = Percentile ([double[]]$dbLatencies.ToArray()) 50
            p95 = Percentile ([double[]]$dbLatencies.ToArray()) 95
            max = if ($dbLatencies.Count) { [math]::Round((($dbLatencies | Measure-Object -Maximum).Maximum),3) } else { $null }
        }
        loop_lag_max_ms = [math]::Round($loopLagMaxMs, 3)
        sqlite_path = $dbPath
        log_path = $eventLogPath
        metrics_path = $metricsPath
    }
    Write-JsonAtomicLocal $summary $summaryPath
}

if ($result -eq 'PASS') { exit 0 }
Write-Error "LOAD WORKER FAIL: $failure"
exit 23
