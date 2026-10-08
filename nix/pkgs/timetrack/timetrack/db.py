"""SQLite schema + idempotent upserts (sqlite-utils)."""
import sqlite_utils
from . import config

PKS = {
    "tasks": "uuid",
    "intervals": "start",
    "sessions": "ts",
    "usage": ("date", "category", "app", "hour"),
    "web": ("date", "domain", "hour"),
    "breaks": "start",
    "salah": ("date", "prayer"),
    "daily_summary": "date",
    "adherence": "date",
    "reconciliation": "date",
}

def open_db(path=None) -> sqlite_utils.Database:
    return sqlite_utils.Database(path or config.DB_PATH)

def upsert(db: sqlite_utils.Database, table: str, records: list[dict]) -> None:
    if not records:
        return
    # store list/dict fields (e.g. tags) as JSON automatically
    db[table].upsert_all(records, pk=PKS[table], alter=True)
