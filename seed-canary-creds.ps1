<#
    seed-canary-creds.ps1
    --------------------------------------------------------------------
    RUN THIS INSIDE THE ISOLATED DETONATION VM ONLY (see VM-DETONATION-RUNBOOK.md).

    Plants a UNIQUE "canary" email + password into the locations an
    info-stealer like Lumma harvests, so you can later grep the captured
    exfil for the exact token and prove end-to-end extraction.

    It seeds NO real accounts and touches nothing outside this VM user profile.
    This is a benign honeytoken generator for authorized malware analysis.
#>

$ErrorActionPreference = 'Stop'

# --- 1. Generate a unique, searchable canary token -----------------------
$token = "CANARY-" + ([guid]::NewGuid().ToString('N').Substring(0,8))
$email = "$token@example.test"
$pass  = "Pw-$token-Zx9"

Write-Host "==================================================================="
Write-Host " CANARY TOKEN : $token"
Write-Host " canary email : $email"
Write-Host " canary pass  : $pass"
Write-Host "==================================================================="
Write-Host " Write the token down. After detonation, search the FakeNet-NG"
Write-Host " capture/logs for it:   findstr /S /I `"$token`" <fakenet-logs>"
Write-Host "==================================================================="

# --- 2. Seed locations stealers commonly grab ----------------------------

# 2a. A plausible credentials text file on the Desktop
$desktop = [Environment]::GetFolderPath('Desktop')
$noteFile = Join-Path $desktop 'Account - Login.txt'
@"
Service : mail.example.test
Email   : $email
Password: $pass
Note    : $token
"@ | Set-Content -Encoding UTF8 $noteFile
Write-Host "[+] Seeded credentials file: $noteFile"

# 2b. User environment marker (some stealers enumerate env + user profile)
[Environment]::SetEnvironmentVariable('CANARY_CRED', "$email::$pass", 'User')
Write-Host "[+] Seeded user environment variable: CANARY_CRED"

# 2c. Clipboard (several stealers snapshot the clipboard)
try { Set-Clipboard -Value "$email $pass $token"; Write-Host "[+] Seeded clipboard" }
catch { Write-Host "[!] Clipboard seed skipped: $($_.Exception.Message)" }

# 2d. A fake 'wallet'-looking file (wallet theft is a Lumma feature)
$walletDir = Join-Path $env:APPDATA 'CanaryWallet'
New-Item -ItemType Directory -Force -Path $walletDir | Out-Null
"seed phrase canary $token`n$email`n$pass" |
    Set-Content -Encoding UTF8 (Join-Path $walletDir 'wallet.dat')
Write-Host "[+] Seeded decoy wallet: $walletDir\wallet.dat"

# --- 3. MOST AUTHENTIC: save the canary in the browser password manager ---
Write-Host ""
Write-Host "-------------------------------------------------------------------"
Write-Host " MANUAL STEP (do this for the strongest proof):"
Write-Host "   1. Open your browser's saved-passwords / password manager UI."
Write-Host "   2. Add a login:   site=https://mail.example.test"
Write-Host "                     user=$email"
Write-Host "                     pass=$pass"
Write-Host "   This lands in the DPAPI-encrypted vault the stealer decrypts,"
Write-Host "   which is the behaviour you are demonstrating."
Write-Host "-------------------------------------------------------------------"
Write-Host ""
Write-Host "Seeding complete. Proceed to arm monitoring and detonate."
