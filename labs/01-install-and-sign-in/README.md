# Lab 01 — Install sbx and sign in

**Goal:** install `sbx` **v0.49.2**, sign in, set the global network policy, and learn to check
the daemon and the whole installation.
**Time:** ~15 minutes. **Prerequisite:** [Lab 00](../00-prepare-ubuntu/README.md).

## Concepts

```text
  you ──► sbx CLI ──unix socket──► SANDBOX DAEMON  (one per user, under systemd --user)
                                     │  embedded containerd, network proxy, secret store,
                                     │  policy engine, policy log
                                     ▼
              ┌───────────── microVM (KVM) ─────────────┐
              │ own Linux kernel (nerdbox-kernel)        │◄── every outbound connection
              │ agent image (shell, claude, codex, ...)  │    goes through the daemon's
              │ your workspace, shared with virtiofs     │    proxy and its policy
              └──────────────────────────────────────────┘
```

- **`sbx`**: the one binary. It is both the CLI and the daemon (`sbx daemon start`).
- **Sandbox daemon** (`sandboxd`): starts and stops microVMs, owns the network proxy that every
  sandbox's traffic goes through, stores secrets, and enforces policy. It listens on a Unix
  socket in your home directory. There is no system service and nothing runs as root.
- **microVM**: each sandbox is a small KVM virtual machine with its own kernel. The container
  image for the agent runs inside it.
- **Global network policy**: the default rule set for every sandbox's outbound traffic. You
  pick one once: `allow-all`, `balanced`, or `deny-all`. Lab 04 goes deep on it.

Compared with OpenShell, the daemon plays the role of the gateway and the supervisor together,
and the microVM plays the role of the Landlock + seccomp workload.

## 1. Install a pinned version

