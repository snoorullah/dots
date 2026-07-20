"""Stable sqlite-diffable dump + single-writer git backup of the observe DB."""
import json, subprocess
from pathlib import Path
import sqlite_utils
from . import config, db as dbmod

def dump(db_path, out_dir) -> None:
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    d = sqlite_utils.Database(db_path)
    for table in sorted(d.table_names()):
        if table.startswith("_"):
            continue
        pk = dbmod.PKS.get(table)
        cols = [c.name for c in d[table].columns]
        key = (lambda r: tuple(r.get(k) for k in ([pk] if isinstance(pk, str) else pk))) if pk else (lambda r: tuple(r.get(c) for c in cols))
        rows = sorted(d[table].rows, key=key)
        (out / f"{table}.metadata.json").write_text(json.dumps({"name": table, "columns": cols}, indent=2, sort_keys=True) + "\n")
        with (out / f"{table}.ndjson").open("w") as f:
            for r in rows:
                f.write(json.dumps([r[c] for c in cols], sort_keys=True) + "\n")

def _git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)

def push(repo=None, db_path=None) -> bool:
    repo = Path(repo or config.DATA_REPO); db_path = db_path or config.DB_PATH
    if not (repo / ".git").is_dir():
        return False                       # repo not set up yet — non-fatal
    _git(repo, "pull", "--quiet", "--no-rebase")      # single-writer: pull before write
    dump(db_path, repo / "tables")
    _git(repo, "add", "tables")
    if not _git(repo, "diff", "--cached", "--quiet").returncode:
        return True                        # nothing changed
    _git(repo, "commit", "--quiet", "-m", "rollup: refresh observe data")
    return _git(repo, "push", "--quiet").returncode == 0
