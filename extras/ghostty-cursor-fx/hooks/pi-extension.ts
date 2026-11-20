// Cursor FX for Ghostty (see `cursor-fx`): the Enter signal when you send a prompt in pi,
// and the "done" signal when pi has finished and won't continue on its own.
// Copy to ~/.pi/agent/extensions/cursor-fx.ts and turn on "Show hardware cursor" in /settings.
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const BIN = join(homedir(), ".local/bin/cursor-fx");

// Fire and forget, never making pi wait. Not detached, so cursor-fx finds pi's terminal.
function signal(...args: string[]): void {
  if (!process.env.GHOSTTY_RESOURCES_DIR) return;
  spawn(BIN, ["signal", ...args], { stdio: "ignore" }).on("error", () => {}).unref();
}

export default function (pi: any) {
  // Only prompts typed in the editor, not ones sent by extensions or over RPC.
  pi.on("input", (event: any) => {
    if (event.source === "interactive") signal();
  });
  // agent_end isn't final (retries, compaction, queued messages); agent_settled is.
  pi.on("agent_settled", (event: any) => {
    if (!event.aborted) signal("done");
  });
}
