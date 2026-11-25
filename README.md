# Lumma Stealer — Static Analysis & PCAP Forensics Lab

A disposable, **no-network** Linux container for studying a Lumma Stealer
capture from [malware-traffic-analysis.net](https://www.malware-traffic-analysis.net)
**without executing the sample**.

## ⚠️ What this lab does and does not do

| | |
|---|---|
| ✅ Parse the PCAP → C2 domains, download URLs, exfil POSTs, TLS SNI | |
| ✅ Static-analyze the PE → strings, imports, sections/entropy, capa, YARA, ClamAV | |
| ❌ **Run / detonate the malware** | Lumma is a Windows PE. This is a Linux container and it never loads the sample. |

**If you want to watch it actually infect**, Docker is the wrong tool — a Linux
container can't run a PE, and a *Windows* container is **not a security boundary**
(shares the host kernel; malware can be container-aware and escape). Use a
disposable **VM** (VirtualBox/VMware) with host-only networking + INetSim or
FakeNet-NG and snapshots instead. Windows Sandbox is **not** on Home edition.

## Layout

```
Dockerfile          analysis toolbox (tshark, pefile, capa, yara, radare2, clamav)
docker-compose.yml  runs it with --network none, read-only, caps dropped
analyze.sh          the offline analysis pass (entrypoint)
samples/            <-- you put the UNZIPPED pcap + dropped files here
rules/              <-- optional: drop Lumma YARA rules here
output/             <-- reports land here
```

## Safe-handling rules (read before touching a sample)

1. **Get the files yourself** from malware-traffic-analysis.net. The zips are
   password-protected and the site now uses a **new password scheme** — the
   password is on the site's **about page** (no longer `infected`).
2. **Unzip only into `samples/`.** Do not let Windows/Defender index the PE
   elsewhere, and never double-click anything.
3. Keep `samples/` mounted **read-only** (the compose file already enforces this).
4. The container runs with **no network** — keep it that way. Never add
   `--privileged`, never mount the Docker socket.
5. Delete `samples/` when done; treat `output/` reports as the keepable artifact.

## Usage

```powershell
# 1. Build the image (first run downloads tools + ClamAV signatures)
docker compose build

# 2. Put the UNZIPPED capture + dropped files into .\samples\
#    e.g. 2026-xx-xx-Lumma-Stealer-infection-traffic.pcap
#         and the dropped .exe / .dll files

# 3. Run the analysis pass
docker compose run --rm analysis

# 4. Read the report
#    .\output\report-<timestamp>.txt
```

## What to look for in the report

- **DNS / HTTP host list** → Lumma C2 domains (often short-lived, random-looking).
- **HTTP POST** to a `.php` endpoint with a content-length → the stealer exfil.
- **TLS SNI** → encrypted C2 / Telegram / Steam dead-drop resolvers.
- **PE sections with entropy ~7.9** → packed/encrypted payload.
- **capa output** → ATT&CK techniques (anti-analysis, credential access, etc.).

Cross-check these against the `*-notes.txt` that ships with the capture.
