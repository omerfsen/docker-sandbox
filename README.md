# Docker Sandboxes Hands-On: a self-paced training

A practical, lab-by-lab course on **[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)**
(`sbx`), which runs AI coding agents such as Claude Code, Codex, or Gemini CLI in **microVMs**
with their own kernel, a shared workspace, and a network proxy that decides every outbound
connection.

You start from a **fresh Ubuntu 24.04** machine and end by running a real coding agent in a
sandbox whose network access, credentials, and files you control.

Every lab has three parts: a document that explains and walks you through it, an automatic
**check** (`bats`) that proves your sandbox behaves as the lab says, and a **solution replay**
you can watch or run.

This course is the twin of the [OpenShell course](https://github.com/omerfsen/openshell): same
lab numbers, same shape, same machine. Where sbx has no equivalent of an OpenShell feature, the
lab says so plainly and shows the closest thing.

> **Version.** This course is written and tested against **sbx v0.49.2** (commit `5d40fd43`,
> package `docker-sbx 0.49.2-1~ubuntu.24.04~noble`) on Ubuntu 24.04.5 LTS (kernel 6.8), on a KVM
> guest with 4 vCPU and 8 GB RAM. Lab 01 pins the install to that version. sbx releases often,
> so if you use a newer version, expect small differences in output.
>
> *Community training material, not an official Docker product.*

## What sbx does, in one picture

```text
  you ──► sbx CLI ──unix socket──► SANDBOX DAEMON  (your user, under systemd --user)
                                     │  network proxy + policy, secret store, policy log
                                     ▼
          ┌──────────────── microVM (KVM) ─────────────────┐
          │  own Linux kernel                               │──► internet, only where
          │  agent image: claude, codex, gemini, shell, ... │    policy allows, with
          │  agent user with sudo (root inside the VM)      │    credentials added by
          │  your workspace, shared live with virtiofs      │    the proxy on the way out
          └─────────────────────────────────────────────────┘
```

## How to start

1. **Get a machine.** A fresh Ubuntu 24.04 LTS machine where **KVM works**: bare metal, or a VM
   with nested virtualization. 4 vCPU, 8 GB RAM, 30 GB disk recommended. Details in
   [Lab 00](labs/00-prepare-ubuntu/README.md).
2. **Clone the course:**
   ```shell
   git clone https://github.com/omerfsen/docker-sandbox.git ~/sbx-training
   cd ~/sbx-training
   ```
3. **Follow the labs in order**, starting with [Lab 00](labs/00-prepare-ubuntu/README.md). Each
   lab tells you what it needs and links to the next one.
4. **After each lab, check your work:**
   ```shell
   bats labs/02-sandbox-basics/test.bats     # or: make test LAB=02
   ```
5. **Stuck?** Watch the solution: `make replay LAB=02`. Or run it live: `make solution LAB=02`.

All commands run from the repository root.

## The labs

| # | Lab | You will learn | sbx feature |
|---|---|---|---|
| 00 | [Prepare a fresh Ubuntu 24.04 host](labs/00-prepare-ubuntu/README.md) | KVM, the `kvm` group and why you must log out, host check | Platform requirements |
| 01 | [Install sbx and sign in](labs/01-install-and-sign-in/README.md) | Pinned apt install, `login`, `policy init`, `setup`, the daemon, `diagnose` | CLI, daemon, packaging |
| 02 | [Sandbox basics](labs/02-sandbox-basics/README.md) | create / run / exec / ls / stop / cp / rm, idle stop, workspaces | Sandbox lifecycle |
| 03 | Templates *(coming)* | Your own image for a sandbox | `sbx template` |
| 04 | Default-deny networking *(coming)* | Balanced vs deny-all, the policy log, bypass attempts | Network policy |
| 05 | L7 rules *(coming)* | Method and path rules, the approval queue | HTTP policy |
| 06 | Filesystem and process *(coming)* | The microVM boundary, workspace mounts; no per-path rules | Isolation |
| 07 | Policy lifecycle *(coming)* | allow / deny / rm / reset, profiles | Policy management |
| 08 | Credentials *(coming)* | Secrets the agent never sees, placeholders | `sbx secret` |
| 09 | Files and SSH *(coming)* | `cp`, read-only mounts, `--clone`, `ssh <name>.sbx` | Files, SSH |
| 10 | Approvals *(coming)* | Closest thing to OpenShell's policy advisor | `policy approval` |
| 11 | Policy check *(coming)* | Closest thing to OpenShell's policy prover | `policy check` |
| 12 | Ports *(coming)* | Publishing sandbox ports | `sbx ports` |
| 13 | Templates and settings *(coming)* | Reusable templates, daemon settings | `template`, `settings` |
| 14 | Observability *(coming)* | Policy log, TUI, diagnose, daemon log | Audit and logging |
| 15 | Declarative sandboxes *(coming)* | No SDK; `sbxenv.yaml` instead | `sbx env` |
| 16 | MCP *(coming)* | MCP servers for agents | `sbx mcp` |
| 17 | Capstone: run a real agent *(coming)* | Claude Code in a sandbox under policy | Everything together |
| 18 | Clean up *(coming)* | rm, prune, reset, logout | Operations |

## What sbx does not have

Compared with OpenShell, sbx has no formal policy prover, no SDK, no per-path file rules inside
the sandbox, and no per-program network rules (every process in a sandbox gets the same network
answer). Its boundary is a whole VM instead. The labs that correspond to those OpenShell
features say so and show the closest sbx tool.

## Repository layout

```text
labs/NN-name/
  README.md        the lab: concepts, steps with real output, exercises
  test.bats        automatic checks for the lab (bats)
  solution.sh      self-playing walkthrough: types each command and runs it for real
  solution.log     \  the same walkthrough recorded with util-linux `script`
  solution.timing  /  → scriptreplay --timing solution.timing solution.log
  solution.cast       asciinema recording of the same run → asciinema play solution.cast
scripts/           host check, autoplay helper, recorder, cleanup
tests/helpers.bash shared test helpers
VERSION            the sbx version the course targets (0.49.2)
```

## Make targets

```shell
make check-host            # prerequisites
make test                  # run every lab's checks (creates and deletes real sandboxes)
make test LAB=02           # one lab
make solution LAB=02       # live replay (PAUSE=0 TYPE_SPEED=0 for full speed, INTERACTIVE=1 to step)
make replay LAB=02         # recorded replay with scriptreplay
make replay-cast LAB=02    # recorded replay with asciinema
make record LAB=02         # re-record a solution after changing it
make cleanup               # remove every lab-* sandbox and ~/sbx-labs
```

The tests and solutions only create and remove sandboxes whose names start with `lab-`. Your
other sandboxes are left alone.

## Tools used

- **[bats-core](https://github.com/bats-core/bats-core)** (`sudo apt install bats`): the test
  runner for the lab checks.
- **`script` / `scriptreplay`** (util-linux, preinstalled): records and replays the solutions.
- **[asciinema](https://asciinema.org)** (`sudo apt install asciinema`, optional): plays the
  `.cast` recordings, which also embed on the web.

## References

- Docker Sandboxes documentation: [docs.docker.com/ai/sandboxes](https://docs.docker.com/ai/sandboxes/)
- Releases: [github.com/docker/sbx-releases](https://github.com/docker/sbx-releases/releases/tag/v0.49.2)

## License

The course material is licensed under the Apache License 2.0. See [LICENSE](LICENSE). sbx itself
is Docker's product under Docker's terms.