`sbx` ships as the `docker-sbx` package in **Docker's apt repository**, the same one Docker
Engine comes from. Add the repository
([Docker's instructions](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)):

```shell
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
```

The course is written and tested against **v0.49.2**. sbx releases often, so pin the version
and hold the package, or the next `apt-get upgrade` changes the behavior under your feet:

```shell
sudo apt-get install -y docker-sbx=0.49.2-1~ubuntu.24.04~noble
sudo apt-mark hold docker-sbx
```

```shell
apt-cache policy docker-sbx | head -6; apt-mark showhold
```

```text
docker-sbx:
  Installed: 0.49.2-1~ubuntu.24.04~noble
  Candidate: 0.49.2-1~ubuntu.24.04~noble
  Version table:
 *** 0.49.2-1~ubuntu.24.04~noble 500
        500 https://download.docker.com/linux/ubuntu noble/stable amd64 Packages
docker-sbx
```

`apt-cache madison docker-sbx` lists every version the repository has.

```shell
sbx version
```

```text
sbx version v0.49.2 5d40fd43027b33ed1f1a39c14fb07e2503d6998f
```

### What the package put on the machine

```shell
dpkg -L docker-sbx | grep -E '^/(usr/bin|usr/libexec|etc)/' | grep -v '/lib$'
```

```text
/etc/apparmor.d
/etc/apparmor.d/docker-sbx-nerdbox-shim
/usr/bin/sbx
/usr/libexec/containerd-shim-nerdbox-gpu-v1
/usr/libexec/containerd-shim-nerdbox-v1
/usr/libexec/lib/libsailor.so
/usr/libexec/mkfs.erofs
/usr/libexec/mkfs.ext4
/usr/libexec/nerdbox-kernel-x86_64
/usr/libexec/nerdbox-rootfs-x86_64.erofs
```

The whole runtime is in that list: the CLI and daemon, a containerd shim that runs each
container inside a microVM (`nerdbox`), the **guest kernel** and its root filesystem, tools to
build disk images, and an AppArmor profile for the shim.

## 2. Sign in

```shell
sbx login
```

`sbx login` prints a device code and a URL. Open the URL in any browser, enter the code, and
sign in with your Docker account. For CI or a machine without a browser, use an access token:

```shell
echo "$DOCKER_PAT" | sbx login --username <you> --password-stdin
```

On Linux without a desktop keychain, sbx keeps credentials and secrets in files under
`~/.config/com.docker.sandboxes/`, protected by file permissions only.

## 3. Choose the global network policy

Signing in does not set a policy. On the course host (then on v0.48.0) the first
`sbx policy ls` after `sbx login` failed with `global network policy has not been initialized`.
`sbx diagnose` shows the state as its `Global network policy` check. Pick **balanced** for now:

```shell
sbx policy init balanced
```

`balanced` denies everything except a long allow list of AI providers, package registries,
GitHub, Docker Hub and cloud storage. Initialization is a one-time step; `sbx policy reset`
starts over. Lab 04 compares it with `deny-all`.

## 4. See what sbx detected

`sbx setup` (experimental) looks at the host and offers to import agent API keys from your
environment, turn on SSH-agent forwarding, and share your skills. Run it in a terminal to
answer its questions. Without a terminal it only reports:

```shell
sbx setup < /dev/null
```

```text
sbx setup — detected configuration

PREREQUISITES
  host           sbx, Docker                                   Ready

SECRETS
  agent secrets  none found on host                            0 found

SSH AGENT
  forwarding     global consent                                Enabled
  socket         /run/user/1000/gnupg/S.gpg-agent.ssh (current…Dynamic

SKILLS
  skills         19 skill(s), 1 folder                         19 found

GOVERNANCE
  Local policy   balanced                                      Set

(non-interactive: showing detected configuration only)
```

Note **SSH AGENT: Enabled**. With forwarding on, code inside a sandbox can ask your host SSH
agent to sign things with your keys (it never gets the keys themselves). That is convenient
for `git push` and is also a real grant of power. Lab 08 comes back to it.

## 5. Meet the daemon

```shell
sbx daemon status
```

```text
  Status:  ● running
  Socket:  /home/serra/.local/state/sandboxes/sandboxes/sandboxd/sandboxd.sock
  Logs:    /home/serra/.local/state/sandboxes/sandboxes/sandboxd/daemon.log
```

You rarely start it yourself: sbx commands start the daemon when it is not running. It runs as
your user, under your systemd user manager, which is why the `kvm` group from Lab 00 has to
reach that manager:

```shell
grep Groups /proc/$(pgrep -f '^/usr/bin/sbx daemon start')/status; getent group kvm
```

```text
Groups:	4 988 993 1000 1001
kvm:x:993:serra
```

`993` (kvm) is in the daemon's groups. The daemon log is JSON lines:

```shell
tail -20 ~/.local/state/sandboxes/sandboxes/sandboxd/daemon.log | grep '}$' | jq -c '{time, level, msg}' | tail -3
```

```text
{"time":"2026-10-24T14:52:42.499374668+01:00","level":"INFO","msg":"http request"}
{"time":"2026-10-24T14:52:42.618489619+01:00","level":"INFO","msg":"uploaded event batch"}
{"time":"2026-10-24T14:52:42.696545944+01:00","level":"INFO","msg":"http request"}
```

`sbx daemon log-level` shows and changes the per-category levels (`general`, `proxy`).

Where things live:

| Path | What |
|---|---|
| `~/.local/state/sandboxes/sandboxes/sandboxd/` | Daemon socket, `daemon.log`, its embedded containerd, sandbox disks |
| `~/.config/sandboxes/sandboxes/` | CLI state: login markers, settings lock |
| `~/.config/com.docker.sandboxes/` | Stored credentials and secrets (file-permission protected on Linux) |

## 6. Check the whole installation

```shell
sbx diagnose
```

```text
INSTALLATION
  ✓ CLI binary — found
      /usr/bin/sbx
  ! Binary version — could not check for updates
      unexpected status code: 403
  ✓ Host processes — 2 sbx, 0 containerd-shim-nerdbox-v1
      sbx PID 116881: /usr/bin/sbx sbx PID 125835: /usr/bin/sbx
  ✓ Daemon — healthy
      version v0.49.2
  ✓ Daemon diagnostics — collected (81306 bytes)

PLATFORM
  ✓ Virtualization — supported
      /dev/kvm is accessible
  ✓ mkfs.erofs — found
      /usr/libexec/mkfs.erofs, default block size 4096 bytes, guest kernel page size 4096 bytes
  ✓ mkfs.ext4 — found
      /usr/libexec/mkfs.ext4, mke2fs 1.47.4 (6-Mar-2025)

STORAGE
  ✓ Storage directories — all 1 paths present
  ✓ Directory permissions — all writable
  ! Disk space — 7.452GiB free
      7.452GiB free of 31.41GiB on the state directory's volume
      Low on space: a new agent template needs a few GiB, and running sandboxes grow into what is left. Remove stopped sandboxes with: sbx prune
  ⊘ ZFS offset sync — state directory is not on ZFS

CONNECTION
  ✓ Version match — v0.49.2
  ✓ Socket — responsive
  ✓ SSH client config — not configured
  ✓ Authentication — authenticated
  ✓ Global network policy — initialized

  14 passed · 2 warnings · 1 skipped
```

Warnings are fine; failures are not. The update check sometimes fails with a 403 from GitHub's
rate limit. When it works on a pinned install it says an update is available, which is
expected. `sbx diagnose --json` gives the same checks for scripts; this lab's test uses it.

## 7. Upgrading later

Upgrading the package does **not** restart the daemon. After an upgrade, `diagnose` warns
`Version match — CLI v0.49.2 ≠ daemon v0.48.0` until you restart it:

```shell
sudo apt-mark unhold docker-sbx
sudo apt-get install -y docker-sbx=<new-version>
sudo apt-mark hold docker-sbx
sbx daemon restart
```

`sbx daemon restart` **stops every running sandbox**. They keep their state and start again
on the next `sbx run` or `sbx exec` (Lab 02).

## Watch the solution

Every step of this lab, typed and run on a real host:

```shell
make replay LAB=01          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=01     # asciinema
labs/01-install-and-sign-in/solution.sh   # run it live on your own host (PAUSE=0 for full speed)
```

## Check your work

```shell
bats labs/01-install-and-sign-in/test.bats
```

## Troubleshooting

- `KVM error: Permission denied (os error 13)` in `daemon.log`: the daemon started before your
  user manager had the `kvm` group. Log out completely (or reboot), then `sbx daemon restart`.
- `Version match` warning: you upgraded the package; run `sbx daemon restart`.
- `global network policy has not been initialized`: run `sbx policy init balanced`.

**Next:** [Lab 02 — Sandbox basics](../02-sandbox-basics/README.md)
