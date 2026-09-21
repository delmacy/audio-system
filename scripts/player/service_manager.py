"""Local process supervisor for the Audio System development runtime."""

from __future__ import annotations

import argparse
import configparser
import ctypes
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "runs" / "system-runtime"
REGISTRY_PATH = RUNTIME_DIR / "services.json"
LOG_DIR = RUNTIME_DIR / "logs"

SERVICE_ORDER = ("api", "frontend", "recorder", "rps", "simulator")
CONTROLLED_FROM_API = {"recorder", "rps", "simulator"}

PORTS = {
    "api": ("127.0.0.1", 8500),
    "frontend": ("127.0.0.1", 5173),
}

PROFILE_PATH = ROOT / "config" / "profiles" / "local-poc.ini"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _ensure_dirs() -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)


def _load_registry() -> dict[str, Any]:
    _ensure_dirs()
    if not REGISTRY_PATH.is_file():
        return {"schema": "audio-system.system-runtime.v1", "services": {}}
    try:
        payload = json.loads(REGISTRY_PATH.read_text(encoding="utf-8-sig"))
        if isinstance(payload, dict) and isinstance(payload.get("services"), dict):
            return payload
    except (OSError, json.JSONDecodeError):
        pass
    return {"schema": "audio-system.system-runtime.v1", "services": {}}


