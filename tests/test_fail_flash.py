import os
import pty
import select
import unittest

from support import REPO, Sandbox

FAIL_BASH = REPO / "extras" / "afterburn-fail.bash"


# Every flash frame starts with an erase-line escape; the glyph itself is not in every frame.
def interactive(sb, keys, histcontrol="ignoreboth", after=""):
    """Run a real interactive bash in a pty; return the output after sourcing, then after each key line."""
    env = sb.env(HISTCONTROL=histcontrol, PS1="> ")
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(str(sb.bin / "bash"), ["bash", "--norc", "--noprofile", "-i"], env)

    def read(wait=0.3):
        out = b""
        while select.select([fd], [], [], wait)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        return out.decode(errors="replace")

    read()
    os.write(fd, f"source {FAIL_BASH}{after}\n".encode())
    seen = [read(0.9)]   # [0] = what the first prompt after sourcing printed
    for k in keys:
        os.write(fd, k.encode())
        seen.append(read(0.9))
    os.write(fd, b"exit\n")
    os.waitpid(pid, 0)
    return seen


class FailFlashTests(unittest.TestCase):
    def flashes(self, keys, **kw):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        return ["\x1b[2K" in out for out in interactive(sb, keys, **kw)[1:]]

    def test_empty_enter_after_a_failure_does_not_replay(self):
        self.assertEqual(self.flashes(["false\n", "\n", "\n", "true\n"]), [True, False, False, False])

    def test_same_failing_command_twice_still_flashes_with_ignoredups(self):
        # Omarchy sets HISTCONTROL=ignoreboth: the second `false` is not a new history entry.
        self.assertEqual(self.flashes(["false\n", "false\n"]), [True, True])
        self.assertEqual(self.flashes(["false\n", "false\n"], histcontrol="ignoreboth:erasedups"), [True, True])

    def test_first_prompt_does_not_flash(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        # the line that installs the hook ends with $? = 1, as when the last line of a bashrc fails
        out = interactive(sb, [], after="; false")[0]
        self.assertNotIn("\x1b[2K", out)


if __name__ == "__main__":
    unittest.main()
