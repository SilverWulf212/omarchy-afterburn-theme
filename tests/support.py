"""Hermetic sandbox for running Afterburn's real shell scripts.

Every test gets a throwaway HOME, a fake /sys/class/power_supply tree, a fake Omarchy
install root, and a PATH made of ONLY stub commands plus symlinks to the few coreutils the
scripts need. The real PATH is never used, so a real `omarchy-plugin-*`, `hyprctl`,
`systemctl` or `cursor-fx` can not run by accident.
"""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
LOCK_SH = REPO / "extras" / "lock" / "lock-embers.sh"
AFTERBURN = REPO / "extras" / "bin" / "afterburn"
WATCH = REPO / "extras" / "bin" / "afterburn-watch"
UNINSTALL = REPO / "extras" / "uninstall.sh"
INSTALL = REPO / "extras" / "install.sh"

# Real tools the scripts under test call. Everything else must be a stub.
TOOLS = ("bash awk sed grep cat jq mktemp install chmod cmp mv rm mkdir dirname basename id cp tail head "
         "sort readlink realpath tr date ls find rmdir env cut wc touch ln stat uniq tee sleep "
         "true false xargs").split()

LOCK_VIEW = """import QtQuick
Item {
    MultiEffect {
    }
    MouseArea {
    }
    BorderSurface {
    }
}
"""

# Same shape as /usr/share/omarchy/shell/plugins/lock/manifest.json in Omarchy 4.5: a "service" plugin whose
# entry point is Service.qml, marked as a lock by the "authentication" capability. Files: LockView.qml (the
# one the script patches), Service.qml, FingerprintModel.js, poster.sh.
MANIFEST = json.dumps({
    "schemaVersion": 1, "id": "omarchy.lock", "name": "Lock Screen", "version": "1.0.0", "author": "Omarchy",
    "omarchy": {"capabilities": ["authentication"]}, "kinds": ["service"], "keepLoaded": True,
    "entryPoints": {"service": "Service.qml"}}, indent=2) + "\n"