def _save_registry(payload: dict[str, Any]) -> None:
    _ensure_dirs()
    payload["schema"] = "audio-system.system-runtime.v1"
    payload["updated_utc"] = _utc_now()
    temp = REGISTRY_PATH.with_suffix(".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(REGISTRY_PATH)


def _pid_alive(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False

    if os.name == "nt":
        # Avoid os.kill(pid, 0) on Windows/Python 3.13. Some Windows builds can
        # leave WinError 87 pending even when OSError is caught, which later
        # surfaces as an unrelated SystemError inside pathlib.
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        open_process = kernel32.OpenProcess
        open_process.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
        open_process.restype = ctypes.c_void_p
        close_handle = kernel32.CloseHandle
        close_handle.argtypes = [ctypes.c_void_p]
        close_handle.restype = ctypes.c_int

        handle = open_process(PROCESS_QUERY_LIMITED_INFORMATION, 0, int(pid))
        if not handle:
            return False
        close_handle(handle)
        return True

    try:
        os.kill(int(pid), 0)
        return True
    except OSError:
        return False


def _port_open(host: str, port: int, timeout: float = 0.15) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False



def _profile_ports() -> dict[str, tuple[str, int, str]]:
    result: dict[str, tuple[str, int, str]] = {}
    if not PROFILE_PATH.is_file():
        return result
    parser = configparser.ConfigParser()
    try:
        parser.read(PROFILE_PATH, encoding="utf-8")
        recorder_ip = parser.get("recorder", "ip", fallback="").strip()
        recorder_port = parser.getint("recorder", "rtsp_port", fallback=0)
        if recorder_ip and recorder_port:
            result["recorder"] = (recorder_ip, recorder_port, "tcp")

        proxy_ip = parser.get("sip", "proxy_ip", fallback="").strip()
        proxy_port = parser.getint("sip", "proxy_port", fallback=0)
        if proxy_ip and proxy_port:
            # SIP may use TCP or UDP. Cleanup checks both transports.
            result["rps"] = (proxy_ip, proxy_port, "both")
    except (OSError, configparser.Error, ValueError):
        pass
    return result


def _service_endpoints(name: str) -> list[tuple[str, int, str]]:
    endpoints: list[tuple[str, int, str]] = []
    if name in PORTS:
        host, port = PORTS[name]
        endpoints.append((host, port, "tcp"))
    configured = _profile_ports().get(name)
    if configured:
        endpoints.append(configured)
    return endpoints


def _windows_port_owner_pids(port: int, protocol: str = "tcp") -> set[int]:
    if os.name != "nt":
        return set()

    queries: list[str] = []
    if protocol in {"tcp", "both"}:
        queries.append(
            f"Get-NetTCPConnection -LocalPort {int(port)} -ErrorAction SilentlyContinue "
            "| Select-Object -ExpandProperty OwningProcess"
        )
    if protocol in {"udp", "both"}:
        queries.append(
            f"Get-NetUDPEndpoint -LocalPort {int(port)} -ErrorAction SilentlyContinue "
            "| Select-Object -ExpandProperty OwningProcess"
        )

    pids: set[int] = set()
    for query in queries:
        completed = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", query],
            capture_output=True,
            text=True,
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        for line in completed.stdout.splitlines():
            line = line.strip()
            if line.isdigit():
                pid = int(line)
                if pid > 0:
                    pids.add(pid)
    return pids


def _windows_process_pids_matching(patterns: tuple[str, ...]) -> set[int]:
    if os.name != "nt" or not patterns:
        return set()

    escaped = [pattern.replace("'", "''") for pattern in patterns]
    conditions = " -or ".join(
        f"$_.CommandLine -like '*{pattern}*'" for pattern in escaped
    )
    command = (
        "Get-CimInstance Win32_Process -ErrorAction SilentlyContinue "
        f"| Where-Object {{ $_.CommandLine -and ({conditions}) }} "
        "| Select-Object -ExpandProperty ProcessId"
    )
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        check=False,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )

    result: set[int] = set()
    for line in completed.stdout.splitlines():
        line = line.strip()
        if line.isdigit():
            pid = int(line)
            if pid > 0:
                result.add(pid)
    return result


def _cleanup_legacy_dev_supervisors() -> list[int]:
    """Stop the old auto-restarting dev supervisor before clean startup."""
    if os.name != "nt":
        return []

    project_name = ROOT.name
    candidates = _windows_process_pids_matching((
        "Start-AudioSystemDev.ps1",
        "dev:supervisor",
    ))
    current_pid = os.getpid()
    killed: list[int] = []

    for pid in sorted(candidates):
        if pid <= 0 or pid == current_pid:
            continue

        # Avoid touching similarly named processes from another checkout when
        # command-line inspection can prove that this project is not involved.
        command = (
            f"$p=Get-CimInstance Win32_Process -Filter \"ProcessId={pid}\" "
            "-ErrorAction SilentlyContinue; if($p){$p.CommandLine}"
        )
        completed = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", command],
            capture_output=True,
            text=True,
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        command_line = completed.stdout.strip().lower()
        root_text = str(ROOT).lower()
        belongs_here = (
            root_text in command_line
            or project_name.lower() in command_line
            or "start-audiosystemdev.ps1" in command_line
        )
        if not belongs_here:
            continue

        if _pid_alive(pid):
            _kill_tree(pid)
            killed.append(pid)

    for pid in killed:
        for _ in range(50):
            if not _pid_alive(pid):
                break
            time.sleep(0.1)

    return killed


def _windows_process_pids_by_name(process_name: str) -> set[int]:
    if os.name != "nt":
        return set()
    command = (
        f"Get-Process -Name '{process_name}' -ErrorAction SilentlyContinue "
        "| Select-Object -ExpandProperty Id"
    )
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        check=False,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    result: set[int] = set()
    for line in completed.stdout.splitlines():
        line = line.strip()
        if line.isdigit():
            result.add(int(line))
    return result


def _port_is_free(host: str, port: int, protocol: str) -> bool:
    if os.name == "nt":
        return not _windows_port_owner_pids(port, protocol)
    if protocol == "tcp":
        return not _port_open(host, port)
    return True


def _wait_endpoints_free(name: str, timeout_seconds: float = 8.0) -> bool:
    endpoints = _service_endpoints(name)
    if not endpoints:
        return True
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if all(_port_is_free(host, port, protocol) for host, port, protocol in endpoints):
            return True
        time.sleep(0.15)
    return all(_port_is_free(host, port, protocol) for host, port, protocol in endpoints)


def _cleanup_service_before_start(name: str) -> dict[str, Any]:
    """Terminate stale instances/port owners for one Audio System service."""
    registry = _load_registry()
    current = registry["services"].get(name, {})
    candidates: set[int] = set()

    registered_pid = int(current.get("pid") or 0)
    if registered_pid > 0:
        candidates.add(registered_pid)

    if name == "recorder":
        recorder_pid = _current_recorder_pid()
        if recorder_pid:
            candidates.add(recorder_pid)
        # recorder-host.exe belongs to this project's native recorder runtime.
        candidates.update(_windows_process_pids_by_name("recorder-host"))

    for _host, port, protocol in _service_endpoints(name):
        candidates.update(_windows_port_owner_pids(port, protocol))

    current_pid = os.getpid()
    killed: list[int] = []
    for pid in sorted(candidates):
        if pid <= 0 or pid == current_pid:
            continue
        if _pid_alive(pid):
            _kill_tree(pid)
            killed.append(pid)

    for pid in killed:
        for _ in range(40):
            if not _pid_alive(pid):
                break
            time.sleep(0.1)

    if not _wait_endpoints_free(name):
        occupied = [
            f"{host}:{port}/{protocol}"
            for host, port, protocol in _service_endpoints(name)
            if not _port_is_free(host, port, protocol)
        ]
        raise RuntimeError(
            f"Could not release required endpoints for {name}: {', '.join(occupied)}"
        )

    registry = _load_registry()
    registry["services"][name] = {
        **registry["services"].get(name, {}),
        "pid": None,
        "state": "stopped",
        "preflight_killed_pids": killed,
        "preflight_utc": _utc_now(),
    }
    _save_registry(registry)
    return {"service": name, "killed_pids": killed}


def _service_command(name: str) -> tuple[list[str], Path]:
    if name == "api":
        return [sys.executable, str(ROOT / "scripts" / "player" / "timeline_api.py")], ROOT
    if name == "frontend":
        return ["cmd.exe", "/d", "/s", "/c", "npm run dev"], ROOT
    if name == "recorder":
        return [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(ROOT / "scripts" / "recorder" / "Start-LiveRecorderStack.ps1"),
        ], ROOT
    if name == "rps":
        return [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(ROOT / "scripts" / "gateway" / "Start-RpsRuntime.ps1"),
        ], ROOT
    if name == "simulator":
        return [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(ROOT / "scripts" / "cwp" / "Start-LiveCwpSimulator.ps1"),
        ], ROOT
    raise ValueError(f"Unknown service: {name}")



def _current_recorder_pid() -> int | None:
    pointer = ROOT / "runs" / "operational-recorder" / "current-run.txt"
    if not pointer.is_file():
        return None
    try:
        run = Path(pointer.read_text(encoding="utf-8-sig").strip())
        state_file = run / "operational-recorder-state.json"
        if not state_file.is_file():
            return None
        payload = json.loads(state_file.read_text(encoding="utf-8-sig"))
        pid = int(payload.get("pid") or 0)
        return pid if _pid_alive(pid) else None
    except (OSError, json.JSONDecodeError, ValueError):
        return None

def _external_running(name: str) -> bool:
    endpoint = PORTS.get(name)
    return bool(endpoint and _port_open(*endpoint))


def start_service(name: str, clean_start: bool = True) -> dict:
    if name not in SERVICE_ORDER:
        raise ValueError(f"Unknown service: {name}")

    if clean_start:
        _cleanup_service_before_start(name)

    if name == "recorder":
        stop_signal = ROOT / "runs" / "operational-recorder" / "stop.signal"
        try:
            stop_signal.unlink(missing_ok=True)
        except OSError:
            pass

    registry = _load_registry()
    services = registry["services"]
    current = services.get(name, {})
    current_pid = int(current.get("pid") or 0)

    if _pid_alive(current_pid):
        return service_status(name)

    recorder_pid = _current_recorder_pid() if name == "recorder" else None
    if recorder_pid and not clean_start:
        services[name] = {
            "pid": recorder_pid,
            "managed": False,
            "started_utc": None,
            "state": "running_external",
        }
        _save_registry(registry)
        return service_status(name)

    if name in PORTS and _external_running(name) and not clean_start:
        services[name] = {
            "pid": None,
            "managed": False,
            "started_utc": None,
            "state": "running_external",
        }
        _save_registry(registry)
        return service_status(name)

    command, cwd = _service_command(name)
    stdout_path = LOG_DIR / f"{name}.stdout.log"
    stderr_path = LOG_DIR / f"{name}.stderr.log"
    creationflags = 0
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0) | getattr(subprocess, "CREATE_NO_WINDOW", 0)

    with stdout_path.open("ab") as stdout, stderr_path.open("ab") as stderr:
        process = subprocess.Popen(
            command,
            cwd=str(cwd),
            stdin=subprocess.DEVNULL,
            stdout=stdout,
            stderr=stderr,
            creationflags=creationflags,
        )

    services[name] = {
        "pid": process.pid,
        "managed": True,
        "started_utc": _utc_now(),
        "state": "starting",
        "stdout": str(stdout_path),
        "stderr": str(stderr_path),
        "command": command,
    }
    _save_registry(registry)

    # Give fast-failing launchers a moment to report failure.
    time.sleep(0.35)
    return service_status(name)


