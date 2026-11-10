# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A graduation-thesis (DATN, PTIT) SOC/SIEM lab: ModSecurity v3 + OWASP CRS v4 WAF in front of DVWA, with Wazuh SIEM detecting attacks and Active Response blocking the attacker. There is no application code, build system, or test suite — the repo is infrastructure config, Bash scripts, and Vietnamese-language guides in `docs/`. It's edited on Windows but **every file runs on Linux VMs**, which pull it from GitHub with `git pull`. Nothing here runs locally.

The docs (`README.md`, `docs/*.md`) are in Vietnamese. Write new docs in Vietnamese and follow the existing phase-guide style (numbered steps, verification checkpoints, troubleshooting tables, checklists).

## Topology (3 VMs, `192.168.1.0/24`)

| VM | IP | Role | Repo files used there |
| --- | --- | --- | --- |
| VM1 Kali | `.10` | Attacker | `scripts/test-attacks.sh` |
| VM2 Ubuntu | `.20` | Docker host (WAF + DVWA) + Wazuh Agent | `vm2-web-target/`, `scripts/setup-vm2-*.sh`, `vm3-wazuh-manager/agent-config/ossec.conf` (reference) |
| VM3 Ubuntu | `.30` | Wazuh all-in-one (manager 1514/1515, indexer 9200, dashboard 443) | `vm3-wazuh-manager/custom-rules/`, `vm3-wazuh-manager/shared/windows/agent.conf` |
| VM4 Windows 10 | `.40` | Endpoint: Wazuh agent (group `windows`) + Sysmon | `vm4-windows-client/`, `scripts/*.ps1` (Phase 5) |

IPs and versions come from `.env` (copied from `.env.example`; `.env` is gitignored). `setup-vm2-agent.sh` reads `.env` and positional args override it. Other scripts and configs hardcode `192.168.1.x`, so an IP change has to be made in several places.

## End-to-end pipeline (spans several files)

1. **WAF**: `vm2-web-target/docker-compose.yml` runs the prebuilt image `owasp/modsecurity-crs:nginx-alpine`, configured entirely through `MODSEC_*` env vars: host port 80 → container 8080, backend `dvwa:80`, audit log in JSON, Serial, `RelevantOnly` with status `^(?:5|4(?!04))`. The audit log goes through a bind mount to the host at `/var/log/modsec/modsec_audit.log`.
   - **Gotcha:** compose has no `build:` section, so `docker/modsecurity/Dockerfile`, `conf/nginx.conf` and `conf/modsec.conf` are **not used** by the running stack, even though the docs say `docker compose up -d --build`. To change WAF behaviour, edit the env vars in compose, or add a `build:` section first. (The Dockerfile/nginx.conf listen on port 80, not 8080.)
2. **Agent (VM2 host)**: `scripts/setup-vm2-agent.sh` purges and reinstalls `wazuh-agent` at the pinned `WAZUH_VERSION` (it must match the manager, currently 4.8.2-1). It keeps `client.keys` across reinstalls, enrolls through `agent-auth`, and injects a `<localfile><log_format>json</log_format>` block for the audit log.
3. **Rules (VM3)**: `vm3-wazuh-manager/custom-rules/modsec_crs4_rules.xml` is copied to `/var/ossec/etc/rules/`. Rule chain:
   - `100100`: any JSON event that has `transaction.client_ip`.
   - `100101`: the event has `http_code` 403.
   - `100102`–`100105`: SQLi/XSS/LFI/RCE, matched by message text or CRS rule-ID prefix (942/941/930/932) in `transaction.messages`.
   - `100110`: level 14. It fires at `frequency="8"` within `timeframe="60"`, uses `if_matched_group web_attack` and `same_field transaction.client_ip`, and triggers Active Response.
   - Correlation is on the **group** `web_attack`, not on individual SIDs. Every attack-type rule must stay inside the `<group name="modsecurity,waf,web_attack,">` wrapper.
4. **Active Response**:
   - The manager-side `<command>`/`<active-response>` block (rule 100110, `location local`, `timeout 600`) is **not in the repo**. It's documented in `docs/phase3-wazuh-siem-setup.md` §7.2 and gets pasted into VM3's `/var/ossec/etc/ossec.conf` by hand.
   - The agent-side script `docker-firewall-drop` is written as a heredoc inside `scripts/setup-vm2-active-response.sh`.
   - It inserts DROP rules into the **`DOCKER-USER`** iptables chain, because Docker's NAT bypasses INPUT. It reads the IP from the Wazuh JSON on stdin (`.parameters.alert.data.transaction.client_ip`).
   - To unblock manually: `sudo /var/ossec/active-response/bin/docker-firewall-drop delete - 192.168.1.10`.
5. **Demo**: `scripts/test-attacks.sh [http://192.168.1.20]` sends a 200 baseline, then 6 attack payloads (403 expected) and 5 burst requests (11 attacks in all, above the threshold of 8). It then expects the next request to time out because of the block.
   - **Coupled values:** if you change the rule 100110 `frequency`, update the echo text and burst count in `test-attacks.sh`, and the docs that mention "8".

