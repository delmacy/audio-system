"""Local process supervisor for the Audio System development runtime."""

from __future__ import annotations

import argparse
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
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _port_open(host: str, port: int, timeout: float = 0.15) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


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


def start_service(name: str) -> dict:
    if name not in SERVICE_ORDER:
        raise ValueError(f"Unknown service: {name}")
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

    if name == "recorder" and _current_recorder_pid():
        services[name] = {
            "pid": _current_recorder_pid(),
            "managed": False,
            "started_utc": None,
            "state": "running_external",
        }
        _save_registry(registry)
        return service_status(name)

    if name in PORTS and _external_running(name):
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
    if name == "recorder":
        stop_signal = ROOT / "runs" / "operational-recorder" / "stop.signal"
        stop_signal.parent.mkdir(parents=True, exist_ok=True)
        stop_signal.write_text(_utc_now() + "\n", encoding="utf-8")
    registry = _load_registry()
    services = registry["services"]
    current = services.get(name, {})
    pid = int(current.get("pid") or 0)
    managed = bool(current.get("managed"))

    target_pid = pid
    if name == "recorder" and not _pid_alive(target_pid):
        target_pid = int(_current_recorder_pid() or 0)

    if target_pid and _pid_alive(target_pid):
        if managed or name == "recorder":
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
    return start_service(name)


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
    results = {}
    for name in SERVICE_ORDER:
        results[name] = start_service(name)
        # API/frontend need a short settling window before their dependents.
        time.sleep(0.5 if name in {"api", "frontend"} else 0.2)
    return {"action": "start_system", "results": results, "status": system_status()}


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
            result = start_service(args.name)
        elif args.action == "stop":
            result = stop_service(args.name)
        elif args.action == "restart":
            result = restart_service(args.name)
        else:
            result = service_status(args.name)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
