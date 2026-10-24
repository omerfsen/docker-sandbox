# Lab 02 — Sandbox basics

**Goal:** create, use, stop, and remove sandboxes; run commands in them; share a workspace and
copy files in and out.
**Time:** ~20 minutes. **Prerequisite:** [Lab 01](../01-install-and-sign-in/README.md).

## Concepts

A sandbox is a microVM built for one **agent**. `sbx create claude .` makes one for Claude Code,
`sbx create codex .` for Codex, and so on. Most labs in this course use the **`shell`** agent:
a plain Ubuntu sandbox with common tools and no AI agent, which makes the behavior easy to see.

| Command | What it does |
|---|---|
| `sbx create AGENT [PATH...]` | Create a sandbox. `PATH` is the workspace shared from the host. |
| `sbx run AGENT [PATH...]` | Create if needed, start, and attach to the agent. `-d` starts it detached. |
| `sbx exec NAME CMD` | Run a command inside, like `docker exec`. Starts a stopped sandbox first. |
| `sbx ls` | List sandboxes. `--json` for scripts. |
| `sbx stop NAME` | Stop the VM and keep its state. |
| `sbx cp SRC DST` | Copy between host and sandbox (`NAME:/path`). |
| `sbx rm NAME` | Remove the sandbox and everything in it. |

There is **no `sbx start`**. A stopped sandbox comes back with `sbx run --name NAME` or with
any `sbx exec`.

The course names every sandbox `lab-NN-...` and keeps lab workspaces under `~/sbx-labs/`, so
`scripts/cleanup.sh` can find them later.

## 1. Create a sandbox with a workspace

```shell
mkdir -p ~/sbx-labs/02 && echo "hello from the host" > ~/sbx-labs/02/README.txt
sbx create --name lab-02-basics shell ~/sbx-labs/02
```

```text
  SANDBOX
    Name:       lab-02-basics
    Agent:      shell
    Workspace:  ~/sbx-labs/02 (rw)
    Image:      docker/sandbox-templates:shell-docker
    CPU:        4
    Memory:     3.9 GiB

  IMAGE
        7/7 layers · finalizing image…
    ✓ image — ready

    ✓ Created sandbox lab-02-basics
        try: sbx run --name lab-02-basics
```

The sandbox gets every host CPU and half the host RAM unless you pass `--cpus` and `--memory`.
The image is pulled on every create (`--pull missing` skips that when it is cached). On the
course host a create took about 15 seconds.

```shell
sbx ls
```

```text
  SANDBOX         AGENT    STATUS                 PORTS   WORKSPACE                                   CREATED
  lab-02-basics   shell    ● running                      /home/serra/sbx-labs/02                     12s
```

Your list may show other sandboxes too.

## 2. Look inside

The sandbox runs **its own kernel and its own distribution**, not the host's:

```shell
uname -r; sbx exec lab-02-basics sh -c '. /etc/os-release; echo $PRETTY_NAME; uname -r'
```

```text
6.8.0-147-generic
Ubuntu 26.04.1 LTS
7.0.14
```

The first line is the host's kernel, the last is the microVM's. This is the main difference
from OpenShell, which confines processes on the host kernel with Landlock and seccomp. Here
code that breaks the sandbox's kernel still has to break out of the VM to reach the host.

```shell
sbx exec lab-02-basics id
```

```text
uid=1000(agent) gid=1000(agent) groups=1000(agent),27(sudo),1001(docker)
```

The agent runs as user `agent`, which is in `sudo` and `docker`: it can install packages and
run containers **inside** its VM.

## 3. The workspace

The workspace is mounted at **the same absolute path** as on the host, so paths in error
messages and git output mean the same thing on both sides:

```shell
sbx exec lab-02-basics sh -c "pwd; cat README.txt"
sbx exec lab-02-basics sh -c 'echo written-in-the-sandbox > from-sandbox.txt'; cat ~/sbx-labs/02/from-sandbox.txt
sbx exec lab-02-basics sh -c 'mount | grep virtiofs'
```

