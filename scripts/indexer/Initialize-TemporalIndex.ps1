[CmdletBinding()]
param(
  [string]$DatabasePath = (Join-Path $PSScriptRoot '..\..\runs\index\recorder-index.sqlite'),
  [string]$SchemaPath = (Join-Path $PSScriptRoot '..\..\db\temporal-index-schema.sql')
)
$ErrorActionPreference='Stop'
$db=[IO.Path]::GetFullPath($DatabasePath)
$schema=[IO.Path]::GetFullPath($SchemaPath)
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($db)) | Out-Null
if (-not (Test-Path $schema)) { throw "Schema not found: $schema" }
$sqlite = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
if (-not $sqlite) { throw 'sqlite3.exe not found. The integrated Windows package will bind winsqlite3.dll; this script uses sqlite3.exe as a development gate.' }
& $sqlite.Source $db ".read '$($schema -replace "'","''")'"
if ($LASTEXITCODE -ne 0) { throw "SQLite initialization failed: exit=$LASTEXITCODE" }
Write-Host "TEMPORAL INDEX INITIALIZED: $db"
