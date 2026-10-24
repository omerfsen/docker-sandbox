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

This course is the short twin of the [OpenShell course](https://github.com/omerfsen/openshell):
same shape, same machine, the core path in eight labs. Where sbx has no equivalent of an
OpenShell feature, the lab says so plainly and shows the closest thing. The side-by-side
comparison is written up in [An OpenShell alternative? Testing Docker Sandboxes (sbx) with the
same labs](https://www.linkedin.com/pulse/openshell-alternative-testing-docker-sandboxes-sbx-same-omer-sen-uhg6e).

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
| 03 | [Default-deny networking](labs/03-network-default-deny/README.md) | Balanced vs deny-all, the policy log, bypass attempts that fail | Network policy |
| 04 | [L7 rules and approvals](labs/04-l7-rules-and-approvals/README.md) | Method and path rules, the approval queue, `policy check` | HTTP policy |
| 05 | [Credentials the agent never sees](labs/05-credentials/README.md) | `sbx secret`, placeholders swapped only for the bound host | Secret injection |
| 06 | [Capstone: run Claude Code](labs/06-run-claude-code/README.md) | A real agent in a sandbox under policy | Everything together |
| 07 | [Clean up](labs/07-cleanup/README.md) | rm, prune, secrets, reset, logout | Operations |

Time: about **2–3 hours** in total.

## What sbx does not have

Compared with OpenShell, sbx has no formal policy prover, no SDK, no per-path file rules inside
the sandbox, and no per-program network rules (every process in a sandbox gets the same network
answer). Its boundary is a whole VM instead. Templates, ports, MCP, and the experimental
`sbx env` are not covered; see the [documentation](https://docs.docker.com/ai/sandboxes/).

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

The checks use public echo services (`postman-echo.com`, `httpbin.org`, `tcpbin.com`) as safe
targets, so you need outbound internet access. Lab 06's Claude checks run only when an
`anthropic` secret is stored, and spend a few cents.

## References

- Docker Sandboxes documentation: [docs.docker.com/ai/sandboxes](https://docs.docker.com/ai/sandboxes/)
- Article comparing sbx and OpenShell: [An OpenShell alternative?](https://www.linkedin.com/pulse/openshell-alternative-testing-docker-sandboxes-sbx-same-omer-sen-uhg6e)
- Releases: [github.com/docker/sbx-releases](https://github.com/docker/sbx-releases/releases/tag/v0.49.2)

## License

The course material is licensed under the Apache License 2.0. See [LICENSE](LICENSE). sbx itself
is Docker's product under Docker's terms.