def _kill_tree(pid: int) -> None:
    if os.name == "nt":
        subprocess.run(
            ["taskkill.exe", "/PID", str(pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return
    try:
        os.kill(pid, 15)
    except OSError:
        return


def stop_service(name: str) -> dict:
    if name not in SERVICE_ORDER:
        raise ValueError(f"Unknown service: {name}")

    registry = _load_registry()
    services = registry["services"]
    current = services.get(name, {})
    pid = int(current.get("pid") or 0)
    managed = bool(current.get("managed"))

    if name == "recorder":
        operational_dir = ROOT / "runs" / "operational-recorder"
        operational_dir.mkdir(parents=True, exist_ok=True)

        # Prevent the PowerShell supervisor from opening another window after
        # the current recorder-host exits.
        stop_signal = operational_dir / "stop.signal"
        stop_signal.write_text(_utc_now() + "\n", encoding="utf-8")

        # Ask recorder-host itself to finish MEDIA_END/EOS and close the shared
        # MXF writers. This is intentionally independent from RPS state.
        shutdown_signal = operational_dir / "shutdown.signal"
        shutdown_signal.write_text(_utc_now() + "\n", encoding="utf-8")

        recorder_pid = int(_current_recorder_pid() or 0)
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            host_alive = bool(recorder_pid and _pid_alive(recorder_pid))
            endpoint_busy = not _wait_endpoints_free("recorder", timeout_seconds=0.05)
            if not host_alive and not endpoint_busy:
                break
            time.sleep(0.15)

        # Fallback only: if graceful shutdown was not enough, terminate the
        # actual recorder-host and any process still owning the recorder RTSP port.
        fallback_pids: set[int] = set()
        if recorder_pid and _pid_alive(recorder_pid):
            fallback_pids.add(recorder_pid)
        fallback_pids.update(_windows_process_pids_by_name("recorder-host"))
        for _host, port, protocol in _service_endpoints("recorder"):
            fallback_pids.update(_windows_port_owner_pids(port, protocol))

        for fallback_pid in sorted(fallback_pids):
            if fallback_pid > 0 and fallback_pid != os.getpid() and _pid_alive(fallback_pid):
                _kill_tree(fallback_pid)

        # The supervisor should observe stop.signal and exit on its own. Kill it
        # only if it remains after the recorder-host is already down.
        supervisor_pid = pid
        supervisor_deadline = time.monotonic() + 4.0
        while supervisor_pid and _pid_alive(supervisor_pid) and time.monotonic() < supervisor_deadline:
            time.sleep(0.1)
        if supervisor_pid and _pid_alive(supervisor_pid):
            _kill_tree(supervisor_pid)

        _wait_endpoints_free("recorder", timeout_seconds=4.0)
    else:
        target_pid = pid
        if target_pid and _pid_alive(target_pid) and managed:
            _kill_tree(target_pid)
            for _ in range(20):
                if not _pid_alive(target_pid):
                    break
                time.sleep(0.1)

    services[name] = {
        **current,
        "pid": None,
        "state": "stopped",
        "stopped_utc": _utc_now(),
    }
    _save_registry(registry)
    return service_status(name)


def restart_service(name: str) -> dict:
    stop_service(name)
    time.sleep(0.25)
    return start_service(name, clean_start=True)


def _rps_detail() -> dict:
    state_path = RUNTIME_DIR / "rps-state.json"
    if not state_path.is_file():
        return {"mode": "gateway_runtime", "proxy_listener_available": False}
    try:
        payload = json.loads(state_path.read_text(encoding="utf-8-sig"))
        if isinstance(payload, dict):
            return payload
    except (OSError, json.JSONDecodeError):
        pass
    return {"mode": "gateway_runtime", "proxy_listener_available": False}


def service_status(name: str) -> dict:
    registry = _load_registry()
    current = registry["services"].get(name, {})
    pid = int(current.get("pid") or 0)
    managed_alive = bool(current.get("managed")) and _pid_alive(pid)
    port_alive = _external_running(name)

    running = managed_alive or port_alive
    state = "running" if running else "stopped"
    if name == "recorder":
        pointer = ROOT / "runs" / "operational-recorder" / "current-run.txt"
        if pointer.is_file():
            try:
                run = Path(pointer.read_text(encoding="utf-8-sig").strip())
                state_file = run / "operational-recorder-state.json"
                if state_file.is_file():
                    recorder = json.loads(state_file.read_text(encoding="utf-8-sig"))
                    recorder_pid = int(recorder.get("pid") or 0)
                    if _pid_alive(recorder_pid):
                        running = True
                        state = str(recorder.get("status") or "running").lower()
            except (OSError, json.JSONDecodeError, ValueError):
                pass

    result = {
        "name": name,
        "running": running,
        "state": state,
        "pid": pid or None,
        "managed": bool(current.get("managed")),
        "started_utc": current.get("started_utc"),
        "controllable": name in CONTROLLED_FROM_API,
    }
    if name in PORTS:
        result["host"] = PORTS[name][0]
        result["port"] = PORTS[name][1]
    if name == "rps":
        result["detail"] = _rps_detail()
    return result


def system_status() -> dict:
    return {
        "schema": "audio-system.system-status.v1",
        "checked_utc": _utc_now(),
        "services": {name: service_status(name) for name in SERVICE_ORDER},
        "start_order": list(SERVICE_ORDER),
        "stop_order": list(reversed(SERVICE_ORDER)),
    }


def start_system() -> dict:
    legacy_supervisors = _cleanup_legacy_dev_supervisors()
    if legacy_supervisors:
        # Give child Vite/API processes from the old supervisor enough time to
        # disappear before per-service port cleanup begins.
        time.sleep(0.75)

    results = {}
    for name in SERVICE_ORDER:
        results[name] = start_service(name, clean_start=True)
        # API/frontend need a short settling window before their dependents.
        time.sleep(0.5 if name in {"api", "frontend"} else 0.2)
    return {
        "action": "start_system",
        "legacy_supervisors_stopped": legacy_supervisors,
        "results": results,
        "status": system_status(),
    }


def stop_system() -> dict:
    results = {}
    for name in reversed(SERVICE_ORDER):
        results[name] = stop_service(name)
        time.sleep(0.15)
    return {"action": "stop_system", "results": results, "status": system_status()}


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("start-system")
    sub.add_parser("stop-system")
    action_parser = sub.add_parser("service")
    action_parser.add_argument("name", choices=SERVICE_ORDER)
    action_parser.add_argument("action", choices=("start", "stop", "restart", "status"))
    args = parser.parse_args()

    if args.command == "status":
        result = system_status()
    elif args.command == "start-system":
        result = start_system()
    elif args.command == "stop-system":
        result = stop_system()
    else:
        if args.action == "start":
            result = start_service(args.name, clean_start=True)
        elif args.action == "stop":
            result = stop_service(args.name)
        elif args.action == "restart":
            result = restart_service(args.name)
        else:
            result = service_status(args.name)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
