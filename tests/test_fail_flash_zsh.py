import os
import pty
import select
import shutil
import time
import unittest

from support import REPO, Sandbox

FAIL_ZSH = REPO / "extras" / "afterburn-fail.zsh"
ZSH = shutil.which("zsh")


def interactive(sb, keys, conf=True, after=""):
    """Run a real interactive zsh (no rc files) in a pty; return the output after sourcing, then after each key line."""
    c = sb.home / ".config/afterburn/afterburn.conf"
    if conf and not c.exists():
        sb.write_state_text(c, "")
    (sb.bin / "zsh").symlink_to(ZSH)
    env = sb.env()
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(str(sb.bin / "zsh"), ["zsh", "-f", "-i", "+Z"], env)   # +Z: no line editor, so the prompt ends the output

    def read():
        out = b""
        end = time.monotonic() + 5
        while not out.endswith(b"PRMT> ") and (left := end - time.monotonic()) > 0:
            if select.select([fd], [], [], left)[0]:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                out += chunk
        return out.decode(errors="replace")

    os.write(fd, b"PS1='PRMT> '\n")
    read()
    os.write(fd, f"source {FAIL_ZSH}{after}\n".encode())
    seen = [read()]
    for k in keys:
        os.write(fd, k.encode())
        seen.append(read())
    os.write(fd, b"exit\n")
    os.waitpid(pid, 0)
    return seen


@unittest.skipUnless(ZSH, "zsh not installed")
class FailFlashZshTests(unittest.TestCase):
    def flashes(self, keys, theme="afterburn", **kw):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.write_state_text(sb.home / ".local/state/omarchy/current/theme.name", theme + "\n")
        return ["\x1b[2K" in out for out in interactive(sb, keys, **kw)[1:]]

    def test_failure_flashes_and_empty_enter_or_success_does_not(self):
        self.assertEqual(self.flashes(["false\n", "\n", "true\n", "false\n"]), [True, False, False, True])

    def test_ctrl_c_and_ctrl_z_codes_and_no_motion_are_skipped(self):
        self.assertEqual(self.flashes(["(exit 130)\n", "(exit 148)\n", "NO_MOTION=1; false\n"]), [False, False, False])

    def test_editions_flash_other_themes_do_not(self):
        self.assertEqual(self.flashes(["false\n"], theme="afterburn-redline"), [True])
        self.assertEqual(self.flashes(["false\n"], theme="nord"), [False])
        self.assertEqual(self.flashes(["false\n"], theme="afterburnish"), [False])

    def test_no_conf_means_uninstalled(self):
        self.assertEqual(self.flashes(["false\n"], conf=False), [False])

    def test_fail_fx_off(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.write_state_text(sb.home / ".config/afterburn/afterburn.conf", "FAIL_FX=off  # quiet\n")
        self.assertEqual(["\x1b[2K" in o for o in interactive(sb, ["false\n"])[1:]], [False])

    def test_later_precmd_hooks_still_see_the_exit_code(self):
        # Starship reads $? in its own precmd: the flash must not hide the failure from it.
        out = Sandbox()
        self.addCleanup(out.cleanup)
        seen = interactive(out, ["false\n"], after="; mine() { print -r -- \"SAW=$?\" }; precmd_functions+=(mine)")
        self.assertIn("SAW=1", seen[1])

    def test_the_failed_command_text_is_shown(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.write_state_text(sb.home / ".config/afterburn/afterburn.conf", "FAIL_FX=burn\n")
        out = interactive(sb, ["ls_nope_xyz\n"])[1]
        plain = "".join(ch for ch in __import__("re").sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out))
        self.assertIn("✗ ls_nope_xyz", plain)

    def test_ksh_arrays_does_not_break_it(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.write_state_text(sb.home / ".config/afterburn/afterburn.conf", "FAIL_FX=burn\n")
        import re
        out = interactive(sb, ["setopt ksh_arrays; ls_nope_xyz\n"])[1]
        self.assertIn("✗ setopt ksh_arrays; ls_nope_xyz  exit 127", re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out))

    def test_hooks_install_even_when_stdout_is_redirected_while_sourcing(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        # As Powerlevel10k's instant prompt does: the rc line runs with stdout not a terminal.
        seen = interactive(sb, ["false\n"], after=" > /dev/null")
        self.assertIn("\x1b[2K", seen[1])


class ZshrcLineTests(unittest.TestCase):
    def test_install_adds_and_uninstall_removes_the_zshrc_line_through_a_symlink(self):
        from support import UNINSTALL
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        real = sb.root / "dotfiles" / ".zshrc"
        sb.write_state_text(real, "export FOO=1")   # no trailing newline
        (sb.home / ".zshrc").symlink_to(real)
        r = sb.install()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("afterburn-fail.zsh", real.read_text())
        self.assertTrue((sb.home / ".zshrc").is_symlink())
        r = sb.run(["/bin/bash", str(UNINSTALL)])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(real.read_text(), "export FOO=1")   # byte for byte
        self.assertTrue((sb.home / ".zshrc").is_symlink())

    def test_no_zshrc_means_no_zshrc(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        sb.install()
        self.assertFalse((sb.home / ".zshrc").exists())


if __name__ == "__main__":
    unittest.main()
