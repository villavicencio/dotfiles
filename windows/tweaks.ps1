#Requires -Version 7
<#
.SYNOPSIS
    Windows system settings, recorded so a rebuild reproduces them. The counterpart
    of macOS `defaults write`.

.DESCRIPTION
    Each entry in $Tweaks below reads the live value, compares it with the value the
    repo records, and reports one of:

      ok         already set; nothing done
      would set  -DryRun: it differs, and this is what would change
      set        it differed and was changed (prior value saved to the backup dir)

    Only settings this PC already had are recorded here. The script is a no-op on
    the machine it was written on; that is what its -DryRun proves. To add one,
    change it by hand first, then record it and check that -DryRun reads "ok".

    This is a separate, opt-in step, not part of install.ps1: some entries write
    HKLM or run w32tm and need an elevated shell, and install.ps1 stays unelevated.
    Entries marked "admin" are still read (and reported ok) from a normal shell;
    only changing them needs elevation, and an unelevated run that would have to
    change one records it as a failure instead of prompting.

    Before anything changes, the prior values are written to
    %LOCALAPPDATA%\dotfiles\tweaks-backups\<timestamp>-<pid>\ (never overwritten). A
    failing entry does not stop the others; the script exits 1 and lists them.

.EXAMPLE
    pwsh -File windows/tweaks.ps1 -DryRun   # preview; reads only, changes nothing
    pwsh -File windows/tweaks.ps1           # apply (elevated, for the admin entries)
#>
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$Failures = [System.Collections.Generic.List[string]]::new()
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$BackupDir = $null

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Would($msg) { Write-Host "[dry-run] would $msg" -ForegroundColor Yellow }

# SystemParametersInfo is the only way to change the mouse settings for the running
# session: writing HKCU\Control Panel\Mouse alone takes effect at the next sign-in.
if (-not ('DotfilesTweaks.User32' -as [type])) {
    Add-Type -Namespace DotfilesTweaks -Name User32 -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
'@
}
$SPI_GETMOUSE = 0x0003
$SPI_SETMOUSE = 0x0004
$SPIF_UPDATEINIFILE = 0x01   # also write the user profile (the HKCU values below)
$SPIF_SENDCHANGE = 0x02      # broadcast WM_SETTINGCHANGE

# --- registry helpers --------------------------------------------------------

