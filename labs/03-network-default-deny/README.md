# Lab 03 — Default-deny networking

**Goal:** see what a sandbox can reach under the Balanced policy, watch attempts to go around
the proxy fail, open and close hosts for one sandbox, and read the policy log.
**Time:** ~20 minutes. **Prerequisite:** [Lab 02](../02-sandbox-basics/README.md).

## Concepts

A sandbox has no direct way out. Every outbound connection goes through the **sandbox daemon's
proxy** on the host, and the proxy asks the policy engine before it connects anywhere:

```text
  microVM                                 host
  ┌──────────────────────────┐            ┌────────────────────────────────────┐
  │ curl, pip, node, agent   │──HTTP(S)──►│ forward proxy  :3128               │
  │  (HTTPS_PROXY is set)    │            │   policy: allow? ──► internet      │
  │                          │            │                deny ──► 403        │
  │ anything that ignores    │──TCP──────►│ transparent proxy                  │
  │  the proxy variables     │            │   policy: deny ──► connection dies │
  │ DNS lookups              │──DNS──────►│ DNS: only names policy allows      │
  └──────────────────────────┘            └────────────────────────────────────┘
```

- **Global policy** (set once in Lab 01): `balanced` is default-deny plus about 195 allow rules
  for AI providers, package registries, GitHub, Docker Hub, and cloud storage.
- **Sandbox-scoped rules** (`--sandbox NAME`) add allows or denies for one sandbox on top.
- **Deny beats allow.** If a request matches both, it is denied.
- Rules match **hosts** (with `*` and `**` wildcards) and optionally HTTP method and path (Lab 04).

What sbx does **not** have: OpenShell scopes a network rule to a **binary** (`curl` may reach a
host while `python3` may not). sbx has no per-program rules. Every process in a sandbox gets the
same answer. You will see that below.

## 1. Balanced: what gets through

```shell
mkdir -p ~/sbx-labs/03 && sbx run -d --name lab-03-net shell ~/sbx-labs/03
for url in https://pypi.org https://example.com https://postman-echo.com/get http://169.254.169.254/; do
  sbx exec lab-03-net curl -s -o /dev/null -w "$url %{http_code}\n" --max-time 10 $url
done
```

```text
https://pypi.org 200
https://example.com 403
https://postman-echo.com/get 403
http://169.254.169.254/ 403
```

A blocked host is a **403 from the proxy**, not a timeout. The cloud metadata address
`169.254.169.254` is blocked like any other host not on the list.

## 2. Read the policy log

```shell
sbx policy log lab-03-net
```

The table is wide. The JSON form is easier to read in a terminal:

```shell
sbx policy log lab-03-net --json | jq -r '(.blocked[:3][] | "DENY   \(.host)  \(.reason)"),
  (.allowed[] | select(.host == "pypi.org:443") | "ALLOW  \(.host)  \(.proxy_type)")'
```

```text
DENY   169.254.169.254:80  No matching allow rule (default deny)
DENY   postman-echo.com:443  No matching allow rule (default deny)
DENY   example.com:443  No matching allow rule (default deny)
ALLOW  pypi.org:443  forward-bypass
```

Each entry is a **host** with a count and first/last-seen times, not one line per request.
`forward-bypass` on an allowed host means the proxy passed the TLS connection through without
looking inside it. The log is kept **by sandbox name**: if you ran this lab before, entries
from the earlier `lab-03-net` are still there, even after `sbx rm`.

## 3. How programs find the proxy

```shell
sbx exec lab-03-net sh -c 'env | grep -i ^https_proxy'
```

```text
HTTPS_PROXY=http://gateway.docker.internal:3128
https_proxy=http://gateway.docker.internal:3128
```

`HTTP_PROXY`, `NO_PROXY`, and `NODE_USE_ENV_PROXY=1` are set too, so curl, pip, npm, and Node
use the proxy without any configuration.

## 4. Going around the proxy does not work

An agent, or code it runs, may ignore the proxy variables. Try:

```shell
sbx exec lab-03-net curl -sS --noproxy '*' --max-time 8 -o /dev/null https://example.com
sbx exec lab-03-net sh -c 'getent hosts example.com || echo no DNS answer for example.com; getent hosts pypi.org | head -1'
```

```text
curl: (6) Could not resolve host: example.com
no DNS answer for example.com
2a04:4e42:400::223 pypi.org
```

Blocked names do not even **resolve**. Allowed ones do. So skip DNS and use an IP address:

```shell
sbx exec lab-03-net curl -sS --noproxy '*' --max-time 8 -o /dev/null https://1.1.1.1
```

```text
curl: (35) TLS connect error: error:0A000126:SSL routines::unexpected eof while reading
```

The TCP connection is accepted and then closed. A **transparent proxy** catches every direct
connection, checks the policy, and drops it. A raw TCP echo server makes it clear. From the
host it answers, from the sandbox it doesn't:

```shell
IP=$(getent ahostsv4 tcpbin.com | awk 'NR==1{print $1}')
echo "host reply: [$(echo hello | nc -q2 $IP 4242)]"
sbx exec lab-03-net bash -c "exec 3<>/dev/tcp/$IP/4242 && echo connected to $IP:4242; echo hello >&3; echo sandbox reply: [\$(timeout 5 head -1 <&3)]"
```

```text
host reply: [hello]
connected to 45.79.112.203:4242
sandbox reply: []
```