# --- stub commands (bash). SB = the sandbox root; every call is appended to $SB/calls.log ----------
STUBS = {
    "omarchy-plugin-list": r'''#!/bin/bash
echo "ID STATE SOURCE KINDS NAME"
for f in "$SB"/plugins/*.state; do
  [[ -e $f ]] || continue
  id=$(basename "$f" .state)
  case $id in omarchy.*) src=first-party ;; *) src=third-party ;; esac
  echo "$id $(cat "$f") $src service Name"
done
''',
    "omarchy-plugin-enable": r'''#!/bin/bash
echo "omarchy-plugin-enable $*" >> "$SB/calls.log"
id=${1:-}
[[ -f $SB/plugins/$id.state ]] || { echo "plugin '$id' is not known" >&2; exit 1; }
if [[ -e $SB/plugins/$id.islock ]]; then   # one lock screen at a time
  for f in "$SB"/plugins/*.islock; do echo disabled > "${f%.islock}.state"; done
fi
echo enabled > "$SB/plugins/$id.state"
echo "Enabled $id"
''',
    # Faithful to /usr/share/omarchy/bin/omarchy-plugin-clone: the new id is "${USER}.${source#omarchy.}",
    # the tool switches to it, and the shell refuses ids in the omarchy.* namespace (the issue #5 log line).
    "omarchy-plugin-clone": r'''#!/bin/bash
echo "omarchy-plugin-clone $* (USER=${USER:-})" >> "$SB/calls.log"
new_id="${USER:-$(id -un)}.${1#omarchy.}"
target="$HOME/.config/omarchy/plugins/$new_id"
[[ ! -e $target ]] || { echo "omarchy-plugin-clone: $target already exists" >&2; exit 1; }
[[ ${STUB_CLONE_FAIL:-} != pre ]] || { echo "omarchy-plugin-clone: boom" >&2; exit 1; }
mkdir -p "$HOME/.config/omarchy/plugins"
cp -a "$LOCK_EMBERS_OMARCHY_PATH/shell/plugins/lock" "$target"
jq --arg id "$new_id" '.id = $id | .name = "My Lock Screen" | .omarchy = (.omarchy + {clonedFrom: "omarchy.lock"})' \
  "$target/manifest.json" > "$target/manifest.json.tmp" && mv "$target/manifest.json.tmp" "$target/manifest.json"
[[ ${STUB_CLONE_BREAK_ANCHOR:-} != 1 ]] || sed -i 's/^    MouseArea {$/    MouseArea2 {/' "$target/LockView.qml"
for f in "$SB"/plugins/*.islock; do echo disabled > "${f%.islock}.state"; done   # switching away from the built-in
if [[ $new_id == omarchy.* ]]; then
  echo "WARN qml: PluginRegistry: plugin $new_id rejected: id is reserved for first-party Omarchy plugins" >&2
else
  echo enabled > "$SB/plugins/$new_id.state"; touch "$SB/plugins/$new_id.islock"
fi
[[ ${STUB_CLONE_FAIL:-} != mid ]] || { rm -rf "$target"; echo "omarchy-plugin-clone: boom after switching" >&2; exit 1; }
[[ ${STUB_CLONE_NODIR:-} != 1 ]] || rm -rf "$target"
echo "Cloned $1 to $target and switched to $new_id"
''',
    "omarchy-plugin-remove": r'''#!/bin/bash
echo "omarchy-plugin-remove $*" >> "$SB/calls.log"
id=$1
dir="$HOME/.config/omarchy/plugins/$id"
[[ -e $dir ]] || { echo "plugin '$id' is not installed" >&2; exit 1; }
was=$(cat "$SB/plugins/$id.state" 2>/dev/null || true)
cloned=$(jq -r '.omarchy.clonedFrom // empty' "$dir/manifest.json")
[[ $id == omarchy.* ]] || rm -f "$SB/plugins/$id.state" "$SB/plugins/$id.islock"
[[ $id != omarchy.* ]] || echo disabled > "$SB/plugins/$id.state"
mv "$dir" "$HOME/.config/omarchy/plugins/.$id.bak.1"
if [[ -n $cloned && $was == enabled && $id != omarchy.* ]]; then echo enabled > "$SB/plugins/$cloned.state"; fi
echo "Removed $id."
''',
    "omarchy-plugin-validate": r'''#!/bin/bash
echo "omarchy-plugin-validate $*" >> "$SB/calls.log"
[[ ${STUB_VALIDATE_FAIL:-} != 1 ]] || { echo "omarchy-plugin-validate: nope" >&2; exit 1; }
id=$(jq -r .id "$1/manifest.json")
[[ $id != omarchy.* ]] || { echo "omarchy-plugin-validate: plugin id '$id' uses the reserved omarchy.* namespace" >&2; exit 1; }
''',
    "omarchy-shell": "#!/bin/bash\nexit 0\n",
    "systemctl": r'''#!/bin/bash
echo "systemctl $*" >> "$SB/calls.log"
[[ $* == *is-active* ]] && echo "${STUB_WATCHER:-active}"
exit 0
''',
    "hyprctl": r'''#!/bin/bash
echo "hyprctl $*" >> "$SB/calls.log"
[[ $1 == configerrors ]] && printf '%s' "${STUB_CONFIGERRORS:-}"
exit 0
''',
    "cursor-fx": "#!/bin/bash\necho \"cursor-fx $*\" >> \"$SB/calls.log\"\n",
    "ghostty": "#!/bin/bash\nexit 0\n",
    # `afterburn` as the watcher calls it: just record it.
    "afterburn": "#!/bin/bash\necho \"afterburn $*\" >> \"$SB/calls.log\"\n",
}


