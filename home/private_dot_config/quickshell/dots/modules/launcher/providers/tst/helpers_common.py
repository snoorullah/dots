"""Shared loader for the launcher-mode helper tests: imports `dots-launch-<mode>` by path."""
import importlib.machinery, importlib.util, json, os, shutil, subprocess, sys, tempfile, unittest


def repo_root():
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isfile(os.path.join(d, "tests", "lint.sh")):
        d = os.path.dirname(d)
    return d


BIN = os.path.join(repo_root(), "home", "private_dot_local", "private_bin")


def helper_path(mode):
    return os.path.join(BIN, "executable_dots-launch-" + mode)


def load(mode):
    path = helper_path(mode)
    loader = importlib.machinery.SourceFileLoader("dots_launch_" + mode, path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class Env(unittest.TestCase):
    """Temp dir + env isolation + an exec log, so no test runs a real action."""
    ENV = ()

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dlm.")
        self.saved = {k: os.environ.get(k) for k in list(self.ENV) + ["DOTS_LAUNCH_EXEC_LOG", "DOTS_LAUNCHER_STATE", "DOTS_HERDR_PANES"]}
        self.log = os.path.join(self.tmp, "exec.log")
        os.environ["DOTS_LAUNCH_EXEC_LOG"] = self.log
        os.environ["DOTS_LAUNCHER_STATE"] = os.path.join(self.tmp, "state")
        os.environ["DOTS_HERDR_PANES"] = os.path.join(self.tmp, "no-panes.json")

    def tearDown(self):
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(self.tmp, ignore_errors=True)

    def logged(self):
        try:
            return [json.loads(x) for x in open(self.log).read().splitlines()]
        except OSError:
            return []

    def write(self, rel, text, mode=None):
        p = os.path.join(self.tmp, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(text)
        if mode:
            os.chmod(p, mode)
        return p

    def run_cli(self, mode, *args):
        r = subprocess.run([sys.executable, helper_path(mode)] + list(args), capture_output=True, text=True, timeout=30, env=dict(os.environ))
        return r.returncode, json.loads(r.stdout)
