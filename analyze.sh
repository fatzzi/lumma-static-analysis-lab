#!/usr/bin/env bash
# Offline analysis pass over /samples. Writes a report to /output.
# NEVER executes a sample. Everything here only reads bytes.
set -u

SAMPLES=/samples
OUT=/output
RULES=/rules
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
REPORT="$OUT/report-$STAMP.txt"

mkdir -p "$OUT"

log() { echo "$@" | tee -a "$REPORT"; }
hr()  { log "============================================================"; }

log "Lumma / Windows stealer static + PCAP analysis"
log "Generated (UTC): $STAMP"
log "Samples dir:     $SAMPLES (read-only)"
hr

if [ -z "$(ls -A "$SAMPLES" 2>/dev/null)" ]; then
    log "[!] $SAMPLES is empty. Drop the UNZIPPED pcap and dropped files there."
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Inventory + hashes
# ---------------------------------------------------------------------------
hr; log "[1] FILE INVENTORY"; hr
find "$SAMPLES" -type f | sort | while read -r f; do
    log ""
    log "--- $f"
    log "    type:   $(file -b "$f")"
    log "    size:   $(stat -c %s "$f") bytes"
    log "    sha256: $(sha256sum "$f" | cut -d' ' -f1)"
    log "    md5:    $(md5sum "$f" | cut -d' ' -f1)"
done

# ---------------------------------------------------------------------------
# 2. PCAP forensics (network IOCs are where Lumma shows itself)
# ---------------------------------------------------------------------------
hr; log "[2] PCAP ANALYSIS (tshark)"; hr
find "$SAMPLES" -type f \( -iname '*.pcap' -o -iname '*.pcapng' \) | while read -r pcap; do
    log ""
    log ">>> $pcap"

    log ""
    log "## DNS queries"
    tshark -r "$pcap" -Y "dns.flags.response==0" -T fields -e dns.qry.name 2>/dev/null \
        | sort | uniq -c | sort -rn | tee -a "$REPORT"

    log ""
    log "## HTTP requests (host + uri + method)"
    tshark -r "$pcap" -Y "http.request" \
        -T fields -e http.request.method -e http.host -e http.request.uri 2>/dev/null \
        | sort | uniq | tee -a "$REPORT"

    log ""
    log "## HTTP POST bodies truncated (possible exfil)"
    tshark -r "$pcap" -Y "http.request.method==\"POST\"" \
        -T fields -e http.host -e http.request.uri -e http.content_length 2>/dev/null \
        | sort | uniq | tee -a "$REPORT"

    log ""
    log "## TLS SNI (server names in encrypted C2)"
    tshark -r "$pcap" -Y "tls.handshake.extensions_server_name" \
        -T fields -e tls.handshake.extensions_server_name 2>/dev/null \
        | sort | uniq -c | sort -rn | tee -a "$REPORT"

    log ""
    log "## Top conversations (endpoints by bytes)"
    tshark -r "$pcap" -q -z conv,ip 2>/dev/null | tee -a "$REPORT"
done

# ---------------------------------------------------------------------------
# 3. PE static analysis (no execution)
# ---------------------------------------------------------------------------
hr; log "[3] PE / BINARY STATIC ANALYSIS"; hr
find "$SAMPLES" -type f | while read -r f; do
    ft="$(file -b "$f")"
    case "$ft" in
        *PE32*|*MS-DOS*|*"PE "*|*Mono*|*.Net*)
            log ""
            log ">>> $f  ($ft)"

            log ""
            log "## strings (ascii, >=6, filtered sample)"
            strings -n 6 "$f" 2>/dev/null | grep -Ei 'http|\.php|\.exe|\.dll|powershell|cmd|wallet|cookie|login|token|appdata|temp|runmru' \
                | sort | uniq | head -n 200 | tee -a "$REPORT"

            log ""
            log "## pefile summary (imports / sections / entropy)"
            python3 -I - "$f" <<'PY' 2>&1 | tee -a "$REPORT"
import sys, pefile
try:
    pe = pefile.PE(sys.argv[1], fast_load=True)
    pe.parse_data_directories()
    print("  Compile time:", hex(pe.FILE_HEADER.TimeDateStamp))
    print("  Sections:")
    for s in pe.sections:
        name = s.Name.rstrip(b"\x00").decode(errors="replace")
        print(f"    {name:8} vsize={s.Misc_VirtualSize:#8x} entropy={s.get_entropy():.2f}")
    print("  Imported DLLs:")
    if hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
        for d in pe.DIRECTORY_ENTRY_IMPORT:
            print("    ", d.dll.decode(errors="replace"))
except Exception as e:
    print("  pefile error:", e)
PY

            log ""
            log "## capa (ATT&CK capabilities)"
            capa -q "$f" 2>/dev/null | tee -a "$REPORT" || log "  (capa produced no output)"
            ;;
    esac
done

# ---------------------------------------------------------------------------
# 4. YARA + ClamAV signature scans
# ---------------------------------------------------------------------------
hr; log "[4] SIGNATURE SCANS"; hr
if [ -n "$(ls -A "$RULES" 2>/dev/null)" ]; then
    log ""
    log "## YARA (rules from /rules)"
    find "$RULES" -type f \( -iname '*.yar' -o -iname '*.yara' \) | while read -r r; do
        yara -r "$r" "$SAMPLES" 2>/dev/null | tee -a "$REPORT"
    done
else
    log "## YARA: no rules in /rules (mount your Lumma rules there to enable)"
fi

log ""
log "## ClamAV"
clamscan -r --no-summary "$SAMPLES" 2>/dev/null | tee -a "$REPORT"

hr
log "Done. Full report: $REPORT"
log "Review IOCs above against the notes.txt from the capture."
