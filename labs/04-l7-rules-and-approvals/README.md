# Lab 04 — L7 rules and approvals

**Goal:** allow some HTTP methods and paths on a host and not others, see how the proxy reads
HTTPS to do that, and work the approval queue that collects every blocked request.
**Time:** ~20 minutes. **Prerequisite:** [Lab 03](../03-network-default-deny/README.md).

## Concepts

Lab 03's rules were about **hosts**. A rule can also name HTTP **methods** and a **path glob**:

```shell
sbx policy allow network --sandbox NAME api.example.com --method GET,HEAD --path '/v1/**'
sbx policy deny  network --sandbox NAME api.example.com --method DELETE
```

To check a method and path inside HTTPS, the proxy has to see the request. For a host with HTTP
rules it terminates TLS itself with the **Docker Sandboxes Proxy CA**, which every sandbox
trusts, checks the request, and makes its own TLS connection upstream. Hosts with only plain
host rules are passed through untouched.

Every blocked request also lands in an **approval queue**. You can allow it (sbx writes a
narrow rule for exactly that request) or dismiss it.

| OpenShell | sbx |
|---|---|
| L7 `rules` with method and path, `access: read-only` presets | `--method` / `--path` on allow and deny rules |
| Policy advisor: drafts rules from denials, agent proposals | Approval queue: allow or dismiss each blocked request |
| `enforcement: audit` (log only) | No audit-only flag on `policy allow` or `deny` |

## 1. A host that needs approval

httpbin.org is not on the Balanced list:

```shell
sbx run -d --name lab-04-l7 shell
sbx exec lab-04-l7 curl -s https://httpbin.org/anything
```

```text
Approval required for httpbin.org:443.

Review and respond with:
  sbx policy approval ls
```

```shell
sbx policy approval ls
```

```text
  APPROVAL                                              SANDBOX     TITLE             DETAIL                                                                      OPTIONS
  network:99Ljl22mWkvPIQzLrXHYj8JbQcSRCONRZv45W_vxM6Q   lab-04-l7   httpbin.org:443   Protocol: TCP Resource type: domain no matching allow rule (default deny)   allow (Allow), dismiss (Dismiss)
```

The request did not wait. It failed at once with a 403, and the approval stays in the queue
until someone answers it. An agent that retries after you approve gets through.

## 2. Allow GET under /anything/ only

```shell
sbx policy allow network --sandbox lab-04-l7 httpbin.org --method GET --path '/anything/**'
sleep 3; for req in "GET /anything/ok" "POST /anything/ok" "GET /headers"; do
  set -- $req; sbx exec lab-04-l7 curl -s -o /dev/null -w "$1 $2 %{http_code}\n" -X $1 https://httpbin.org$2
done
```

```text
  Added rule f055542b-5a78-4da1-bc6f-98bef7d07435 to policy local (scope: sandbox:lab-04-l7): GET httpbin.org/anything/**

GET /anything/ok 200
POST /anything/ok 403
GET /headers 403
```

Only the listed method under the listed path gets through. This is an **allow-list**: write
only method/path rules for the host, and anything else is blocked.

## 3. How the proxy reads HTTPS

```shell
sbx exec lab-04-l7 sh -c 'curl -sv -o /dev/null https://httpbin.org/anything/ok 2>&1 | grep issuer:
  curl -sv -o /dev/null https://pypi.org 2>&1 | grep issuer:'
```

```text
*   issuer: C=US; ST=; L=; street=; postalCode=; O=Docker Sandboxes; CN=Docker Sandboxes Proxy CA
*   issuer: C=BE; O=GlobalSign nv-sa; CN=GlobalSign Atlas R3 DV TLS CA 2025 Q4
```

httpbin.org, which has HTTP rules, is served with the proxy's certificate. pypi.org, allowed by
a plain host rule in Balanced, keeps its real certificate: `forward-bypass` in the policy log.
The CA is installed in the sandbox image (`/usr/local/share/ca-certificates/proxy-ca.crt`).
Tools that ship their own CA list instead of the system store, or pin certificates, fail on
hosts with HTTP rules.

## 4. Work the approval queue

The two blocked requests from step 2 are waiting:

```shell
sbx policy approval ls | cut -c1-110
```

```text
APPROVAL                                              SANDBOX     TITLE                              DETAIL
network:99Ljl22mWkvPIQzLrXHYj8JbQcSRCONRZv45W_vxM6Q   lab-04-l7   httpbin.org:443                    Protocol:
network:i9YFZTeQXOefSpwF1DMXJm-TmgQwMP2yXcs286gwVUQ   lab-04-l7   POST httpbin.org:443/anything/ok   Protocol:
network:seNH16VL4JMkYrwxAJCdPqIUpRo4vl_GFG_iG3-pIP0   lab-04-l7   GET httpbin.org:443/headers        Protocol:
```

Approve the POST:

```shell
A=$(sbx policy approval ls --json | jq -r '.[] | select(.title == "POST httpbin.org:443/anything/ok") | .id')
sbx policy approval inspect $A && sbx policy approval respond $A --option allow
```

```text
    ○ APPROVAL network:i9YFZTeQXOefSpwF1DMXJm-TmgQwMP2yXcs286gwVUQ — sandbox lab-04-l7
        POST httpbin.org:443/anything/ok
        Protocol: HTTP Method: POST Target scope: httpbin.org:443 Path: /anything/ok no matching allow rule (default deny)

    OPTION    LABEL
    allow     Allow
    dismiss   Dismiss

  Recorded answer Allow
```

