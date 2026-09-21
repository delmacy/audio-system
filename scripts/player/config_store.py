"""Persistent configuration registry for CWP, SIP services and media gateways."""

from __future__ import annotations

import ipaddress
import re
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

SEED_GATEWAY = (
    "Gateway SIP/RTSP Local",
    "10.10.0.20",
    5060,
    "rtsp://10.10.0.10:8554",
)

SEED_SERVICES = [
    ("RADIO", "TWR-SIM 121.500", "sip:twr-sim-121500@10.10.0.20:5060"),
    ("RADIO", "TWR-SIM 118.700", "sip:twr-sim-118700@10.10.0.20:5060"),
    ("RADIO", "APP-SIM 125.800", "sip:app-sim-125800@10.10.0.20:5060"),
    ("RADIO", "APP-SIM 127.300", "sip:app-sim-127300@10.10.0.20:5060"),
    ("RADIO", "GND-SIM 121.900", "sip:gnd-sim-121900@10.10.0.20:5060"),
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


def _column_names(con: sqlite3.Connection, table: str) -> set[str]:
    return {str(row["name"]) for row in con.execute(f"PRAGMA table_info({table})")}


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

            CREATE TABLE IF NOT EXISTS sip_gateway (
                id TEXT PRIMARY KEY,
                label TEXT NOT NULL UNIQUE,
                ip TEXT NOT NULL,
                sip_port INTEGER NOT NULL,
                rtsp_base_url TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
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

        service_columns = _column_names(con, "service")
        if "sip_uri" not in service_columns:
            con.execute("ALTER TABLE service ADD COLUMN sip_uri TEXT")
        if "gateway_id" not in service_columns:
            con.execute("ALTER TABLE service ADD COLUMN gateway_id TEXT")

        for key, value in DEFAULT_SETTINGS.items():
            con.execute("INSERT OR IGNORE INTO system_setting(key,value) VALUES(?,?)", (key, value))

        if con.execute("SELECT COUNT(*) FROM cwp").fetchone()[0] == 0:
            now = utc_now()
            for label, ip, side in SEED_CWPS:
                con.execute(
                    "INSERT INTO cwp(id,label,ip,side,enabled,ip_source,created_at,updated_at) VALUES(?,?,?,?,1,'manual',?,?)",
                    (str(uuid.uuid4()), label, ip, side, now, now),
                )

        if con.execute("SELECT COUNT(*) FROM sip_gateway").fetchone()[0] == 0:
            now = utc_now()
            con.execute(
                """
                INSERT INTO sip_gateway(id,label,ip,sip_port,rtsp_base_url,enabled,created_at,updated_at)
                VALUES(?,?,?,?,?,1,?,?)
                """,
                (str(uuid.uuid4()), *SEED_GATEWAY, now, now),
            )

        gateway_id = str(con.execute("SELECT id FROM sip_gateway ORDER BY created_at LIMIT 1").fetchone()["id"])

        if con.execute("SELECT COUNT(*) FROM service").fetchone()[0] == 0:
            now = utc_now()
            for kind, label, _legacy_uri in SEED_SERVICES:
                try:
                    sip_user = _service_sip_user(label)
                    gateway = con.execute(
                        "SELECT ip,sip_port FROM sip_gateway WHERE id=?",
                        (gateway_id,),
                    ).fetchone()
                    sip_uri = f"sip:{sip_user}@{gateway['ip']}:{int(gateway['sip_port'])}"
                    con.execute(
                        """
                        INSERT INTO service(id,kind,label,endpoint,sip_uri,gateway_id,enabled,created_at,updated_at)
                        VALUES(?,?,?,?,?,?,1,?,?)
                        """,
                        (str(uuid.uuid4()), kind, label, sip_uri, sip_uri, gateway_id, now, now),
                    )
                except ValueError:
                    pass
        else:
            # Migrate existing services to the current RPS-derived SIP addressing rule.
            rows = con.execute("SELECT id,label,gateway_id FROM service").fetchall()
            for row in rows:
                selected_gateway = str(row["gateway_id"]) if row["gateway_id"] else gateway_id
                try:
                    sip_uri, selected_gateway = _service_sip_uri(con, str(row["label"]), selected_gateway)
                    con.execute(
                        "UPDATE service SET endpoint=?,sip_uri=?,gateway_id=? WHERE id=?",
                        (sip_uri, sip_uri, selected_gateway, str(row["id"])),
                    )
                except ValueError:
                    pass


def _setting(con: sqlite3.Connection, key: str) -> str:
    row = con.execute("SELECT value FROM system_setting WHERE key=?", (key,)).fetchone()
    if not row:
        raise RuntimeError(f"Missing system setting: {key}")
    return str(row["value"])


def get_network_config() -> dict:
    initialize()
    with connect() as con:
        network = _setting(con, "cwp_pool_network")
        start = _setting(con, "cwp_pool_start")
        end = _setting(con, "cwp_pool_end")
    return {
        "network": network,
        "start": start,
        "end": end,
        "allocation": "first_free_ascending",
    }


def update_network_config(network: str, start: str, end: str) -> dict:
    initialize()
    try:
        parsed_network = ipaddress.ip_network(network.strip(), strict=False)
    except ValueError as exc:
        raise ValueError("Invalid CWP network/CIDR") from exc
    if parsed_network.version != 4:
        raise ValueError("CWP network must be IPv4")

    start_ip = ipaddress.ip_address(start.strip())
    end_ip = ipaddress.ip_address(end.strip())
    if start_ip.version != 4 or end_ip.version != 4:
        raise ValueError("CWP pool must use IPv4")
    if start_ip not in parsed_network or end_ip not in parsed_network:
        raise ValueError("Pool start/end must belong to the configured CWP network")
    if int(end_ip) < int(start_ip):
        raise ValueError("Pool end must be greater than or equal to pool start")

    usable = int(end_ip) - int(start_ip) + 1
    with connect() as con:
        count = int(con.execute("SELECT COUNT(*) FROM cwp").fetchone()[0])
        if usable < count:
            raise ValueError(f"CWP pool has {usable} addresses but {count} CWP are registered")
        con.execute("UPDATE system_setting SET value=? WHERE key='cwp_pool_network'", (str(parsed_network),))
        con.execute("UPDATE system_setting SET value=? WHERE key='cwp_pool_start'", (str(start_ip),))
        con.execute("UPDATE system_setting SET value=? WHERE key='cwp_pool_end'", (str(end_ip),))
    return get_network_config()


def renew_cwp_ips() -> dict:
    initialize()
    config = get_network_config()
    network = ipaddress.ip_network(config["network"], strict=False)
    start = ipaddress.ip_address(config["start"])
    end = ipaddress.ip_address(config["end"])
    addresses = [str(ipaddress.ip_address(value)) for value in range(int(start), int(end) + 1)]
    addresses = [value for value in addresses if ipaddress.ip_address(value) in network]

    with connect() as con:
        rows = con.execute(
            "SELECT id,label,side,created_at FROM cwp ORDER BY created_at,label"
        ).fetchall()
        if len(addresses) < len(rows):
            raise ValueError(
                f"CWP pool has {len(addresses)} addresses but {len(rows)} CWP are registered"
            )

        now = utc_now()
        # Two-phase update avoids UNIQUE(ip) collisions while the transaction is open.
        for row in rows:
            con.execute(
                "UPDATE cwp SET ip=?,updated_at=? WHERE id=?",
                (f"__renew__:{row['id']}", now, str(row["id"])),
            )

        assignments = []
        for row, assigned_ip in zip(rows, addresses):
            con.execute(
                "UPDATE cwp SET ip=?,ip_source='auto',updated_at=? WHERE id=?",
                (assigned_ip, now, str(row["id"])),
            )
            assignments.append({
                "id": str(row["id"]),
                "label": str(row["label"]),
                "side": str(row["side"]),
                "ip": assigned_ip,
            })

    return {
        "network": config,
        "count": len(assignments),
        "assignments": assignments,
    }


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
        raise ValueError("IP must be IPv4")
    return str(parsed)


def _service_sip_user(label: str) -> str:
    matches = re.findall(r"\d+(?:\.\d+)*", label)
    if not matches:
        raise ValueError("Service name must contain a ramal or frequency number")
    value = re.sub(r"\D", "", matches[-1])
    if not value:
        raise ValueError("Could not derive SIP user from service name")
    return value


def _service_sip_uri(con: sqlite3.Connection, label: str, gateway_id: str | None) -> tuple[str, str]:
    selected_gateway = _validate_gateway_for_service(con, gateway_id)
    row = con.execute(
        "SELECT ip,sip_port FROM sip_gateway WHERE id=? AND enabled=1",
        (selected_gateway,),
    ).fetchone()
    if not row:
        raise ValueError("Selected RPS does not exist or is disabled")
    sip_user = _service_sip_user(label)
    return f"sip:{sip_user}@{row['ip']}:{int(row['sip_port'])}", selected_gateway


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


def update_cwp(record_id: str, label: str, side: str, ip: str) -> dict:
    initialize()
    label = label.strip()
    side = side.strip().upper()
    if not label:
        raise ValueError("CWP label is required")
    if side not in {"A", "B"}:
        raise ValueError("CWP side must be A or B")
    assigned_ip = _validate_ip(ip)
    now = utc_now()
    try:
        with connect() as con:
            cursor = con.execute(
                "UPDATE cwp SET label=?,ip=?,side=?,ip_source='manual',updated_at=? WHERE id=?",
                (label, assigned_ip, side, now, record_id),
            )
            if cursor.rowcount == 0:
                raise LookupError("CWP not found")
    except sqlite3.IntegrityError as exc:
        raise ValueError("CWP label or IP already exists") from exc
    return get_cwp(record_id)


def delete_cwp(record_id: str) -> None:
    initialize()
    with connect() as con:
        cursor = con.execute("DELETE FROM cwp WHERE id=?", (record_id,))
        if cursor.rowcount == 0:
            raise LookupError("CWP not found")


def list_gateways() -> list[dict]:
    initialize()
    with connect() as con:
        rows = con.execute("""
            SELECT id,label,ip,sip_port,rtsp_base_url,enabled,created_at,updated_at
            FROM sip_gateway ORDER BY label
        """).fetchall()
    return [dict(row) | {"enabled": bool(row["enabled"])} for row in rows]


def get_gateway(record_id: str) -> dict:
    with connect() as con:
        row = con.execute("""
            SELECT id,label,ip,sip_port,rtsp_base_url,enabled,created_at,updated_at
            FROM sip_gateway WHERE id=?
        """, (record_id,)).fetchone()
    if not row:
        raise LookupError("Gateway not found")
    return dict(row) | {"enabled": bool(row["enabled"])}


def create_gateway(label: str, ip: str, sip_port: int, rtsp_base_url: str) -> dict:
    initialize()
    label = label.strip()
    ip = _validate_ip(ip)
    rtsp_base_url = rtsp_base_url.strip().rstrip("/")
    if not label:
        raise ValueError("Gateway label is required")
    if not 1 <= int(sip_port) <= 65535:
        raise ValueError("SIP port must be between 1 and 65535")
    if not rtsp_base_url.lower().startswith("rtsp://"):
        raise ValueError("RTSP base URL must start with rtsp://")
    record_id = str(uuid.uuid4())
    now = utc_now()
    try:
        with connect() as con:
            con.execute(
                """
                INSERT INTO sip_gateway(id,label,ip,sip_port,rtsp_base_url,enabled,created_at,updated_at)
                VALUES(?,?,?,?,?,1,?,?)
                """,
                (record_id, label, ip, int(sip_port), rtsp_base_url, now, now),
            )
    except sqlite3.IntegrityError as exc:
        raise ValueError("Gateway label already exists") from exc
    return get_gateway(record_id)


def update_gateway(record_id: str, label: str, ip: str, sip_port: int, rtsp_base_url: str) -> dict:
    initialize()
    label = label.strip()
    ip = _validate_ip(ip)
    rtsp_base_url = rtsp_base_url.strip().rstrip("/")
    if not label:
        raise ValueError("Gateway label is required")
    if not 1 <= int(sip_port) <= 65535:
        raise ValueError("SIP port must be between 1 and 65535")
    if not rtsp_base_url.lower().startswith("rtsp://"):
        raise ValueError("RTSP base URL must start with rtsp://")
    now = utc_now()
    try:
        with connect() as con:
            cursor = con.execute(
                """
                UPDATE sip_gateway
                SET label=?,ip=?,sip_port=?,rtsp_base_url=?,updated_at=?
                WHERE id=?
                """,
                (label, ip, int(sip_port), rtsp_base_url, now, record_id),
            )
            if cursor.rowcount == 0:
                raise LookupError("Gateway not found")
            services = con.execute(
                "SELECT id,label FROM service WHERE gateway_id=?",
                (record_id,),
            ).fetchall()
            for service in services:
                try:
                    sip_uri, _ = _service_sip_uri(con, str(service["label"]), record_id)
                    con.execute(
                        "UPDATE service SET endpoint=?,sip_uri=?,updated_at=? WHERE id=?",
                        (sip_uri, sip_uri, now, str(service["id"])),
                    )
                except ValueError:
                    pass
    except sqlite3.IntegrityError as exc:
        raise ValueError("Gateway label already exists") from exc
    return get_gateway(record_id)


def delete_gateway(record_id: str) -> None:
    initialize()
    with connect() as con:
        used = con.execute("SELECT COUNT(*) FROM service WHERE gateway_id=?", (record_id,)).fetchone()[0]
        if used:
            raise ValueError("Gateway is in use by one or more radio services")
        cursor = con.execute("DELETE FROM sip_gateway WHERE id=?", (record_id,))
        if cursor.rowcount == 0:
            raise LookupError("Gateway not found")


def list_services() -> list[dict]:
    initialize()
    with connect() as con:
        rows = con.execute("""
            SELECT
                s.id,s.kind,s.label,s.endpoint,s.sip_uri,s.gateway_id,s.enabled,s.created_at,s.updated_at,
                g.label AS gateway_label,g.rtsp_base_url AS gateway_rtsp_base_url
            FROM service s
            LEFT JOIN sip_gateway g ON g.id=s.gateway_id
            ORDER BY s.kind,s.label
        """).fetchall()
    result = []
    for row in rows:
        item = dict(row)
        item["enabled"] = bool(row["enabled"])
        item["legacy_rtsp"] = item["kind"] == "RADIO" and not item["sip_uri"] and str(item["endpoint"]).lower().startswith("rtsp://")
        result.append(item)
    return result


def get_service(record_id: str) -> dict:
    initialize()
    with connect() as con:
        row = con.execute("""
            SELECT
                s.id,s.kind,s.label,s.endpoint,s.sip_uri,s.gateway_id,s.enabled,s.created_at,s.updated_at,
                g.label AS gateway_label,g.rtsp_base_url AS gateway_rtsp_base_url
            FROM service s
            LEFT JOIN sip_gateway g ON g.id=s.gateway_id
            WHERE s.id=?
        """, (record_id,)).fetchone()
    if not row:
        raise LookupError("Service not found")
    item = dict(row)
    item["enabled"] = bool(row["enabled"])
    item["legacy_rtsp"] = item["kind"] == "RADIO" and not item["sip_uri"] and str(item["endpoint"]).lower().startswith("rtsp://")
    return item


def _validate_gateway_for_service(con: sqlite3.Connection, gateway_id: str | None) -> str:
    if not gateway_id:
        raise ValueError("Service requires an RPS (RTSP Proxy)")
    row = con.execute("SELECT id FROM sip_gateway WHERE id=? AND enabled=1", (gateway_id,)).fetchone()
    if not row:
        raise ValueError("Selected RPS does not exist or is disabled")
    return str(row["id"])


def create_service(kind: str, label: str, gateway_id: str | None = None) -> dict:
    initialize()
    kind = kind.strip().upper()
    label = label.strip()
    if kind not in {"RADIO", "TEL"}:
        raise ValueError("Service kind must be RADIO or TEL")
    if not label:
        raise ValueError("Service label is required")
    record_id = str(uuid.uuid4())
    now = utc_now()
    try:
        with connect() as con:
            sip_uri, selected_gateway = _service_sip_uri(con, label, gateway_id)
            con.execute(
                """
                INSERT INTO service(id,kind,label,endpoint,sip_uri,gateway_id,enabled,created_at,updated_at)
                VALUES(?,?,?,?,?,?,1,?,?)
                """,
                (record_id, kind, label, sip_uri, sip_uri, selected_gateway, now, now),
            )
    except sqlite3.IntegrityError as exc:
        raise ValueError("Service label or SIP URI already exists") from exc
    return get_service(record_id)


def update_service(record_id: str, kind: str, label: str, gateway_id: str | None = None) -> dict:
    initialize()
    kind = kind.strip().upper()
    label = label.strip()
    if kind not in {"RADIO", "TEL"}:
        raise ValueError("Service kind must be RADIO or TEL")
    if not label:
        raise ValueError("Service label is required")
    now = utc_now()
    try:
        with connect() as con:
            sip_uri, selected_gateway = _service_sip_uri(con, label, gateway_id)
            cursor = con.execute(
                """
                UPDATE service
                SET kind=?,label=?,endpoint=?,sip_uri=?,gateway_id=?,updated_at=?
                WHERE id=?
                """,
                (kind, label, sip_uri, sip_uri, selected_gateway, now, record_id),
            )
            if cursor.rowcount == 0:
                raise LookupError("Service not found")
    except sqlite3.IntegrityError as exc:
        raise ValueError("Service label or SIP URI already exists") from exc
    return get_service(record_id)


def delete_service(record_id: str) -> None:
    initialize()
    with connect() as con:
        cursor = con.execute("DELETE FROM service WHERE id=?", (record_id,))
        if cursor.rowcount == 0:
            raise LookupError("Service not found")


def configuration_snapshot() -> dict:
    return {
        "schema": "audio-system.configuration.v2",
        "database": str(DB_PATH),
        "network": get_network_config() | {
            "next_cwp_ip": next_cwp_ip(),
        },
        "cwps": list_cwps(),
        "gateways": list_gateways(),
        "services": list_services(),
    }


initialize()
