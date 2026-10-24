---
name: record-lab-solution
description: Write, run, and record a self-playing terminal walkthrough ("solution replay") for a lab in this Docker Sandboxes (sbx) training repo, producing solution.sh plus solution.log/solution.timing (util-linux scriptreplay) and solution.cast (asciinema). Use when adding a new lab, when a lab's commands change, when the user asks to "record the solution", "re-record lab NN", "make a replay/demo/cast", or to change how replays look.
---

# Recording lab solutions

Every lab in `labs/NN-name/` ships a replay of its solution in three files, all produced
from **one** real run against the live sbx daemon:

| File | Made by | Played with |
|---|---|---|
| `solution.sh` | you (hand-written) | `labs/NN-*/solution.sh` (live, types and runs commands) |
| `solution.log` + `solution.timing` | `script` (util-linux) | `scriptreplay --timing solution.timing solution.log` |
| `solution.cast` | converted from the same recording | `asciinema play solution.cast`, asciinema web player |

`script`/`scriptreplay` are preinstalled on every Ubuntu, so learners need nothing extra.
The `.cast` is for asciinema users and for embedding on the web.

## 1. Write `solution.sh`

Start every solution with the shared helper and use only these four calls:

```bash
#!/usr/bin/env bash
# Lab NN solution: replays the lab against your sbx daemon.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab NN — Title"                              # cyan narration line
run_quiet 'sbx rm --force lab-NN-x'               # idempotent setup, output hidden
run 'sbx create --name lab-NN-x shell ~/sbx-labs/NN'   # typed at human speed, then executed for real
run "sbx exec lab-NN-x sh -c '...'"                # use double quotes outside when the command has single quotes
say "Clean up"
run 'sbx rm --force lab-NN-x'
```

Rules that keep replays reliable:

- **Mirror the lab README.** Same sandbox names, same commands, same order. A replay that
  drifts from the README confuses learners.
- **Make it rerunnable.** First `run_quiet` deletes anything the script creates; last step
  cleans up.
- `run` executes with `bash -c`, so pipes, `;`, `&&`, `$(...)`, and subshells work. A failing
  command prints `[exit N]` and the script continues, which is intended for steps that
  *demonstrate* a denial.
- **Only touch `lab-*` sandboxes.** Never stop, remove, or exec into any other sandbox on
  the host. Lab workspaces live under `~/sbx-labs/NN`.
- **Use `sbx rm --force`.** The recording runs under a terminal, so a plain `sbx rm` would
  sit at its confirmation prompt.
- A sandbox made with `sbx create` stops after ~30 s with nothing attached, and the next
  `exec` prints a "started" line. That is fine in a replay; in tests, create sandboxes with
  `create_sandbox` (it uses `sbx run -d`) or use `run --separate-stderr`.
- `sbx run` (without `-d`) needs a terminal. It works in a recording; in tests wrap it in
  `script -qec '...' /dev/null`.
- Filter `sbx ls` to `lab-` rows so other sandboxes on the host do not land in the recording.
- Wait for asynchronous effects inside the command (`sleep 35; ...` for the idle stop)
  instead of relying on pauses.
- Never put real secrets in a solution. Use fake values (`sk-fake-training-key`) and
  explain the real flow in a `say` line.
- `chmod +x` the file.

`scripts/autoplay.sh` reads `PAUSE` (seconds between steps, default 1.5), `TYPE_SPEED`
(chars/sec, default 40, 0 = instant), and `INTERACTIVE=1` (wait for Enter).

## 2. Dry-run it fast

```bash
PAUSE=0 TYPE_SPEED=0 script -qec labs/NN-name/solution.sh /dev/null < /dev/null | tee /tmp/sol.txt
grep -n '\[exit' /tmp/sol.txt     # every hit must be a step that is *meant* to fail
```

Fix anything unexpected before recording. Recording takes as long as the replay.

## 3. Record

```bash
scripts/record-solution.sh labs/NN-name     # or: make record LAB=NN
```

The script:

1. runs `script --quiet --return --log-out solution.log --log-timing solution.timing
   --command "stty cols 110 rows 32; labs/NN-name/solution.sh"` at a fixed 110×32 size;
2. converts the log and timing into an asciinema v2 `solution.cast` (header line with
   `width`, `height`, `title`; then `[seconds, "o", text]` events), skipping the
   `Script started` header line;
3. prints the two replay commands.

`make record-all` re-records every lab in order. Run it after a version bump, after
`scripts/cleanup.sh`.

## 4. Verify the recording

```bash
scriptreplay -d 1000 --timing labs/NN-name/solution.timing labs/NN-name/solution.log | tail -5
python3 -c "import json,sys; [json.loads(l) for l in open('labs/NN-name/solution.cast')]; print('cast ok')"
grep -c '\[exit' labs/NN-name/solution.log
```

`-d 1000` replays 1000× faster. Then watch it once at normal speed with `make replay LAB=NN`.

## 5. Link it from the lab README

Each lab README ends with a **Watch the solution** block:

```markdown
## Watch the solution

    make replay LAB=NN              # scriptreplay, nothing to install
    make replay-cast LAB=NN         # asciinema
    labs/NN-name/solution.sh        # replay live against your own sbx daemon
```

Commit `solution.sh`, `solution.log`, `solution.timing`, and `solution.cast` together.
