"""Persistent configuration registry for CWP and communication services."""

from __future__ import annotations

import ipaddress
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = ROOT / "data"
DB_PATH = DATA_DIR / "audio-system.sqlite"

DEFAULT_SETTINGS = {
    "cwp_pool_network": "10.20.1.0/24",
    "cwp_pool_start": "10.20.1.101",
    "cwp_pool_end": "10.20.1.254",
}

SEED_CWPS = [
    ("CWP-001", "10.20.1.101", "A"),
    ("CWP-002", "10.20.1.102", "A"),
    ("CWP-B01", "10.20.2.101", "B"),
    ("CWP-B02", "10.20.2.102", "B"),
]

SEED_SERVICES = [
    ("RADIO", "TWR-SIM 121.500", "rtsp://10.10.0.10:8554/sim-a01-r1"),
    ("RADIO", "TWR-SIM 118.700", "rtsp://10.10.0.10:8554/sim-a01-r2"),
    ("RADIO", "APP-SIM 125.800", "rtsp://10.10.0.10:8554/sim-a02-r1"),
    ("RADIO", "APP-SIM 127.300", "rtsp://10.10.0.10:8554/sim-a02-r2"),
    ("RADIO", "GND-SIM 121.900", "rtsp://10.10.0.10:8554/sim-b01-r1"),
    ("TEL", "TEL-SIM-050", "sip:sim-a01-t1@10.10.0.20:5060"),
    ("TEL", "TEL-SIM-051", "sip:sim-a02-t1@10.10.0.20:5060"),
    ("TEL", "TEL-SIM-060", "sip:sim-b01-t1@10.10.0.20:5060"),
    ("TEL", "TEL-SIM-061", "sip:sim-b02-t1@10.10.0.20:5060"),
]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def connect() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH, timeout=10)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys=ON")
    con.execute("PRAGMA journal_mode=WAL")
    return con


def initialize() -> None:
    with connect() as con:
        con.executescript("""
            CREATE TABLE IF NOT EXISTS system_setting (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS cwp (
                id TEXT PRIMARY KEY,
                label TEXT NOT NULL UNIQUE,
                ip TEXT NOT NULL UNIQUE,
                side TEXT NOT NULL CHECK(side IN ('A','B')),
                enabled INTEGER NOT NULL DEFAULT 1,
                ip_source TEXT NOT NULL CHECK(ip_source IN ('auto','manual')),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS service (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL CHECK(kind IN ('RADIO','TEL')),
                label TEXT NOT NULL,
                endpoint TEXT NOT NULL UNIQUE,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(kind, label)
            );

            CREATE TABLE IF NOT EXISTS cwp_radio_state (
                cwp_id TEXT NOT NULL REFERENCES cwp(id) ON DELETE CASCADE,
                service_id TEXT NOT NULL REFERENCES service(id) ON DELETE CASCADE,
                active INTEGER NOT NULL DEFAULT 0,
                source TEXT NOT NULL DEFAULT 'configuration',
                updated_at TEXT NOT NULL,
                PRIMARY KEY(cwp_id, service_id)
            );

            CREATE TABLE IF NOT EXISTS runtime_state (
                scope TEXT NOT NULL,
                state_key TEXT NOT NULL,
                value_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY(scope, state_key)
            );
        """)
        for key, value in DEFAULT_SETTINGS.items():
            con.execute("INSERT OR IGNORE INTO system_setting(key,value) VALUES(?,?)", (key, value))

        count = con.execute("SELECT COUNT(*) FROM cwp").fetchone()[0]
        if count == 0:
            now = utc_now()
            for label, ip, side in SEED_CWPS:
                con.execute(
                    "INSERT INTO cwp(id,label,ip,side,enabled,ip_source,created_at,updated_at) VALUES(?,?,?,?,1,'manual',?,?)",
                    (str(uuid.uuid4()), label, ip, side, now, now),
                )

        count = con.execute("SELECT COUNT(*) FROM service").fetchone()[0]
        if count == 0:
            now = utc_now()
            for kind, label, endpoint in SEED_SERVICES:
                con.execute(
                    "INSERT INTO service(id,kind,label,endpoint,enabled,created_at,updated_at) VALUES(?,?,?,?,1,?,?)",
                    (str(uuid.uuid4()), kind, label, endpoint, now, now),
                )


def _setting(con: sqlite3.Connection, key: str) -> str:
    row = con.execute("SELECT value FROM system_setting WHERE key=?", (key,)).fetchone()
    if not row:
        raise RuntimeError(f"Missing system setting: {key}")
    return str(row["value"])