Every attempt is in the log, with the path it took:

```shell
sbx policy log lab-03-net --json | jq -r '.blocked[:4][] | "\(.last_seen[11:19])  \(.proxy_type)  \(.host)  \(.reason)"'
```

```text
15:31:26  transparent  45.79.112.203:4242  No matching allow rule (default deny)
15:31:23  transparent  1.1.1.1:443  No matching allow rule (default deny)
15:31:23  network  example.com.lab-03-net.docker.internal  DNS lookup blocked by proxy policy
15:31:23  network  example.com  DNS lookup blocked by proxy policy
```

## 5. Open one host for this sandbox

```shell
sbx policy allow network --sandbox lab-03-net postman-echo.com
sleep 3; sbx exec lab-03-net curl -s -o /dev/null -w "%{http_code}\n" https://postman-echo.com/get
```

```text
  Added rule 9b5f14a6-8a5e-4be0-8f3d-56d58cb3b470 to policy local (scope: sandbox:lab-03-net): postman-echo.com [tcp]

200
```

Rules apply to running sandboxes within a few seconds; no restart. `sbx policy check` asks the
policy engine without sending traffic:

```shell
sbx policy check network postman-echo.com
sbx policy check network --sandbox lab-03-net postman-echo.com
```

```text
    Denied:      postman-echo.com:443
    Governance:  Local policy only
    Context:     global
    Reason:      no matching allow rule (default deny)

    Allowed:     postman-echo.com:443
    Governance:  Local policy only
    Context:     sandbox:lab-03-net
```

Other sandboxes are still denied; only `lab-03-net` has the rule.

## 6. No per-program rules

The same host, from Python:

```shell
sbx exec lab-03-net python3 -c 'import urllib.request as u; print(u.urlopen(u.Request("https://postman-echo.com/get", headers={"User-Agent": "curl/8"}), timeout=10).status)'
```

```text
200
```

Allowed for curl means allowed for every program in the sandbox. In OpenShell you would list
`/usr/bin/curl` in the rule and Python would stay blocked.

**A trap worth knowing:** without the `User-Agent` header, Python gets a 403 too. That 403
comes from the **site**, not from sbx. postman-echo's CDN rejects Python's default
User-Agent:

```shell
sbx exec lab-03-net curl -sS -A 'Python-urllib/3.14' https://postman-echo.com/get; echo
```

```text
error code: 1010
```

Before you blame the policy for a 403, check `sbx policy log`: this request is listed under
**allowed**.

## 7. Deny-all for one sandbox

```shell
sbx policy deny network --sandbox lab-03-net '**'
sleep 3; for url in https://pypi.org https://postman-echo.com/get; do
  sbx exec lab-03-net curl -s -o /dev/null -w "$url %{http_code}\n" --max-time 10 $url
done
```

```text
  warning: UDP rule saved, but UDP egress is disabled; enable experimental features and feature.udp-egress to use UDP
  Added rule 93c5e92e-30e7-4736-a6bd-f5d2c449ec19 to policy local (scope: sandbox:lab-03-net): ** [tcp,udp]

https://pypi.org 403
https://postman-echo.com/get 403
```

`**` matches every host, and **deny beats allow**: the sandbox's own `postman-echo.com` allow
and every Balanced allow lose. The warning says UDP egress is off altogether, so only TCP
matters. The sandbox's rules:

```shell
sbx policy ls --json | jq -r '.rules[] | select(.applies_to == "sandbox:lab-03-net") | "\(.decision)  \(.resources | join(","))"'
```

```text
allow  postman-echo.com
deny  **
```

To make **every** sandbox deny-all, change the global policy instead:
`sbx policy reset`, then `sbx policy init deny-all`. That affects all your sandboxes, so the lab
uses a sandbox-scoped rule. `sbx create --deny-network HOST` adds a deny rule when the sandbox
is created.

## 8. Remove the rules

```shell
sbx policy rm network --sandbox lab-03-net --resource '**' --force
sbx policy rm network --sandbox lab-03-net --resource postman-echo.com --force
sleep 3; sbx exec lab-03-net curl -s -o /dev/null -w "%{http_code}\n" https://postman-echo.com/get
```

```text
  Removed rule from policy local: resources=**

  Removed rule from policy local: resources=postman-echo.com

403
```

## 9. Clean up

```shell
sbx rm --force lab-03-net; rm -rf ~/sbx-labs/03
```

`sbx rm` also removes the sandbox's scoped rules. Its log entries stay.

## Exercises

1. Allow `*.npmjs.org` for a sandbox and check which of `registry.npmjs.org` and `npmjs.org`
   matches with `sbx policy check network --sandbox`.
2. Use `sbx policy check network --verbose` and read the exact request the policy engine sees.
3. Find two hosts in the Balanced list that surprise you:
   `sbx policy ls --wide | grep default-`. Which of them could an agent use to send data out?

## Watch the solution

Every step of this lab, typed and run against a real sbx daemon:

```shell
make replay LAB=03          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=03     # asciinema
labs/03-network-default-deny/solution.sh   # replay it live against your own daemon (PAUSE=0 for full speed)
```

## Check your work

```shell
bats labs/03-network-default-deny/test.bats
```

**Next:** [Lab 04 — L7 rules and approvals](../04-l7-rules-and-approvals/README.md)
