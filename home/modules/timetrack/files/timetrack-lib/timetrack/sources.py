"""Read-only normalized readers for taskwarrior / timewarrior / ActivityWatch / logind."""
import json, subprocess
import requests
from . import config

WINDOW_BUCKET = "aw-watcher-window_devsupreme"
AFK_BUCKET = "aw-watcher-afk_devsupreme"

_TASK_KEYS = ["uuid","description","project","status","tags","entry","modified","due","end","urgency","salah_status"]

def _run(cmd: list[str]) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout

def read_tasks() -> list[dict]:
    data = json.loads(_run([config.TASK, "export"]) or "[]")
    return [{k: t.get(k) for k in _TASK_KEYS} for t in data]

def read_intervals() -> list[dict]:
    data = json.loads(_run([config.TIMEW, "export"]) or "[]")
    return [{"start": i.get("start"), "end": i.get("end"), "tags": i.get("tags", [])} for i in data]

def list_aw_buckets() -> list[str]:
    return list(requests.get(f"{config.AW_BASE}/api/0/buckets/", timeout=10).json())

def read_aw_events(bucket: str, start_iso: str, end_iso: str) -> list[dict]:
    r = requests.get(f"{config.AW_BASE}/api/0/buckets/{bucket}/events",
                     params={"start": start_iso, "end": end_iso, "limit": -1}, timeout=30)
    if r.status_code == 404:
        return []
    r.raise_for_status()
    return r.json()

def read_logind() -> list[dict]:
    if not config.LOGIND_JSONL.exists():
        return []
    out = []
    for line in config.LOGIND_JSONL.read_text().splitlines():
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out
