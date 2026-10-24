#!/usr/bin/env bash
# Lab 03 solution: replays the lab against your sbx daemon.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 03 — Default-deny networking"
run_quiet 'sbx rm --force lab-03-net; rm -rf ~/sbx-labs/03'
run 'mkdir -p ~/sbx-labs/03 && sbx run -d --name lab-03-net shell ~/sbx-labs/03'
say "Balanced: registries and AI providers yes, everything else no"
run "for url in https://pypi.org https://example.com https://postman-echo.com/get http://169.254.169.254/; do sbx exec lab-03-net curl -s -o /dev/null -w \"\$url %{http_code}\n\" --max-time 10 \$url; done"
run "sleep 2; sbx policy log lab-03-net --json | jq -r '(.blocked[:3][] | \"DENY   \\(.host)  \\(.reason)\"), (.allowed[] | select(.host == \"pypi.org:443\") | \"ALLOW  \\(.host)  \\(.proxy_type)\")'"
say "How: every program is pointed at the daemon's proxy"
run "sbx exec lab-03-net sh -c 'env | grep -i ^https_proxy'"
say "Going around the proxy does not work"
run "sbx exec lab-03-net curl -sS --noproxy '*' --max-time 8 -o /dev/null https://example.com"
run "sbx exec lab-03-net sh -c 'getent hosts example.com || echo no DNS answer for example.com; getent hosts pypi.org | head -1'"
run "sbx exec lab-03-net curl -sS --noproxy '*' --max-time 8 -o /dev/null https://1.1.1.1"
run 'IP=$(getent ahostsv4 tcpbin.com | awk "NR==1{print \$1}"); echo "host reply: [$(echo hello | nc -q2 $IP 4242)]"; sbx exec lab-03-net bash -c "exec 3<>/dev/tcp/$IP/4242 && echo connected to $IP:4242; echo hello >&3; echo sandbox reply: [\$(timeout 5 head -1 <&3)]"'
run "sleep 2; sbx policy log lab-03-net --json | jq -r '.blocked[:4][] | \"\\(.last_seen[11:19])  \\(.proxy_type)  \\(.host)  \\(.reason)\"'"
say "Open one host for this sandbox only"
run 'sbx policy allow network --sandbox lab-03-net postman-echo.com'
run 'sleep 3; sbx exec lab-03-net curl -s -o /dev/null -w "%{http_code}\n" https://postman-echo.com/get'
run 'sbx policy check network postman-echo.com; sbx policy check network --sandbox lab-03-net postman-echo.com'
say "No per-program rules: python gets the same answer (with a normal User-Agent)"
run "sbx exec lab-03-net python3 -c 'import urllib.request as u; print(u.urlopen(u.Request(\"https://postman-echo.com/get\", headers={\"User-Agent\": \"curl/8\"}), timeout=10).status)'"
run "sbx exec lab-03-net curl -sS -A 'Python-urllib/3.14' https://postman-echo.com/get; echo"
say "Deny-all for one sandbox: deny beats allow"
run "sbx policy deny network --sandbox lab-03-net '**'"
run "sleep 3; for url in https://pypi.org https://postman-echo.com/get; do sbx exec lab-03-net curl -s -o /dev/null -w \"\$url %{http_code}\n\" --max-time 10 \$url; done"
run "sbx policy ls --json | jq -r '.rules[] | select(.applies_to == \"sandbox:lab-03-net\") | \"\\(.decision)  \\(.resources | join(\",\"))\"'"
say "Remove the rules again"
run "sbx policy rm network --sandbox lab-03-net --resource '**' --force; sbx policy rm network --sandbox lab-03-net --resource postman-echo.com --force"
run 'sleep 3; sbx exec lab-03-net curl -s -o /dev/null -w "%{http_code}\n" https://postman-echo.com/get'
say "Clean up"
run 'sbx rm --force lab-03-net; rm -rf ~/sbx-labs/03'