```text
/home/serra/sbx-labs/02
hello from the host
written-in-the-sandbox
bind-95f03ffa45a7d998 on /etc/resolv.conf type virtiofs (ro,relatime)
host on /home/serra/sbx-labs/02 type virtiofs (rw,nosuid,nodev,relatime)
```

The workspace is shared live with **virtiofs**. Whatever the agent writes there is on your disk
at once. Nothing else from your home directory is visible inside: no `~/.ssh`, no `~/.aws`.
The VM and this one shared folder are the whole filesystem boundary: sbx has no per-path rules
like OpenShell's Landlock policy.

## 4. Not root, but root is close

```shell
sbx exec lab-02-basics sh -c 'touch /etc/probe'
sbx exec lab-02-basics sudo -n id -u; sbx exec -u root lab-02-basics id -u
```

```text
touch: cannot touch '/etc/probe': Permission denied
0
0
```

The agent user cannot write `/etc`, but `sudo` needs no password and `exec -u root` works. Inside
the sandbox, root is not a barrier. The boundary is the VM and the network proxy around it.
OpenShell's model is the opposite: the workload stays non-root with no capabilities.

## 5. exec is docker exec

```shell
sbx exec lab-02-basics sh -c 'exit 3'; echo "exit code: $?"
echo "piped stdin" | sbx exec -i lab-02-basics cat
sbx exec -e GREETING=merhaba lab-02-basics sh -c 'echo $GREETING'
```

```text
exit code: 3
piped stdin
merhaba
```

Exit codes come back, `-i` passes stdin, `-e` sets an environment variable for that one command.
`-it` gives you an interactive shell: `sbx exec -it lab-02-basics bash`.

## 6. Sandboxes stop when idle

A sandbox made with `sbx create` keeps running only while something is attached. Wait half a
minute:

```shell
sleep 35; sbx ls --json | jq -r '.[] | select(.name == "lab-02-basics") | .status'
sbx exec lab-02-basics cat README.txt
```

```text
stopped

    ✓ sandbox lab-02-basics — started

hello from the host
```

`exec` started it again first. That "started" line goes to stderr.

To keep a sandbox up with nothing attached, start it **detached**:

```shell
sbx run -d --name lab-02-basics
sleep 35; sbx ls | grep -E 'SANDBOX|lab-02'
```

```text
    ✓ sandbox lab-02-basics — attaching to the existing sandbox (workspace /home/serra/sbx-labs/02)
    ✓ sandbox lab-02-basics — running detached
        workspace /home/serra/sbx-labs/02
223d2d2a-31ac-49e8-b6ef-c9b38dabf3ba

SANDBOX         AGENT    STATUS                 PORTS   WORKSPACE                                   CREATED
lab-02-basics   shell    ● running (detached)           /home/serra/sbx-labs/02                     1m
```

`sbx run --name lab-02-basics` without `-d` attaches you to the agent; for `shell` that is a
bash prompt inside the VM.

## 7. Stop keeps state

```shell
sbx exec lab-02-basics sh -c 'echo kept > ~/keep.txt' && sbx stop lab-02-basics
sbx exec lab-02-basics cat /home/agent/keep.txt
```

```text
  Stopped sandbox lab-02-basics
    try: sbx run --name lab-02-basics

    ✓ sandbox lab-02-basics — started

kept
```

Everything inside the VM survives a stop: installed packages, files in `/home/agent`, caches.
Only `sbx rm` throws it away.

## 8. Copy files in and out

`sbx cp` works like `docker cp`. One side is `NAME:/path`:

```shell
mkdir -p ~/sbx-labs/02-out && echo "copied in" > ~/sbx-labs/02-out/in.txt
sbx cp ~/sbx-labs/02-out/in.txt lab-02-basics:/home/agent/ && sbx exec lab-02-basics cat /home/agent/in.txt
```

