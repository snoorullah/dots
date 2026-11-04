"""Move the Secret Service (org.freedesktop.secrets) from gnome-keyring to KeePassXC.

Every item is read from gnome-keyring into memory, the provider is switched, and the items
are written to KeePassXC with the same label, attributes and content type, so apps that
look secrets up by attribute (Chrome/Brave "Safe Storage", VS Code, Slack, gh, git) keep
working. Nothing is written to disk in plaintext. On any failure the switch is rolled back;
gnome-keyring's own files are never modified.
"""
import os
import subprocess
import sys
import time

import secretstorage

INI = sys.argv[1]
HOME = os.environ["HOME"]
CFG = os.environ.get("XDG_CONFIG_HOME", f"{HOME}/.config")
DATA = os.environ.get("XDG_DATA_HOME", f"{HOME}/.local/share")
DROPIN = f"{CFG}/systemd/user/gnome-keyring-daemon.service.d/50-no-secrets.conf"
DBUS_SVC = f"{DATA}/dbus-1/services/org.freedesktop.secrets.service"
KEEPASSXC = f"{HOME}/.nix-profile/bin/keepassxc"


def sh(*cmd, check=True):
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def provider(bus):
    r = sh("busctl", "--user", "status", "org.freedesktop.secrets", check=False)
    for line in r.stdout.splitlines():
        if line.startswith("Comm="):
            return line.split("=", 1)[1]
    return ""


def notify(msg):
    sh("notify-send", "-a", "dots-secrets", "Secret Service", msg, check=False)
    print(msg)


def ini_set(sec, key, val):
    sh("crudini", "--set", INI, sec, key, val)


def rollback():
    for p in (DROPIN, DBUS_SVC):
        if os.path.exists(p):
            os.remove(p)
    ini_set("FdoSecrets", "Enabled", "false")
    sh("systemctl", "--user", "daemon-reload", check=False)
    sh("systemctl", "--user", "restart", "gnome-keyring-daemon.service", check=False)
    sh("systemctl", "--user", "restart", "keepassxc.service", check=False)
    print("Rolled back: gnome-keyring is the Secret Service again; its keyring was not touched.")


def main():
    bus = secretstorage.dbus_init()
    who = provider(bus)
    if "keepassxc" in who:
        print("KeePassXC already provides the Secret Service. Nothing to do.")
        return 0
    if "gnome-keyring" not in who:
        print(f"Unexpected Secret Service provider: {who or 'none'}. Stopping.")
        return 1

    # 1. Read everything from gnome-keyring (it may prompt to unlock).
    items = []
    for coll in secretstorage.get_all_collections(bus):
        if coll.collection_path.endswith("/session"):
            continue
        if coll.is_locked():
            coll.unlock()
        for it in coll.get_all_items():
            if it.is_locked():
                it.unlock()
            items.append((it.get_label(), it.get_attributes(), it.get_secret(),
                          it.get_secret_content_type()))
    print(f"Read {len(items)} item(s) from gnome-keyring.")

    # 2. Switch: gnome-keyring keeps pkcs11 only; D-Bus activation starts KeePassXC.
    try:
        os.makedirs(os.path.dirname(DROPIN), exist_ok=True)
        with open(DROPIN, "w") as f:
            f.write("# dots-secrets: KeePassXC is the Secret Service; gnome-keyring keeps pkcs11 only.\n"
                    "[Service]\nExecStart=\n"
                    "ExecStart=/usr/bin/gnome-keyring-daemon --foreground --components=pkcs11 "
                    "--control-directory=%t/keyring\n")
        os.makedirs(os.path.dirname(DBUS_SVC), exist_ok=True)
        with open(DBUS_SVC, "w") as f:
            f.write(f"[D-BUS Service]\nName=org.freedesktop.secrets\nExec={KEEPASSXC}\n")
        ini_set("FdoSecrets", "Enabled", "true")
        ini_set("FdoSecrets", "ShowNotification", "false")
        ini_set("FdoSecrets", "ConfirmAccessItem", "true")
        ini_set("FdoSecrets", "ConfirmDeleteItem", "true")
        sh("systemctl", "--user", "daemon-reload")
        sh("systemctl", "--user", "restart", "gnome-keyring-daemon.service")
        sh("systemctl", "--user", "restart", "keepassxc.service")

        notify("Unlock the vault in KeePassXC. Then: Database > Database Settings > "
               "Secret Service Integration > expose the 'Secret Service' group.")
        coll = None
        for _ in range(600):  # up to 10 minutes
            time.sleep(1)
            if "keepassxc" not in provider(bus):
                continue
            try:
                bus = secretstorage.dbus_init()
                coll = secretstorage.get_default_collection(bus)
                if not coll.is_locked():
                    break
            except Exception:
                coll = None
        if coll is None or coll.is_locked():
            raise RuntimeError("KeePassXC did not expose an unlocked collection in 10 minutes")

        # 3. Write the items back.
        for label, attrs, secret, ctype in items:
            coll.create_item(label, attrs, secret, replace=True, content_type=ctype)
        notify(f"Copied {len(items)} item(s) into KeePassXC. gnome-keyring's file is kept as a backup.")
        return 0
    except Exception as e:
        print(f"Failed: {e}")
        rollback()
        return 1


sys.exit(main())
