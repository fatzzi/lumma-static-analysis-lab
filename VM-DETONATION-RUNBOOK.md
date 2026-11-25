# Lumma Stealer — Isolated VM Detonation Runbook

A step-by-step procedure to **safely detonate** a Lumma Stealer sample in a
disposable virtual machine and capture **reproducible proof that it extracts
saved emails and passwords** — without the malware ever reaching the internet,
a real account, or your host machine.

> **Why a VM and not Docker:** Lumma is a Windows PE. A Linux Docker container
> can't run it, and a *Windows* container shares the host kernel and is **not a
> security boundary**. Live detonation requires a real, snapshot-isolated VM.
> This runbook is the companion to the static-analysis lab in this repo.

---

## ⚠️ Safety contract (read fully before you start)

Follow **every** rule. Lumma is live, information-stealing malware.

1. **Air-gap the VM.** No NAT, no bridged adapter, no internet. Host-only
   networking **only**. The malware must never reach its real C2.
2. **No bridges to your real data.** Disable shared folders, shared clipboard,
   and drag-and-drop between host and guest.
3. **Fake credentials only.** Seed *canary* emails/passwords that exist nowhere
   real. Never log into a real account inside the VM. Never put real data in it.
4. **Snapshot before, revert after.** Treat the VM as burn-after-use.
5. **Host hygiene.** Transfer the sample into the VM via a read-only mechanism
   (see §4). Keep the zipped sample on the host; unzip only inside the VM.
6. **Isolated host, ideally.** Run this on a machine you can afford to rebuild,
   not your primary workstation, if possible.

This procedure is for **authorized coursework / defensive malware analysis**.

---

## 1. Prerequisites

