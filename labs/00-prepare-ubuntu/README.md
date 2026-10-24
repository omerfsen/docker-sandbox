# Lab 00 — Prepare a fresh Ubuntu 24.04 host

**Goal:** turn a brand-new Ubuntu 24.04 LTS machine into a host that can run Docker Sandboxes.
**Time:** ~15 minutes. **You need:** `sudo` on the machine.

## Why this matters

A Docker Sandbox is a **microVM**: a small virtual machine with its own Linux kernel, not a
container sharing yours. The sandbox daemon starts these VMs with the kernel's virtualization
support, **KVM**. If the CPU does not expose hardware virtualization, or your user cannot open
`/dev/kvm`, no sandbox can start.

You do **not** need Docker Engine for this course. `sbx` brings its own container runtime
inside its daemon, and sandboxes never show up in `docker ps`.

| Requirement | Minimum | Why |
|---|---|---|
| Ubuntu | 24.04 LTS, x86_64 or arm64 | The `docker-sbx` package the course pins is built for it |
| CPU virtualization | `vmx` (Intel) or `svm` (AMD) flag, `/dev/kvm` present | Every sandbox is a KVM microVM |
| Group | your user in `kvm` | `/dev/kvm` is `root:kvm 0660` |
| CPU / RAM / disk | 2 vCPU / 4 GB / 20 GB minimum; **4 vCPU / 8 GB / 30 GB recommended** | By default a sandbox gets every host CPU and half the host RAM. An agent image needs a few GB of disk. The headroom is for a real agent in Lab 17. |

## 1. Create the machine

You need a machine where KVM works:

- **Bare metal or a desktop** with virtualization turned on in the firmware (Intel VT-x or
  AMD-V).
- **A cloud VM with nested virtualization.** Most clouds turn it off by default or only
  offer it on some instance families. Look up "nested virtualization" in your provider's docs
  before you create the VM.
- **A local VM** (Multipass, virt-manager, VirtualBox) on a host where nested virtualization
  is turned on.

The course was written on an Ubuntu 24.04 KVM guest with 4 vCPU and 8 GB RAM.

## 2. Update the system and install the tools

```shell
sudo apt-get update
sudo apt-get -y full-upgrade
sudo apt-get install -y ca-certificates curl git jq bats asciinema
sudo reboot   # only if the upgrade installed a new kernel
```

`bats` runs the lab checks. `asciinema` is optional: it plays the `.cast` recordings.

## 3. Check KVM

The CPU must expose hardware virtualization:

```shell
grep -owE 'vmx|svm' /proc/cpuinfo | sort | uniq -c
```

```text
      4 svm
```

One line per vCPU. No output means nested virtualization is off. Fix that on the hypervisor
or in the cloud console, not inside this machine.

The device must exist:

```shell
ls -l /dev/kvm
```

```text
crw-rw---- 1 root kvm 10, 232 Oct 24 14:43 /dev/kvm
```

## 4. Join the kvm group, then log out

```shell
sudo usermod -aG kvm "$USER"
```

Then **log out completely and log back in, or reboot**. `newgrp kvm` is not enough. The sandbox
daemon (Lab 01) is started by your **systemd user manager**, and that manager keeps the groups it
had when your first session started. If you only refresh your shell, `/dev/kvm` works in the
shell but the daemon fails with `KVM error: Permission denied (os error 13)` in its log. On a
server where you also have tmux or other SSH sessions open, rebooting is the reliable way.

```shell
id -nG | tr " " "\n" | grep -x kvm
```

```text
kvm
```

## 5. Get a Docker account

`sbx login` (Lab 01) signs you in with a Docker account through a device code in the browser.
Create one at [app.docker.com/signup](https://app.docker.com/signup) if you don't have one.

## 6. Get the course

```shell
git clone https://github.com/omerfsen/docker-sandbox.git ~/sbx-training
cd ~/sbx-training
```

## 7. Check the host

```shell
scripts/check-host.sh
```

Expected output ends with `Host is ready for Docker Sandboxes.` Every `[FAIL]` line names the
fix.

```text
Docker Sandboxes host check
  [ok]   OS: Ubuntu 24.04.5 LTS
  [ok]   architecture: x86_64
  [ok]   CPU virtualization: svm
  [ok]   /dev/kvm present
  [ok]   serra is in the kvm group
  [ok]   /dev/kvm is readable and writable by this shell
  [ok]   sandbox daemon (pid 116881) has the kvm group
  [warn] disk: 8 GB free in /home/serra (each agent image needs a few GB; 15 GB or more is comfortable)
  [ok]   curl
  [ok]   git
  [ok]   jq
  [ok]   bats 1.10.0 (lab tests)
  [ok]   sbx installed: v0.49.2
Host is ready for Docker Sandboxes.
```

This run is from the course host after Lab 01. On a fresh machine the `sandbox daemon` line is
missing and the last check reads `[warn] sbx is not installed yet (Lab 01 installs it)`. Both
are expected. Run the check again after Lab 01: it then also confirms that the running daemon
has the `kvm` group.

## Watch the solution

Every step of this lab, typed and run on a real host:

```shell
make replay LAB=00          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=00     # asciinema
labs/00-prepare-ubuntu/solution.sh   # run it live on your own host (PAUSE=0 for full speed)
```

## Check your work

```shell
bats labs/00-prepare-ubuntu/test.bats
```

## Troubleshooting

- `CPU has no vmx/svm flag`: nested virtualization is off for this VM. Turn it on where the VM
  is defined, then stop and start the VM.
- `/dev/kvm is not accessible from this shell`: you joined `kvm` but have not logged out and
  back in yet.

**Next:** [Lab 01 — Install sbx and sign in](../01-install-and-sign-in/README.md)
