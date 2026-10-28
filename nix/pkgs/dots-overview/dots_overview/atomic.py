"""Atomic file writes: a reader sees the old file or the new one, never half of one."""
import json
import os
import tempfile
from pathlib import Path


def _ensure_dir(path):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)


def write_text(path, text, mode=0o600):
    """Same-directory `*.tmp`, fsync, then os.replace. A crash leaves the tmp, not a torn target."""
    path = Path(path)
    _ensure_dir(path)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        # only a failure BEFORE the replace removes the tmp; after it the name is gone anyway
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_json(path, obj, mode=0o600):
    write_text(path, json.dumps(obj, separators=(",", ":"), ensure_ascii=False) + "\n", mode)


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default