# Render the current values of $Values as "Name=value" pairs. A value that is absent
# reads "<absent>"; one stored with a different registry type gets its type appended,
# so a String "2" never passes for a DWord 2.
function Get-RegState([object[]]$Values) {
    ($Values | ForEach-Object {
        $key = Get-Item -LiteralPath $_.Path -ErrorAction SilentlyContinue
        $cur = if ($key) { $key.GetValue($_.Name, $null, 'DoNotExpandEnvironmentNames') }
        if ($null -eq $cur) { "$($_.Name)=<absent>"; return }
        $kind = $key.GetValueKind($_.Name).ToString()
        "$($_.Name)=$cur$(if ($kind -ne $_.Type) { " [$kind]" })"
    }) -join ' '
}
function Get-RegWant([object[]]$Values) {
    ($Values | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '
}
function Set-RegValues([object[]]$Values) {
    foreach ($v in $Values) {
        # Never New-Item -Force an existing registry key: that recreates it empty.
        if (-not (Test-Path -LiteralPath $v.Path)) { New-Item -Path $v.Path | Out-Null }
        New-ItemProperty -LiteralPath $v.Path -Name $v.Name -PropertyType $v.Type -Value $v.Value -Force | Out-Null
    }
}
function RegValue($Path, $Name, $Type, $Value) {
    @{ Path = $Path; Name = $Name; Type = $Type; Value = $Value }
}

# --- Windows Terminal --------------------------------------------------------

function Get-TerminalSettingsPath {
    @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"   # unpackaged install
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
# Anchored to a line that starts with the key, so a commented-out
# `// "defaultProfile": ...` line (Terminal's settings are JSON with comments) never matches.
$DefaultProfileRx = '(?m)(^[ \t]*"defaultProfile"\s*:\s*")([^"]*)(")'

# --- the tweaks --------------------------------------------------------------
# Each entry: Label, Why (one line), Admin (needs elevation to change), and either
# Registry (values read by Get-RegState, written by Set-RegValues) or custom
# Get/Want/Set. A Set on a Registry entry replaces the plain registry write with the
# API that also applies the change live; Live/LiveWant add a check of the running
# session's value. Note is printed after a set.
# Never name a key Values, Keys or Count: on an entry without that key, $t.Values
# silently returns the hashtable's own .Values collection instead of $null.

$Tweaks = @(
    @{
        Label  = 'Mouse acceleration off ("Enhance pointer precision")'
        Why    = 'Raw 1:1 pointer movement for games; turned off 2026-09-24.'
        Registry = @(
            RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed'      'String' '0'
            RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' 'String' '0'
            RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' 'String' '0'
        )
        # The registry is what persists; SPI_GETMOUSE is what the session is using.
        # Both must agree, or a registry-only change still waits for a sign-in.
        Live   = {
            $m = [int[]]::new(3)
            if (-not [DotfilesTweaks.User32]::SystemParametersInfo($SPI_GETMOUSE, 0, $m, 0)) {
                throw "SPI_GETMOUSE failed (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
            }
            "live=$($m -join ',')"   # [threshold1, threshold2, speed]
        }
        LiveWant = 'live=0,0,0'
        # One call sets the session value AND writes the three HKCU values above.
        Set    = {
            $m = [int[]](0, 0, 0)
            if (-not [DotfilesTweaks.User32]::SystemParametersInfo($SPI_SETMOUSE, 0, $m, $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)) {
                throw "SPI_SETMOUSE failed (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
            }
        }
    }
    @{
        Label  = 'Game Bar background recording off ("Record what happened")'
        Why    = 'Background capture keeps the GPU encoder recording through every game.'
        Registry = @( RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 'DWord' 0 )
        Note   = 'A Game Bar that is already running may keep recording until you sign out.'
    }
    @{
        Label  = 'Hardware-accelerated GPU scheduling on'
        Why    = 'Lets the GPU manage its own scheduling queue (Settings > Display > Graphics).'
        Admin  = $true
        Registry = @( RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 'DWord' 2 )   # 2 on, 1 off
        Note   = 'Takes effect after a restart.'
    }
    @{
        Label  = 'Windows Time syncs from time.windows.com'
        Why    = 'The clock had never synced (source "Local CMOS Clock", 84 s fast) until 2026-09-24.'
        Admin  = $true
        Registry = @(
            RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' 'NtpServer' 'String' 'time.windows.com,0x9'
            RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' 'Type'      'String' 'NTP'
        )
        # w32tm writes the same two values; /update is what makes the running service
        # re-read them, and /resync syncs now instead of at the next poll.
        Set    = {
            if ((Get-Service W32Time).Status -ne 'Running') { Start-Service W32Time }
            w32tm /config '/manualpeerlist:time.windows.com,0x9' /syncfromflags:manual /update
            if ($LASTEXITCODE -ne 0) { throw "w32tm /config failed (exit $LASTEXITCODE)" }
            w32tm /resync
            if ($LASTEXITCODE -ne 0) { throw "w32tm /resync failed (exit $LASTEXITCODE)" }
        }
    }
    @{
        Label = 'Windows Terminal default profile = PowerShell 7'
        Why   = 'New tabs open pwsh, where the dotfiles profile lives, not Windows PowerShell 5.1.'
        # Terminal rewrites its own settings.json, and a fragment cannot set
        # defaultProfile, so only that one line is edited in place.
        Get   = {
            $p = Get-TerminalSettingsPath
            if (-not $p) { return '<settings.json not found>' }
            $m = [regex]::Match((Get-Content -Raw -LiteralPath $p), $DefaultProfileRx)
            if ($m.Success) { $m.Groups[2].Value } else { '<no defaultProfile key>' }
        }
        Want  = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
        Set   = {
            $p = Get-TerminalSettingsPath
            if (-not $p) { throw 'Windows Terminal settings.json not found: launch Terminal once, then re-run' }
            Copy-Item -LiteralPath $p (Join-Path (Get-BackupDir) 'windows-terminal-settings.json')
            $bytes = [IO.File]::ReadAllBytes($p)
            $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
            $text = [IO.File]::ReadAllText($p)
            if (-not [regex]::IsMatch($text, $DefaultProfileRx)) {
                throw 'no "defaultProfile" key in settings.json; set it once in Terminal > Settings > Startup'
            }
            $text = ([regex]$DefaultProfileRx).Replace($text, '${1}{574e775e-4f2a-5b96-ac1e-a2962a402336}${3}', 1)
            [IO.File]::WriteAllText($p, $text, [Text.UTF8Encoding]::new($bom))
        }
        Note  = 'Terminal reloads settings.json on change; open tabs keep their profile.'
    }
)

# --- engine -----------------------------------------------------------------

function Get-BackupDir {
    if (-not $script:BackupDir) {
        # The PID makes the name unique per run; creating it without -Force fails
        # rather than reuse a directory that already exists.
        $parent = Join-Path $env:LOCALAPPDATA 'dotfiles\tweaks-backups'
        New-Item -ItemType Directory -Force $parent | Out-Null
        $dir = Join-Path $parent "$(Get-Date -Format yyyyMMdd-HHmmss)-$PID"
        New-Item -ItemType Directory $dir | Out-Null
        $script:BackupDir = $dir
    }
    $script:BackupDir
}

# Append one record of what a tweak read before it changed anything.
function Save-Prior([string]$Label, [string]$Current, [string]$Want) {
    $file = Join-Path (Get-BackupDir) 'prior-values.json'
    $records = @(if (Test-Path -LiteralPath $file) { Get-Content -Raw -LiteralPath $file | ConvertFrom-Json })
    $records += [pscustomobject]@{ tweak = $Label; prior = $Current; desired = $Want; at = (Get-Date -Format o) }
    ConvertTo-Json -InputObject $records -Depth 3 | Set-Content -LiteralPath $file -Encoding utf8NoBOM
}

function Get-TweakState($t) {
    $cur = if ($t.Registry) { Get-RegState $t.Registry } else { & $t.Get }
    $want = if ($t.Registry) { Get-RegWant $t.Registry } else { $t.Want }
    if ($t.Live) { $cur = "$cur $(& $t.Live)"; $want = "$want $($t.LiveWant)" }
    [pscustomobject]@{ Current = $cur; Want = $want }
}

Write-Step "system tweaks$(if (-not $IsAdmin) { ' (not elevated: admin entries are read-only this run)' })"
foreach ($t in $Tweaks) {
    $tag = if ($t.Admin) { ' [admin]' } else { '' }
    try {
        $s = Get-TweakState $t
        if ($s.Current -eq $s.Want) { Write-Host "    ok      $($t.Label)$tag"; continue }
        if ($DryRun) {
            Write-Would "set $($t.Label)$tag"
            Write-Host "              now:  $($s.Current)"
            Write-Host "              want: $($s.Want)"
            continue
        }
        if ($t.Admin -and -not $IsAdmin) {
            throw 'needs an elevated shell (re-run from an Administrator pwsh)'
        }
        Save-Prior $t.Label $s.Current $s.Want
        if ($t.Set) { & $t.Set } else { Set-RegValues $t.Registry }
        $after = Get-TweakState $t
        if ($after.Current -ne $after.Want) { throw "still differs after set: $($after.Current)" }
        Write-Host "    set     $($t.Label)$tag"
        if ($t.Note) { Write-Host "            $($t.Note)" }
    } catch {
        $Failures.Add("$($t.Label): $($_.Exception.Message)")
        Write-Warning "$($t.Label) failed: $($_.Exception.Message)"
    }
}

if ($BackupDir) { Write-Host "`nPrior values saved to $BackupDir" }
if ($Failures.Count) {
    Write-Host "`nCompleted with $($Failures.Count) failure(s)$(if ($DryRun) { ' (dry run - nothing was changed)' }):" -ForegroundColor Red
    $Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
} elseif ($DryRun) {
    Write-Step 'Dry run complete - nothing was changed.'
} else {
    Write-Step 'Tweaks complete.'
}