| Component | Notes |
|-----------|-------|
| **VirtualBox** (or VMware) | Free; this runbook uses VirtualBox terms |
| **Windows 10/11 VM** | A throwaway eval VM. [FLARE-VM](https://github.com/mandiant/flare-vm) is ideal — it ships the analysis tools below |
| **FakeNet-NG** | Fakes all network services so you capture exfil offline. Bundled in FLARE-VM |
| **Procmon** (Sysinternals) | Shows the stealer reading browser credential databases |
| **Wireshark** | Confirms exfil traffic on the host-only segment |
| **Regshot** (optional) | Before/after registry + filesystem diff |
| The **Lumma sample** | From malware-traffic-analysis.net, still zipped |
| `seed-canary-creds.ps1` | In this repo — plants trackable fake credentials |

---

## 2. Build the isolated VM

1. Install Windows in a new VirtualBox VM (or import FLARE-VM).
2. Install the analysis tools (skip if using FLARE-VM).
3. **Network isolation** — VM **Settings → Network**:
   - Adapter 1: **Host-only Adapter** (e.g. `VirtualBox Host-Only Ethernet`).
   - **Disable** any NAT/Bridged adapter. Confirm only host-only remains.
4. **Settings → Shared Folders:** remove all.
5. **Settings → General → Advanced:** Shared Clipboard = **Disabled**,
   Drag'n'Drop = **Disabled**.
6. Inside the VM, confirm no internet: `ping 8.8.8.8` must **fail**.

---

## 3. Seed canary credentials (the proof mechanism)

The demo's strength is a **honeytoken**: a unique string planted as a saved
login, which you later find verbatim in the captured exfil. If the exact canary
appears in the C2 upload, the stealer provably read it.

Inside the VM:

1. Open a browser (Chrome/Edge/Firefox) and let it create a profile.
2. Run `seed-canary-creds.ps1` from this repo (copy its text in; see §4).
   It prints a unique canary email + password and saves them to the browser's
   password store (and leaves a canary file + registry marker as backups).
3. **Write down the canary token** it prints, e.g.
   `CANARY-7f3a91e2`. You will grep for this later.

> Credential vaults are DPAPI-encrypted per-user, which is exactly what Lumma
> decrypts with `CryptUnprotectData`. Seeding a real saved login (not just a
> text file) is what makes the demo authentic.

---

## 4. Transfer the sample into the VM (one-way)

With networking already host-only and shares disabled, move the **zipped**
sample in via a temporary read-only method, then **re-isolate**:

- Attach the zip on a **read-only** virtual optical disc (ISO), **or**
- Temporarily enable a **read-only** shared folder, copy in, then **remove it**.

Unzip the sample **inside the VM only**, into `C:\detonation\`. Never unzip on
the host.

---

## 5. Arm monitoring, snapshot, detonate

1. Start **FakeNet-NG** (as admin). It now answers all DNS/HTTP/HTTPS, so the
   stealer "reaches" its C2 but you capture everything locally. It writes a
   PCAP and logs requested domains.
2. Start **Procmon**; set a filter for your browser's profile path and for
   `Process Name is <sample>.exe`.
3. (Optional) Take a **Regshot** first snapshot.
4. **VirtualBox → take a VM snapshot** named `pre-detonation`.
5. **Detonate:** run the sample (double-click or from an admin cmd in
   `C:\detonation\`). Give it 1–3 minutes.
6. Stop FakeNet-NG and Procmon. (Optional) Regshot second snapshot + compare.

---

## 6. Collect the evidence

You now have three independent, reinforcing proofs:

**A. Exfil contains the canary (the headline result)**
- In FakeNet-NG's capture/logs, search for your canary token:
  ```
  findstr /S /I "CANARY-7f3a91e2" C:\path\to\fakenet\logs\*
  ```
  or open the FakeNet PCAP in Wireshark → *Follow HTTP Stream* on the POST to
  the C2 host, and show the canary email/password inside the uploaded body.
  **This is the money shot: the exact seeded credential leaving the machine.**

**B. Procmon shows the credential-store reads**
- Filter Procmon to the sample → show `ReadFile` on
  `...\Chrome\User Data\Default\Login Data` (or Firefox `logins.json`), cookie
  DBs, and wallet paths. Proof it touched the vault.

**C. FakeNet domain log = the C2 destination**
- The requested hostname(s) the sample tried to reach — your reproduced C2 IOC,
  matching the original capture's notes.

---

## 7. Cleanup

1. **VirtualBox → restore the `pre-detonation` snapshot** (or delete the VM).
   The infected state is gone.
2. Securely delete the sample zip from the host when finished.
3. Keep only the **evidence artifacts** (FakeNet PCAP, Procmon CSV, screenshots)
   — these are safe, non-executable, and are what you show your prof.

---

## 8. What to present (reproducibility story)

Hand your prof a package that lets them rerun it:

1. **This repo** — static lab (reproducible environment + capability evidence).
2. **This runbook** — exact VM build + detonation steps.
3. **`seed-canary-creds.ps1`** — so the canary is reproducible.
4. **Evidence set** — the FakeNet PCAP/stream showing the canary in the exfil,
   the Procmon trace of the vault reads, and the C2 domain log.

The claim you can defend: *"Given the same sample, VM recipe, and seed script,
the stealer reproducibly reads the seeded credential store and transmits the
exact canary email/password to its C2 — demonstrated here without any real
account or internet exposure."*

---

## Appendix — troubleshooting

- **Sample exits instantly / does nothing:** Lumma often has anti-VM/anti-sandbox
  checks and short-lived C2. It may refuse to run, or run but find its real C2
  dead. FakeNet-NG answering the C2 hostname usually keeps it going; if not, the
  **static** evidence in this repo plus the **original** capture's PCAP still
  prove the behavior.
- **No canary in exfil but Procmon shows vault reads:** the build may encrypt the
  upload before FakeNet sees plaintext. Fall back to proof **B** + **C**, and note
  the encrypted POST body + its size as the exfil indicator.
- **VM has internet by mistake:** stop immediately, revert the snapshot, and fix
  the adapter config before retrying. Never detonate with live networking.