```text
copied in
```

Two things to know. First, a symlink is copied **as a link** unless you pass `-L`:

```shell
sbx cp lab-02-basics:/etc/os-release ~/sbx-labs/02-out/ && ls -l ~/sbx-labs/02-out/os-release
sbx cp -L lab-02-basics:/etc/os-release ~/sbx-labs/02-out/os-release-real && head -1 ~/sbx-labs/02-out/os-release-real
```

```text
lrwxrwxrwx 1 serra serra 21 Aug 24 11:33 /home/serra/sbx-labs/02-out/os-release -> ../usr/lib/os-release
PRETTY_NAME="Ubuntu 26.04.1 LTS"
```

The first copy is a dangling link on your host that points at `../usr/lib/os-release`. Use `-L`
when you want the content.

Second, `cp` is not limited by the agent user's permissions:

```shell
sbx cp ~/sbx-labs/02-out/in.txt lab-02-basics:/etc/ && sbx exec lab-02-basics ls -l /etc/in.txt
```

```text
-rw-rw-r-- 1 agent docker 10 Oct 24 13:57 /etc/in.txt
```

`touch /etc/probe` failed in step 4, but `sbx cp` wrote into `/etc`. It works from the outside,
like `docker cp`.

## 9. A sandbox without a workspace

Leave out the path and the sandbox gets no host bind mount at all:

```shell
sbx create --name lab-02-nows shell
sbx exec lab-02-nows sh -c "pwd; ls -A"
```

```text
    Workspace:  none · no workspace bind mount
    ...
/home/agent/workspace
```

The agent works in an empty directory inside the VM. Nothing it does touches your disk. Use
`sbx cp` to get results out.

## 10. A throwaway sandbox

`run --rm` creates a sandbox, runs the agent, and removes the sandbox when the session ends.
Arguments after `--` go to the agent; for `shell` that is bash:

```shell
sbx run --rm --name lab-02-once shell ~/sbx-labs/02 -- -c 'echo hello from $(hostname) as $(id -un)'
sbx ls -q | grep lab-02
```

```text
    ✓ Created sandbox lab-02-once

    ○ shell — starting in sandbox lab-02-once…
        workspace /home/serra/sbx-labs/02

hello from lab-02-once as agent
lab-02-basics
lab-02-nows
```

`lab-02-once` is gone. `run` needs a terminal: from a script without one it prints nothing.

## 11. Clean up

```shell
sbx rm lab-02-basics lab-02-nows
rm -rf ~/sbx-labs/02 ~/sbx-labs/02-out
```

`sbx rm` asks for confirmation. From a script it refuses with
`error: stdin is not a terminal; use --force to skip confirmation`, so scripts use
`sbx rm --force`. Removing a sandbox also deletes secrets scoped to it (Lab 05).

## Exercises

1. Create a sandbox with a second, read-only workspace
   (`mkdir -p ~/sbx-labs/02-docs && sbx create --name lab-02-ro shell ~/sbx-labs/02 ~/sbx-labs/02-docs:ro`)
   and try to write into it from inside. Use the host path (`$HOME/sbx-labs/02-docs` expanded on
   the host): inside the sandbox `~` is `/home/agent`.
2. Install a package with `sudo apt-get install -y cowsay` in a sandbox, stop it, and check it
   is still there after the next `exec`.
3. Create a sandbox with `--memory 1g --cpus 1` and compare `nproc` and `free -m` inside.

## Watch the solution

Every step of this lab, typed and run against a real sbx daemon:

```shell
make replay LAB=02          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=02     # asciinema
labs/02-sandbox-basics/solution.sh   # replay it live against your own daemon (PAUSE=0 for full speed)
```

## Check your work

```shell
bats labs/02-sandbox-basics/test.bats
```

**Next:** [Lab 03 — Default-deny networking](../03-network-default-deny/README.md)