## Windows endpoint pipeline (Phase 5, VM4)

- **Manager setup order matters:** create agent group `windows` *before* the agent enrolls, otherwise enrollment fails with `Invalid group`. `vm3-wazuh-manager/shared/windows/agent.conf` adds the Sysmon, PowerShell/Operational and Defender eventchannels. Security, System and Application are already in the default Windows agent config.
- **`windows_rules.xml` (100200–100213):**
  - The rules hang off built-in groups through `<if_group>`: `authentication_failed`, `windows`, `sysmon_event1`.
  - The wrapper group is `custom_windows`. It must never include `windows`, because a rule must not belong to the group it uses as `if_group`. It must also never include `web_attack`, or rule 100110 would count Windows events.
  - Sysmon fields are `win.eventdata.*` in camelCase (`commandLine`, `image`, `parentImage`). Regexes use `type="pcre2"`.
  - Built-in Sysmon rules (92xxx) may match before the custom rules. When that happens, the fix is `<if_sid>` on the built-in rule that won.
- **Active Response:**
  - Rule 100201 (8 or more 4625 events in 60s with the same `win.eventdata.ipAddress`) triggers `win-firewall-drop`. That is a `.cmd` wrapper which launches the 64-bit `.ps1`, because the agent is 32-bit.
  - The `.ps1` reads the alert JSON from stdin, adds or deletes a Windows Firewall rule named `WazuhAR-Block-<IP>`, and logs to `active-responses.log` in the agent's `active-response` folder.
  - The built-in `netsh` AR can't be used, because it only reads `data.srcip`.
  - Run it by hand with `win-firewall-drop.cmd add|delete <IP>`.
- **Demo:** use SMB brute-force (`test-windows-attacks.sh`, smbclient loop). RDP with NLA may log 4625 without a source IP.
- **Keep `.ps1` files ASCII-only.** Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI. Audit policy is set by subcategory GUID, and the Administrators group by SID `S-1-5-32-544`, so both work on any Windows display language.

## Alert export for AI triage

`scripts/export-demo-alerts.sh START END` runs on VM3 with sudo.
- **Input:** `alerts.json` for today, plus `YYYY/Mon/ossec-alerts-DD.json.gz` for earlier days.
- **Output:** `~/demo-alerts-<stamp>/{alerts.jsonl,summary.md}` and a matching `.tar.gz`.
- **Labels:** each alert gets a `ground_truth` label, assigned by rule-ID ranges, attacker IP and simulation markers (`lab-backdoor`, `WAZUH-LAB-TEST`, `sekurlsa::`).
- **Keep in sync:** if you add rules or test scenarios, update the label `if/elif` chain in the jq program.
- **Compatibility:** the jq code must stay compatible with jq 1.6, the Ubuntu 22.04 version.

## Common commands (run on the VMs, not locally)

```bash
# VM2: bring up WAF + DVWA
cd vm2-web-target && docker compose up -d
tail -n 1 /var/log/modsec/modsec_audit.log | jq .   # must parse as single-line JSON

# VM2: agent + active response
sudo bash scripts/setup-vm2-agent.sh 192.168.1.30 vm2-web-target
sudo bash scripts/setup-vm2-active-response.sh

# VM3: deploy rules
sudo cp vm3-wazuh-manager/custom-rules/modsec_crs4_rules.xml /var/ossec/etc/rules/
sudo chown wazuh:wazuh /var/ossec/etc/rules/modsec_crs4_rules.xml && sudo chmod 660 /var/ossec/etc/rules/modsec_crs4_rules.xml
sudo /var/ossec/bin/wazuh-analysisd -t && sudo systemctl restart wazuh-manager
sudo /var/ossec/bin/agent_control -l                 # confirm agent is Active

# VM1: run attack suite
bash scripts/test-attacks.sh http://192.168.1.20

# VM2: inspect blocks
sudo iptables -L DOCKER-USER -n; sudo tail /var/ossec/logs/active-responses.log
```

The only "test" is the rule-syntax check `wazuh-analysisd -t` plus the attack script. To test a single rule, feed one audit-log line to `/var/ossec/bin/wazuh-logtest` on VM3.

## Editing notes

- Line endings are enforced by `.gitattributes`: `*.sh/*.xml/*.conf/*.yml` use LF (they run on Linux), and `*.ps1/*.cmd` use CRLF.
- On this Windows host, the Bash tool collapses `\\` in inline Python and sed strings. Use Edit/Write, or PowerShell, when writing Windows paths into files.
- Custom Wazuh rule IDs must stay in the 100000+ range. Bump `level` carefully, since the Telegram integration described in phase 3 alerts on level ≥ 12.
- `docs/deployment-plan.md` holds the master checklist across phases 0–6 (5 = Windows endpoint, 6 = Cloud). If a change affects a phase, update its checklist and the matching `docs/phaseN-*.md` guide together.
