"""Shared test scaffolding: a scratch state dir, an in-memory Taskwarrior, no network."""
import os
import shutil
import sys
import tempfile
import unittest
import uuid as uuidlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from dots_overview import config, herdr, local_tt, tw  # noqa: E402


class Scratch(unittest.TestCase):
    """Every test gets its own state dir, work.conf and timetrack dir under one tmp root."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="dots-overview-test."))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.saved = (config.STATE_DIR, config.CONF, config.OPS_STATE, config.TT_DIR)
        config.STATE_DIR = self.root / "state"
        config.CONF = self.root / "work.conf"
        config.OPS_STATE = self.root / "ops"
        config.TT_DIR = self.root / "tt"
        self.addCleanup(lambda: (setattr(config, "STATE_DIR", self.saved[0]), setattr(config, "CONF", self.saved[1]),
                                 setattr(config, "OPS_STATE", self.saved[2]), setattr(config, "TT_DIR", self.saved[3])))
        # ActivityWatch lives on loopback; tests must not talk to the real one
        local_tt.AW, aw = "http://127.0.0.1:1/api/0", local_tt.AW
        self.addCleanup(setattr, local_tt, "AW", aw)
        # herdr and timewarrior are the machine's real ones; tests see neither
        herdr.run, real_run = (lambda *a, **k: None), herdr.run
        self.addCleanup(setattr, herdr, "run", real_run)
        # a poisoned proxy: anything that tries the network goes nowhere
        self._env = dict(os.environ)
        os.environ.update({"HTTP_PROXY": "http://127.0.0.1:1", "HTTPS_PROXY": "http://127.0.0.1:1",
                           "TIMEWARRIORDB": str(self.root / "no-timew")})
        os.environ.pop("GH_TOKEN", None)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(self._env)))


class FakeTw:
    """Replaces the module-level functions in `tw` with an in-memory task list."""

    def __init__(self, test):
        self.tasks = []
        self.log = []
        for name in ("pending", "export", "by_ref", "add", "modify", "done", "start", "completed_since"):
            old = getattr(tw, name)
            setattr(tw, name, getattr(self, "_" + name))
            test.addCleanup(setattr, tw, name, old)

    def seed(self, **kw):
        t = {"uuid": str(uuidlib.uuid4()), "status": "pending", "tags": [], "desc": kw.pop("desc", "x"),
             "description": "x", "id": len(self.tasks) + 1, "entry_ts": 1000, "start_ts": None, "end_ts": None,
             "srcsync_ts": None}
        t.update(kw)
        self.tasks.append(t)
        return t

    def _pending(self):
        return [t for t in self.tasks if t["status"] == "pending"]

    def _export(self, *flt):
        rows = self.tasks
        for f in flt:
            if f == "status:pending":
                rows = [t for t in rows if t["status"] == "pending"]
            elif f == "status:completed":
                rows = [t for t in rows if t["status"] == "completed"]
            elif f == "+mirror":
                rows = [t for t in rows if "mirror" in t["tags"]]
        return list(rows)

    def _completed_since(self, epoch):
        return [t for t in self.tasks if t["status"] == "completed" and (t.get("end_ts") or 0) >= epoch]

    def _by_ref(self, ref):
        hit = [t for t in self.tasks if t.get("ref") == ref]
        return hit[0] if hit else None

    def _add(self, desc, tags=(), **attrs):
        t = self.seed(desc=desc, tags=list(tags), **attrs)
        self.log.append(("add", desc, tuple(tags), attrs))
        return t["uuid"]

    def _modify(self, uuid, **attrs):
        for t in self.tasks:
            if t["uuid"] == uuid:
                t.update(attrs)
        self.log.append(("modify", uuid, attrs))

    def _done(self, uuid, **attrs):
        self._modify(uuid, **attrs)
        for t in self.tasks:
            if t["uuid"] == uuid:
                t.update(status="completed", end_ts=2000)
        self.log.append(("done", uuid))

    def _start(self, uuid):
        self._modify(uuid, start_ts=1500)
