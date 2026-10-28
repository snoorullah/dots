"""Desktop notifications with buttons. Same contract as timetrack.notify: no answer is
None, never a default; a timed-out question is closed so no dead button stays behind."""
import select
import subprocess
import time

popen = subprocess.Popen


def toast(app, summary, body="", urgency="normal", ms=8000):
    try:
        popen(["notify-send", "-a", app, "-u", urgency, "-t", str(ms), summary, body],
              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def _close(nid):
    try:
        popen(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
               "--object-path", "/org/freedesktop/Notifications",
               "--method", "org.freedesktop.Notifications.CloseNotification", str(nid)],
              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def ask(app, summary, body, actions, timeout, urgency="normal"):
    argv = ["notify-send", "-a", app, "-u", urgency, "-t", str(int(timeout * 1000)), "-p", "--wait"]
    argv += [f"--action={k}={label}" for k, label in actions] + [summary, body]
    try:
        proc = popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                     stderr=subprocess.DEVNULL, text=True)
    except OSError:
        return None
    keys, nid, answer = {k for k, _ in actions}, None, None
    deadline = time.monotonic() + timeout + 2
    try:
        while (left := deadline - time.monotonic()) > 0:
            if not select.select([proc.stdout], [], [], left)[0]:
                break
            line = proc.stdout.readline()
            if not line:
                break
            line = line.strip()
            if nid is None:
                nid = line
                continue
            if line in keys:
                answer = line
                break
    finally:
        if answer is None and nid is not None:
            _close(nid)
        try:
            proc.terminate(); proc.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            proc.kill()
    return answer