class Sandbox:
    def __init__(self, user="alice"):
        self.user = user
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="afterburn-test-"))
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        self.sysfs = self.root / "sysfs"
        self.omarchy = self.root / "omarchy"
        for d in (self.home, self.bin, self.sysfs, self.root / "plugins"):
            d.mkdir(parents=True)
        self.calls = self.root / "calls.log"
        self.calls.touch()
        for t in TOOLS:
            real = shutil.which(t)
            if real:
                (self.bin / t).symlink_to(real)
        # `[` and `test` are builtins; nothing else is allowed through.
        self.use_stubs([k for k in STUBS if k != "afterburn"])
        lock = self.omarchy / "shell" / "plugins" / "lock"
        lock.mkdir(parents=True)
        (lock / "manifest.json").write_text(MANIFEST)
        (lock / "LockView.qml").write_text(LOCK_VIEW)
        (lock / "Service.qml").write_text("// service\n")
        self.set_plugin("omarchy.lock", "enabled")
        # The installed-theme path the CLI and hook expect, pointing at this checkout.
        themes = self.home / ".config" / "omarchy" / "themes"
        themes.mkdir(parents=True)
        (themes / "afterburn").symlink_to(REPO)
        self.write_state_text(self.home / ".local/state/omarchy/current/theme.name", "afterburn")

    # --- helpers -------------------------------------------------------------------------------
    def use_stubs(self, names):
        for n in names:
            p = self.bin / n
            p.write_text(STUBS[n])
            p.chmod(0o755)

    def write_state_text(self, path, text):
        path = pathlib.Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    @property
    def plugins_dir(self):
        return self.home / ".config" / "omarchy" / "plugins"

    @property
    def state_dir(self):
        return self.home / ".local" / "state" / "afterburn"

    @property
    def marker(self):
        return self.state_dir / "lock-embers"

    def set_plugin(self, pid, state, lock=True):
        """Register a plugin in the fake shell. lock=True: it is a lock screen (the stub keeps one active)."""
        (self.root / "plugins" / f"{pid}.state").write_text(state + "\n")
        if lock:
            (self.root / "plugins" / f"{pid}.islock").touch()

    def add_user_plugin(self, pid, state="enabled", *, lock=True, manifest="ok", folder=None):
        """A third-party plugin folder in ~/.config/omarchy/plugins. manifest: ok, broken (not JSON) or none."""
        self.set_plugin(pid, state, lock=lock)
        d = self.plugins_dir / (folder or pid)
        d.mkdir(parents=True)
        if manifest == "broken":
            (d / "manifest.json").write_text("{ this is not json")
        elif manifest == "ok":
            m = json.loads(MANIFEST)
            m.update(id=pid, name=pid)
            if lock:
                m["omarchy"] = {"capabilities": ["authentication"], "clonedFrom": "omarchy.lock"}
            else:
                m["omarchy"] = {}
                m["kinds"] = ["bar-widget"]
            (d / "manifest.json").write_text(json.dumps(m))

    def plugin_state(self, pid):
        f = self.root / "plugins" / f"{pid}.state"
        return f.read_text().strip() if f.exists() else None

    def enabled_locks(self):
        return sorted(f.name[:-len(".islock")] for f in (self.root / "plugins").glob("*.islock")
                      if (f.with_suffix(".state")).read_text().strip() == "enabled")

    def call_log(self):
        return self.calls.read_text().splitlines()

    def add_legacy_clone(self, pid, enabled=True):
        """An install made by the old script: ~/.config/omarchy/plugins/<user>.lock, active."""
        d = self.plugins_dir / pid
        d.mkdir(parents=True)
        m = json.loads(MANIFEST)
        m.update(id=pid, name="My Lock Screen")
        m["omarchy"]["clonedFrom"] = "omarchy.lock"
        (d / "manifest.json").write_text(json.dumps(m))
        (d / "Service.qml").write_text("// service\n")
        (d / "LockView.qml").write_text(LOCK_VIEW)
        (d / "EmberLayer.qml").write_text("// old embers ffc48a ff5a1f 7a3e16\n")
        self.set_plugin("omarchy.lock", "disabled")
        self.set_plugin(pid, "enabled" if enabled else "disabled")

    # --- power supplies --------------------------------------------------------------------------
    def supply(self, name, type_, scope=None, status=None, capacity=None, online=None):
        d = self.sysfs / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "type").write_text(type_ + "\n")
        for fname, val in (("scope", scope), ("status", status), ("capacity", capacity), ("online", online)):
            if val is not None:
                (d / fname).write_text(str(val) + "\n")

    # --- running things ---------------------------------------------------------------------------
    def env(self, **extra):
        e = {"PATH": str(self.bin), "HOME": str(self.home), "USER": self.user, "SB": str(self.root),
             "LOCK_EMBERS_OMARCHY_PATH": str(self.omarchy), "POWER_DIR": str(self.sysfs),
             "TERM": "dumb", "LANG": "C"}
        e.update(extra)
        return e

    def run(self, argv, **extra):
        return subprocess.run(argv, env=self.env(**extra), capture_output=True, text=True, timeout=60,
                              stdin=subprocess.DEVNULL)

    def lock(self, *args, **extra):
        return self.run(["/bin/bash", str(LOCK_SH), *args], **extra)

    def afterburn(self, *args, **extra):
        return self.run(["/bin/bash", str(AFTERBURN), *args], **extra)

    def watch_func(self, body, **extra):
        """Source the real afterburn-watch and run a snippet that calls its functions."""
        return self.run(["/bin/bash", "-c", f'source "{WATCH}"; {body}'], **extra)

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)