def next_cwp_ip() -> str:
    initialize()
    with connect() as con:
        start = ipaddress.ip_address(_setting(con, "cwp_pool_start"))
        end = ipaddress.ip_address(_setting(con, "cwp_pool_end"))
        if start.version != 4 or end.version != 4 or int(end) < int(start):
            raise RuntimeError("Invalid CWP IPv4 allocation range")
        used = {str(row["ip"]) for row in con.execute("SELECT ip FROM cwp")}
        for value in range(int(start), int(end) + 1):
            candidate = str(ipaddress.ip_address(value))
            if candidate not in used:
                return candidate
    raise RuntimeError("CWP IP pool exhausted")


def _validate_ip(value: str) -> str:
    parsed = ipaddress.ip_address(value.strip())
    if parsed.version != 4:
        raise ValueError("CWP IP must be IPv4")
    return str(parsed)


def list_cwps() -> list[dict]:
    initialize()
    with connect() as con:
        rows = con.execute("""
            SELECT id,label,ip,side,enabled,ip_source,created_at,updated_at
            FROM cwp ORDER BY side,label
        """).fetchall()
    return [dict(row) | {"enabled": bool(row["enabled"])} for row in rows]


def create_cwp(label: str, side: str, ip: str | None = None) -> dict:
    initialize()
    label = label.strip()
    side = side.strip().upper()
    if not label:
        raise ValueError("CWP label is required")
    if side not in {"A", "B"}:
        raise ValueError("CWP side must be A or B")
    source = "manual" if ip and ip.strip() else "auto"
    assigned_ip = _validate_ip(ip) if source == "manual" else next_cwp_ip()
    now = utc_now()
    record_id = str(uuid.uuid4())
    try:
        with connect() as con:
            con.execute(
                "INSERT INTO cwp(id,label,ip,side,enabled,ip_source,created_at,updated_at) VALUES(?,?,?,?,1,?,?,?)",
                (record_id, label, assigned_ip, side, source, now, now),
            )
    except sqlite3.IntegrityError as exc:
        text = str(exc).lower()
        if "cwp.label" in text:
            raise ValueError(f"CWP label already exists: {label}") from exc
        if "cwp.ip" in text:
            raise ValueError(f"CWP IP already exists: {assigned_ip}") from exc
        raise
    return get_cwp(record_id)


def get_cwp(record_id: str) -> dict:
    with connect() as con:
        row = con.execute("""
            SELECT id,label,ip,side,enabled,ip_source,created_at,updated_at
            FROM cwp WHERE id=?
        """, (record_id,)).fetchone()
    if not row:
        raise LookupError("CWP not found")
    return dict(row) | {"enabled": bool(row["enabled"])}


def delete_cwp(record_id: str) -> None:
    initialize()
    with connect() as con:
        cursor = con.execute("DELETE FROM cwp WHERE id=?", (record_id,))
        if cursor.rowcount == 0:
            raise LookupError("CWP not found")


def list_services() -> list[dict]:
    initialize()
    with connect() as con:
        rows = con.execute("""
            SELECT id,kind,label,endpoint,enabled,created_at,updated_at
            FROM service ORDER BY kind,label
        """).fetchall()
    return [dict(row) | {"enabled": bool(row["enabled"])} for row in rows]


def create_service(kind: str, label: str, endpoint: str) -> dict:
    initialize()
    kind = kind.strip().upper()
    label = label.strip()
    endpoint = endpoint.strip()
    if kind not in {"RADIO", "TEL"}:
        raise ValueError("Service kind must be RADIO or TEL")
    if not label:
        raise ValueError("Service label is required")
    if not endpoint:
        raise ValueError("Service endpoint is required")
    now = utc_now()
    record_id = str(uuid.uuid4())
    try:
        with connect() as con:
            con.execute(
                "INSERT INTO service(id,kind,label,endpoint,enabled,created_at,updated_at) VALUES(?,?,?,?,1,?,?)",
                (record_id, kind, label, endpoint, now, now),
            )
    except sqlite3.IntegrityError as exc:
        raise ValueError("Service label or endpoint already exists") from exc
    return get_service(record_id)


def get_service(record_id: str) -> dict:
    with connect() as con:
        row = con.execute("""
            SELECT id,kind,label,endpoint,enabled,created_at,updated_at
            FROM service WHERE id=?
        """, (record_id,)).fetchone()
    if not row:
        raise LookupError("Service not found")
    return dict(row) | {"enabled": bool(row["enabled"])}


def delete_service(record_id: str) -> None:
    initialize()
    with connect() as con:
        cursor = con.execute("DELETE FROM service WHERE id=?", (record_id,))
        if cursor.rowcount == 0:
            raise LookupError("Service not found")


def configuration_snapshot() -> dict:
    return {
        "schema": "audio-system.configuration.v1",
        "database": str(DB_PATH),
        "network": {
            "allocation": "first_free_ascending",
            "next_cwp_ip": next_cwp_ip(),
        },
        "cwps": list_cwps(),
        "services": list_services(),
    }


initialize()