```shell
sleep 3; for p in /anything/ok /anything/other; do
  sbx exec lab-04-l7 curl -s -o /dev/null -w "POST $p %{http_code}\n" -X POST https://httpbin.org$p
done
sbx policy ls --json | jq -r '.rules[] | select(.applies_to == "sandbox:lab-04-l7") |
  "\(.decision) \(.methods) \(.http_targets[0].host)\(.http_targets[0].path)  created via \(.provenance.created_via)"'
```

```text
POST /anything/ok 200
POST /anything/other 403
allow ["GET"] httpbin.org/anything/**  created via added
allow ["POST"] httpbin.org:443/anything/ok  created via approval
```

Approving wrote a **permanent rule for exactly that request**: one method, one path, this
sandbox. `POST /anything/other` is still blocked. `sbx policy ls --wide --created-via approval`
lists every rule that came from an approval, so you can review them later.

This is the closest thing sbx has to OpenShell's **policy advisor**. There is no rule drafting
from patterns and no proposals from the agent: a person answers each request.

## 5. Dismiss is a one-time no

```shell
D=$(sbx policy approval ls --json | jq -r '.[] | select(.title == "GET httpbin.org:443/headers") | .id')
sbx policy approval respond $D --option dismiss
sleep 2; sbx exec lab-04-l7 curl -s -o /dev/null -w "GET /headers %{http_code}\n" https://httpbin.org/headers
sbx policy approval ls | grep headers | cut -c1-110
```

```text
  Recorded answer Dismiss

GET /headers 403
network:seNH16VL4JMkYrwxAJCdPqIUpRo4vl_GFG_iG3-pIP0   lab-04-l7   GET httpbin.org:443/headers           Protoc
```

Dismissing writes no rule. The request stays blocked, and the next attempt queues the same
approval again (same ID: IDs are derived from the sandbox and the request). To block something
for good, add a **deny** rule.

## 6. Deny-list style: allow the host, deny a method

A plain host allow opens **every** method and path, even next to method rules:

```shell
sbx policy allow network --sandbox lab-04-l7 httpbin.org
sleep 3; for m in POST DELETE; do
  sbx exec lab-04-l7 curl -s -o /dev/null -w "$m /anything/other %{http_code}\n" -X $m https://httpbin.org/anything/other
done
```

```text
  Added rule cb3c94b5-1cd9-4531-9025-58768bb860cd to policy local (scope: sandbox:lab-04-l7): httpbin.org [tcp]

POST /anything/other 200
DELETE /anything/other 200
```

That is the most common surprise with sbx L7 rules: **a method rule only restricts a host that
has no plain host allow.** A method **deny** still works on top:

```shell
sbx policy deny network --sandbox lab-04-l7 httpbin.org --method DELETE
sleep 3; for m in POST DELETE; do
  sbx exec lab-04-l7 curl -s -o /dev/null -w "$m /anything/other %{http_code}\n" -X $m https://httpbin.org/anything/other
done
```

```text
  Added rule 20e06cf6-0335-4309-b660-f41e327cf5c1 to policy local (scope: sandbox:lab-04-l7): DELETE httpbin.org/**

POST /anything/other 200
DELETE /anything/other 403
```

Pick one style per host: an allow-list of methods and paths (safer: new endpoints stay closed),
or a host allow with denies for the dangerous methods.

## 7. policy check and its limit

```shell
sbx policy check network --sandbox lab-04-l7 https://httpbin.org/anything/ok
```

```text
    HTTP authorization required:  httpbin.org:443
    Governance:                   Local policy only
    Context:                      sandbox:lab-04-l7
    Reason:                       authorization required by policy
```

`sbx policy check` evaluates the **connection** (host and port), with the same engine the proxy
uses. For a host with HTTP rules it can only say that the request will be judged at the HTTP
level. It cannot answer "would `POST /anything/ok` be allowed?", and it exits 1 here.

This is the closest thing to OpenShell's **policy prover**, and it is much smaller: a prover
answers questions about **every possible** request (for example "can any request write to
this host?") and gives a counterexample. `policy check` answers one concrete connection.

## 8. Clean up

```shell
sbx rm --force lab-04-l7; sbx policy approval ls
```

```text
  Removed sandbox lab-04-l7

  No pending approvals.
```

Removing the sandbox removes its rules, including the ones approvals created, and its pending
approvals.

## Exercises

1. Allow `GET,HEAD` on `/get` only, then check what `curl -I https://httpbin.org/get` and
   `curl https://httpbin.org/get?x=1` return.
2. Write a deny-list for a host: allow it, deny `POST,PUT,PATCH,DELETE`. Which methods are left?
3. Find out what a tool that does not use the system CA store sees on a host with HTTP rules
   (try `python3 -c 'import ssl; print(ssl.get_default_verify_paths())'` and a Node script).

## Watch the solution

Every step of this lab, typed and run against a real sbx daemon:

```shell
make replay LAB=04          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=04     # asciinema
labs/04-l7-rules-and-approvals/solution.sh   # replay it live against your own daemon (PAUSE=0 for full speed)
```

## Check your work

```shell
bats labs/04-l7-rules-and-approvals/test.bats
```

**Next:** [Lab 05 — Credentials the agent never sees](../05-credentials/README.md)
