# Lab 08 (bonus) — What's new in sbx 0.51

**Goal:** upgrade from the course version (0.49.2) to **sbx v0.51.0**, understand the `sbx cp`
symlink fixes that make this upgrade worth doing, and try the new features that matter for the
rest of the course: query-parameter rules, custom mount targets, `--workdir`, and the stricter
checks.
**Time:** ~30 minutes. **Prerequisite:** Labs 00–07, or at least [Lab 01](../01-install-and-sign-in/README.md)
and [Lab 04](../04-l7-rules-and-approvals/README.md).

> This lab is the one place in the course that runs a **newer** sbx than `VERSION`. At the end
> you choose: stay on 0.51.0 (recommended, because of the security fixes) or roll back to
> 0.49.2 to match the other labs' output exactly. Section 9 shows both.

## What changed between 0.49.2 and 0.51.0

| Release | Date | What matters here |
|---|---|---|
| [v0.50.0](https://github.com/docker/sbx-releases/releases/tag/v0.50.0) | 2026-10-26 | `sbx cp` symlink fixes for alternate host paths, `--query` HTTP rules, `exec` exit code 125, host Git no longer runs programs set by the sandbox's `.git` |
| [v0.50.1](https://github.com/docker/sbx-releases/releases/tag/v0.50.1) | 2026-10-28 | Fix for sandboxes that did not start |
| [v0.51.0](https://github.com/docker/sbx-releases/releases/tag/v0.51.0) | 2026-11-03 | `sbx cp` blocks symlinks in mounted directories that escape to other host paths, built-in agents become **kits**, custom mount targets, `--workdir`, stricter `--sandbox` and custom-secret checks, clipboard copy off by default |

## 1. The security issue: `sbx cp` and symlinks

`sbx cp` copies files between your host and a sandbox, **with your host user's permissions**.
The workspace is shared live between the two, and the agent controls everything inside the
sandbox, including symbolic links it creates in the workspace. Suppose a link the agent planted
were followed **on the host side** during a copy. Then a copy you start could read a host file
(for example `~/.ssh/id_ed25519`) into the sandbox, or write sandbox data onto a host path
outside the workspace. That is a sandbox escape, even though the VM itself was never broken.

Docker has fixed this class of bug more than once:

- **CopyEscape, CVE-2026-17106** (a race in the tar stream that `docker cp` and `sbx cp` share),
  fixed in sbx **0.38.0**, according to
  [Imperva's write-up](https://www.imperva.com/blog/copyescape-taking-over-docker-hosts-with-docker-cp/).
- **v0.50.0:** "`sbx cp` rejects symbolic links that escape a sandbox workspace when the
  workspace is reached through an alternate host path, including a symlink or junction, macOS
  `/private/tmp`, or a Linux bind mount of a workspace subdirectory."
- **v0.51.0:** "`sbx cp` blocks symbolic links in mounted directories from escaping onto other
  host paths. On Windows, it also blocks workspace escapes through substituted drives."

> **About the CVE number.** Posts about the 0.51.0 fix cite **CVE-2026-103916**. On
> 2026-11-04 that ID was not in the release notes, the repository's security advisories, or
> any CVE database we could search. Treat the release notes above as the source, and check
> [the advisories](https://github.com/docker/sbx-releases/security) for an official ID.

**What to do:** if any agent you run in `sbx` might be malicious or prompt-injected, run 0.51.0
or later, and treat `sbx cp` on a sandbox path like unpacking an untrusted archive.

## 2. Upgrade to 0.51.0

Same steps as Lab 01, section 7. The daemon restart **stops every running sandbox**.

```shell
sudo apt-mark unhold docker-sbx
sudo apt-get install -y docker-sbx=0.51.0-1~ubuntu.24.04~noble
sudo apt-mark hold docker-sbx
sbx daemon restart
sbx version; sbx diagnose | grep -E 'Version match|passed'
```

```text
sbx version v0.51.0 7d55286de0c775148b985ed349f760f1eba06203
  ✓ Version match — v0.51.0
  15 passed · 1 warning · 4 skipped
```

Your existing sandboxes survive the upgrade and keep their old image. Section 3 shows the
difference.

## 3. Built-in agents are now kits

From 0.51.0, `shell`, `claude`, `codex` and the other built-in names resolve to **published kits**
at `docker.io/sbx/<name>`. The shell agent is no longer Ubuntu:

```shell
mkdir -p ~/sbx-labs/08/ws
sbx create --name lab-08-new shell ~/sbx-labs/08/ws
sbx run -d --name lab-08-new
sbx exec lab-08-new sh -c '. /etc/os-release; echo $PRETTY_NAME'
sbx inspect lab-08-new | grep -E 'Kits|Created with|Image:'
```

```text
  ○ shell — now ships as a kit; resolving docker.io/sbx/shell:latest
  ...
Docker Hardened Images/Debian GNU/Linux 13 (trixie)
  Kits:                    docker.io/sbx/shell@sha256:5548b2fa5e9d...
  Created with:            v0.51.0
  Image:                   sandbox-kit-assembled:86c8772c84b423df
```

A sandbox created by 0.49.2 still runs its old image, and `Created with` is empty because older
versions did not record it:

```text
$ sbx exec sbx-test sh -c '. /etc/os-release; echo $PRETTY_NAME'
Ubuntu 26.04.1 LTS
$ sbx inspect sbx-test | grep -E 'Created with|Image:'
  Created with:            -
  Image:                   docker/sandbox-templates:shell-docker
```

What this means for you:

- Old Claude and Codex sandboxes keep running, but you must **recreate** them before using
  `sbx kit add`, `sbx run --model` or `sbx move`. Push your work first.
- The first create after the upgrade pulls the new kit (about 37 s and 510 MB on the course host).
- Outputs in Labs 02–07 that show `Ubuntu 26.04` or `docker/sandbox-templates:shell-docker`
  now show Debian 13 and `docker.io/sbx/shell`.

## 4. Check: a planted symlink cannot reach host files

The agent plants three links in the workspace: one to a host file, one to a host directory, and
one to the workspace's parent directory.

```shell
echo "host-canary" > ~/sbx-labs/08/host-canary.txt; mkdir -p ~/sbx-labs/08/victim ~/sbx-labs/08/out
W=$HOME/sbx-labs/08/ws
sbx exec lab-08-new sh -c "ln -sfn $HOME/sbx-labs/08/host-canary.txt $W/notes.txt; ln -sfn $HOME/sbx-labs/08/victim $W/drop; ln -sfn .. $W/up; ls -l $W"
```

```text
lrwxrwxrwx 1 agent agent 30 Nov  4 15:52 drop -> /home/serra/sbx-labs/08/victim
lrwxrwxrwx 1 agent agent 39 Nov  4 15:52 notes.txt -> /home/serra/sbx-labs/08/host-canary.txt
lrwxrwxrwx 1 agent agent  2 Nov  4 15:52 up -> ..
```

The links exist on the host too, because the workspace is shared. Now you copy through them:

```shell
sbx cp lab-08-new:$W/notes.txt ~/sbx-labs/08/out/a.txt                    # read the host file?
sbx cp -L lab-08-new:$W/up/host-canary.txt ~/sbx-labs/08/out/c.txt        # read via the parent?
echo payload > ~/sbx-labs/08/out/payload.txt
sbx cp ~/sbx-labs/08/out/payload.txt lab-08-new:$W/drop/payload.txt       # write into a host dir?
sbx cp ~/sbx-labs/08/out/payload.txt lab-08-new:$W/up/escaped.txt         # write next to the workspace?
ls -A ~/sbx-labs/08/victim; ls ~/sbx-labs/08
```

```text
error: path "/home/serra/sbx-labs/08/ws/notes.txt" not found in container
error: path "/home/serra/sbx-labs/08/ws/up/host-canary.txt" not found in container
error: upload archive: request failed: 500 Internal Server Error: tar extract failed in sandbox "lab-08-new": tar: /home/serra/sbx-labs/08/ws/drop: Cannot open: No such file or directory ...
host-canary.txt  out  victim  ws
```

Every copy is **resolved inside the VM**, where the host paths do not exist: the reads fail, the
write into `drop/` fails, and `victim/` stays empty. The last copy "succeeds", but `escaped.txt`
lands in the VM's own `/home/serra/sbx-labs/08/`, not on your disk:

```shell
sbx exec lab-08-new ls /home/serra/sbx-labs/08/
```

```text
AGENTS.md  escaped.txt  kits-agent-context  ws
```

> **Honest note.** We ran the same commands on 0.49.2 and got the same answers: the simple case
> was already safe there. The 0.50 and 0.51 fixes cover paths this check does not hit: a
> workspace reached through a symlink or bind mount, extra mounted directories, Windows
> substituted drives, and the CopyEscape race. This check proves the basics still hold. It does
> not prove the fix. Upgrade anyway.

## 5. Query-parameter rules (0.50.0)

Lab 04 showed that HTTP rules matched method and path only. Now they can also require query
parameters:

```shell
sbx policy allow network --sandbox lab-08-new httpbin.org --method GET --path /anything/report --query format=csv
```

```text
Added rule 19307b21-... to policy local (scope: sandbox:lab-08-new): GET httpbin.org/anything/report?format=csv
```

```text
GET  /anything/report?format=csv                200
GET  /anything/report?format=json               403
GET  /anything/report                           403
GET  /anything/report?format=CSV                403
GET  /anything/report?format=csv&extra=1        200
GET  /anything/report?format=json&format=csv    200
GET  /anything/report?format=cs%76              200
POST /anything/report?format=csv                403
```

Read this table carefully:

- `--query` means **must include**, not **only**. Extra parameters pass, and so does a repeated
  `format` as long as one copy matches.
- Values are compared **after URL decoding** (`cs%76` is `csv`) and are case-sensitive.
- The **approval queue still shows only method, host and path**. A blocked
  `GET /anything/delete?id=42` appears as `GET httpbin.org:443/anything/delete`, so the person
  approving cannot see the query string they are approving.

## 6. Custom mount targets and `--workdir` (0.51.0)

Extra workspaces now take `PATH:TARGET[:ro]`, so a folder can appear somewhere other than its
host path:

```shell
mkdir -p ~/sbx-labs/08/docs && echo "docs from host" > ~/sbx-labs/08/docs/guide.txt
sbx create --name lab-08-mounts shell ~/sbx-labs/08/ws ~/sbx-labs/08/docs:/opt/docs:ro
sbx run -d --name lab-08-mounts
sbx exec lab-08-mounts sh -c 'cat /opt/docs/guide.txt; touch /opt/docs/x'
```

```text
  Workspace:  /home/serra/sbx-labs/08/ws (rw)
              /home/serra/sbx-labs/08/docs → /opt/docs (ro)
...
docs from host
touch: cannot touch '/opt/docs/x': Read-only file system
```

`sbx ls --json` and `sbx inspect` now list every configured host mount, so you can audit what a
sandbox can see. `--workdir` starts the agent in a subdirectory of the workspace:

```shell
mkdir -p ~/sbx-labs/08/ws/src
sbx run --rm --name lab-08-wd --workdir ~/sbx-labs/08/ws/src shell ~/sbx-labs/08/ws -- -c pwd
```

```text
/home/serra/sbx-labs/08/ws/src
```

## 7. Stricter checks

```shell
sbx policy allow network --sandbox "" example.org; echo "exit=$?"
sbx exec lab-08-nope true; echo "exit=$?"
sbx secret set-custom --sandbox lab-08-new --env NOHOST_TOKEN --value fake-nohost-123
```

```text
error: --sandbox must contain a non-empty value
exit=1
error: sandbox 'lab-08-nope' not found
  try: sbx ls
exit=125
error: --host is required
```

- An empty `--sandbox` used to apply the rule **globally**. A script with an unset variable
  (`--sandbox "$NAME"`) could open a host for every sandbox. Now it is refused.
- `exec` returns **125** when it cannot run the command (0.49.2 returned 1), so scripts can tell
  "sandbox missing" apart from "the command failed".
- A custom secret needs a destination host. Old mappings without one **stop substituting** after
  the upgrade; add `--host` again to repair them.

## 8. Clipboard and FUSE settings

```shell
sbx settings ls | grep -E 'clipboard|fuse'
```

```text
clipboard.imagePaste    false   bool   default   Allow sandboxed agents to read the host clipboa…
clipboard.textCopy      false   bool   default   Allow sandboxed processes to copy text to the h…
sandbox.fuse            true    bool   default   Expose /dev/fuse and grant SYS_ADMIN for mounti…
```

Copying text from a sandbox to your clipboard is now **off** until you turn it on. Leave it off
for agents you do not trust. A clipboard is another way out of the VM.

## 9. Clean up, and stay or roll back

```shell
sbx rm --force lab-08-new lab-08-mounts
rm -rf ~/sbx-labs/08
```

**Stay on 0.51.0 (recommended).** Most commands in Labs 02–07 work the same. On the course
host, the checks for Labs 01–05 gave **48 of 53** on 0.51.0. All five failures come from the
version pin or the new shell kit, not from the network or secret enforcement:

| Check | Why it fails on 0.51.0 |
|---|---|
| Lab 01: CLI and package are the course version (2 checks) | They test for 0.49.2 on purpose |
| Lab 02: cp copies a symlink as a link | `/etc/os-release` is a regular file in the Debian kit, not a link. `sbx cp` still copies a link as a link (tested with a link of our own) |
| Lab 03: direct connection by IP is caught | The connection is still blocked and logged as `transparent ... default deny`. The new image prints a Docker banner on stderr, and the check expects no output at all |
| Lab 05: SSH agent forwarding | `SSH_AUTH_SOCK` is empty in the new shell sandbox, and `ssh-add -l` says "Could not open a connection to your authentication agent". The release notes say shell sandboxes now need the `shell-credentials` mixin for provider credentials. We have not confirmed whether that also brings back the SSH agent |

Lab 06 (Claude) was not re-run on 0.51.0.

**Roll back to 0.49.2** to match the recorded output of the other labs exactly. apt can
downgrade a pinned package directly:

```shell
sudo apt-mark unhold docker-sbx
sudo apt-get install -y --allow-downgrades docker-sbx=0.49.2-1~ubuntu.24.04~noble
sudo apt-mark hold docker-sbx
sbx daemon restart
```

```text
dpkg: warning: downgrading docker-sbx from 0.51.0-1~ubuntu.24.04~noble to 0.49.2-1~ubuntu.24.04~noble
sbx version v0.49.2 5d40fd43027b33ed1f1a39c14fb07e2503d6998f
  ✓ Version match — v0.49.2
```

On the course host, a shell sandbox created by 0.51.0 still started under 0.49.2 and still ran
Debian 13. New sandboxes go back to the Ubuntu image. Rolling back also brings back the
`sbx cp` issues fixed in 0.50 and 0.51, so roll back only on a machine that runs agents you
trust.

## Watch the solution

```shell
make replay LAB=08          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=08     # asciinema
labs/08-whats-new-0.51/solution.sh   # run it live (needs sbx 0.51.0)
```

## Check your work

```shell
bats labs/08-whats-new-0.51/test.bats
```

The checks need sbx 0.51.0 or later and skip with a message on an older version.
