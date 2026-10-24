# Lab 07 — Clean up

**Goal:** remove what the course created without touching anything else, know what the global
cleanup commands really do, and uninstall sbx if you want to.
**Time:** ~10 minutes. **Prerequisite:** any of the earlier labs.

## Concepts

What the course left behind, and what removes it:

| Leftover | Where | Removed by |
|---|---|---|
| `lab-*` sandboxes, with their scoped rules, secrets, and approvals | daemon state | `sbx rm` / `scripts/cleanup.sh` |
| Lab workspaces | `~/sbx-labs/` | `scripts/cleanup.sh` |
| Policy log entries | daemon state, kept by sandbox name | not removed by `sbx rm` (Lab 03) |
| The `anthropic` secret (Lab 06) | global secret store | `sbx secret rm anthropic -f` |
| Agent images | `sbx template ls` | `sbx template rm` |
| Global policy (Lab 01) | daemon state | `sbx policy reset` |

## 1. Look before you prune

Make two leftovers, one running and one stopped:

```shell
sbx create --name lab-07-a shell && sbx run -d --name lab-07-a && sbx create --name lab-07-b shell && sbx stop lab-07-b
sbx ls | grep -E 'SANDBOX|lab-'
```

```text
SANDBOX      AGENT    STATUS                 PORTS   WORKSPACE                                   CREATED
lab-07-a     shell    ● running (detached)           -                                           31s
lab-07-b     shell    ○ stopped                      -                                           17s
```

`sbx prune` removes **every stopped sandbox**, not only the course's. Always dry-run it:

```shell
sbx prune --dry-run | grep -E 'Would|SANDBOX|lab-'
```

```text
Would remove 3 stopped sandboxes:
SANDBOX      AGENT    STOPPED   WORKSPACE
lab-07-b     shell    9s        -
```

**3** stopped sandboxes. On the course host the other two are someone's real work, filtered
out of this listing. A plain `sbx prune` would have deleted them, and their secrets with them.
`--filter until=168h` limits it to sandboxes stopped more than a week ago.

## 2. Remove only what the course made

`scripts/cleanup.sh` removes sandboxes whose names start with `lab-` and the `~/sbx-labs`
folder, nothing else:

```shell
scripts/cleanup.sh
sbx ls | grep -E 'lab-' || echo no lab sandboxes left
```

```text
Deleting course sandboxes...
  sandbox lab-07-a
  sandbox lab-07-b
Done.
no lab sandboxes left
```

When `~/sbx-labs` exists, the script also prints `Removing lab workspaces...`.

## 3. Disk space

```shell
du -sh ~/.local/state/sandboxes; sbx template ls
```

```text
4.7G	/home/serra/.local/state/sandboxes

  REPOSITORY                           TAG                  IMAGE ID       FLAVOR               CREATED
  docker.io/docker/sandbox-templates   claude-code-docker   4a94d9144a70   claude-code-docker   3d
  docker.io/docker/sandbox-templates   shell-docker         b178ca62ec2e   shell-docker         3d
```

Most of the space is the agent images and the sandboxes' own disks. `sbx template rm
claude-code-docker` frees the Claude image; the next `sbx create claude` pulls it again.

## 4. Secrets

The Anthropic key from Lab 06 is global and stays until you remove it:

```shell
sbx secret rm anthropic -f
sbx secret ls
```

Sandbox-scoped secrets went away with their sandboxes. Remember Lab 05's trap: removing a
scoped custom secret by placeholder needs `--sandbox`.

## 5. The big switches (read before you run them)

| Command | What it does |
|---|---|
| `sbx logout` | Stops all **running** local sandboxes and signs you out. |
| `sbx policy reset` | Removes all policies; you choose a global policy again with `sbx policy init`. |
| `sbx reset` | Back to a fresh install: stops and **deletes every sandbox**, the image cache, all policies, all secrets (unless `--preserve-secrets`), the SSH config, signs out, stops the daemon, and removes all state and config directories. |

The lab does not run them. They affect every sandbox on the machine.

## 6. Uninstall

```shell
sbx reset                  # optional: remove all state first
sudo apt-mark unhold docker-sbx
sudo apt-get purge -y docker-sbx
```

Lab 00's `kvm` group membership and the Docker apt repository stay; remove them yourself if no
longer needed (`sudo gpasswd -d $USER kvm`, `/etc/apt/sources.list.d/docker.list`).

## 7. Where to go next

The course covered the core path. Not covered hands-on:

- **Templates**: save a configured sandbox and start new ones from it (`sbx template save`,
  `sbx template load`, `sbx create -t`).
- **Ports**: publish a dev server from a sandbox to the host (`sbx ports`, `create -p`).
- **MCP servers** for agents (`sbx mcp`), **kits** and **skills** (experimental).
- **Declarative sandboxes** from an `sbxenv.yaml` (`sbx env`, experimental).
- **Cloud sandboxes** (`sbx --cloud ...`) and organization governance (`sbx policy profile`).
- **Other agents**: `sbx create codex .`, `gemini`, `copilot`, `cursor`, `opencode`, and more.

Documentation: [docs.docker.com/ai/sandboxes](https://docs.docker.com/ai/sandboxes/). The
OpenShell twin of this course, for comparison:
[github.com/omerfsen/openshell](https://github.com/omerfsen/openshell).

## Watch the solution

```shell
make replay LAB=07          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=07     # asciinema
labs/07-cleanup/solution.sh   # run it live (only removes lab-* sandboxes)
```

## Check your work

```shell
bats labs/07-cleanup/test.bats
```

You are done. Thanks for working through the course.
