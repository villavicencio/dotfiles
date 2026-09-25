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

    Only settings this PC already had are recorded here. To add one, change it by
    hand first, then record it and check that -DryRun reads "ok". The one exception
    is Game Mode: Windows defaults it on without writing AutoGameModeEnabled, so a PC
    that never toggled it reads "would set" until the first real run writes the value.

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
# Replacing Terminal's settings.json without losing a save Terminal makes meanwhile
# (see Write-TerminalDefaultProfile). OpenLocked opens a file for read + DELETE
# while sharing only read, so no one else can write it, or rename or delete over it,
# until the handle closes. RenameByHandle moves that same open file to a new name.
if (-not ('DotfilesTweaks.FileOps' -as [type])) {
    Add-Type -Namespace DotfilesTweaks -Name FileOps -UsingNamespace Microsoft.Win32.SafeHandles, System.ComponentModel, System.Text -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
[DllImport("kernel32.dll", SetLastError = true)]
private static extern bool SetFileInformationByHandle(SafeFileHandle h, int infoClass, IntPtr info, uint size);

public static SafeFileHandle OpenLocked(string path) {
    // GENERIC_READ | DELETE, FILE_SHARE_READ, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL
    SafeFileHandle h = CreateFileW(path, 0x80000000u | 0x00010000u, 1u, IntPtr.Zero, 3u, 0x80u, IntPtr.Zero);
    if (h.IsInvalid) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
    return h;
}

public static void RenameByHandle(SafeFileHandle h, string newPath) {
    // FILE_RENAME_INFO { BOOLEAN ReplaceIfExists; HANDLE RootDirectory; DWORD FileNameLength; WCHAR FileName[]; }
    // ReplaceIfExists = FALSE, so an existing file at newPath is never overwritten.
    byte[] name = Encoding.Unicode.GetBytes(newPath);
    int nameOffset = IntPtr.Size == 8 ? 20 : 12;
    int size = nameOffset + name.Length + 2;
    IntPtr buf = Marshal.AllocHGlobal(size);
    try {
        for (int i = 0; i < size; i++) { Marshal.WriteByte(buf, i, 0); }
        Marshal.WriteInt32(buf, nameOffset - 4, name.Length);
        Marshal.Copy(name, 0, IntPtr.Add(buf, nameOffset), name.Length);
        if (!SetFileInformationByHandle(h, 3 /* FileRenameInfo */, buf, (uint)size)) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    } finally { Marshal.FreeHGlobal(buf); }
}
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

$TerminalPackagedSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$TerminalUnpackagedSettings = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"   # zip / Scoop build
$Pwsh7ProfileGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

# The settings.json of the Terminal in use. With only one present, that's it. With
# both, the running WindowsTerminal.exe decides: the packaged build runs from
# WindowsApps\Microsoft.WindowsTerminal_*, anything else is unpackaged (Preview and
# Canary are other packages with their own settings, so they don't count). If none
# is running, both kinds are, or a process path can't be read, it throws naming
# both files rather than guess. $RunningExe exists for tests.
function Get-TerminalSettingsPath {
    param(
        [string]$Packaged = $TerminalPackagedSettings,
        [string]$Unpackaged = $TerminalUnpackagedSettings,
        [string[]]$RunningExe = @(Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Path })
    )
    $havePackaged = Test-Path -LiteralPath $Packaged -PathType Leaf
    $haveUnpackaged = Test-Path -LiteralPath $Unpackaged -PathType Leaf
    if (-not ($havePackaged -and $haveUnpackaged)) {
        if ($havePackaged) { return $Packaged }
        if ($haveUnpackaged) { return $Unpackaged }
        return $null
    }
    $kinds = @($RunningExe | ForEach-Object {
            if (-not $_) { 'unreadable' }
            elseif ($_ -match '\\WindowsApps\\Microsoft\.WindowsTerminal_') { 'packaged' }
            elseif ($_ -notmatch '\\WindowsApps\\') { 'unpackaged' }
        } | Sort-Object -Unique)
    if ($kinds.Count -eq 1 -and $kinds[0] -eq 'packaged') { return $Packaged }
    if ($kinds.Count -eq 1 -and $kinds[0] -eq 'unpackaged') { return $Unpackaged }
    $seen = if ($kinds.Count) { "running: $($kinds -join ', ')" } else { 'neither is running' }
    throw ("both Terminal settings files exist and the one in use is unclear ($seen): " +
        "'$Packaged' (packaged) and '$Unpackaged' (unpackaged). " +
        'Re-run with only the Terminal you use open, or move the unused file aside.')
}

# Terminal's settings.json is JSON with comments (and trailing commas). These skip
# whitespace and comments, and find the closing quote of a string, so the scan below
# never mistakes a commented-out or quoted "defaultProfile" for the real one.
function Skip-JsonTrivia([string]$Text, [int]$i) {
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq '/' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            $nl = $Text.IndexOf("`n", $i)
            $i = if ($nl -lt 0) { $Text.Length } else { $nl + 1 }
            continue
        }
        if ($c -eq '/' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '*') {
            $close = $Text.IndexOf('*/', $i + 2, [StringComparison]::Ordinal)
            if ($close -lt 0) { throw 'settings.json has an unterminated /* comment' }
            $i = $close + 2
            continue
        }
        break
    }
    $i
}
function Get-JsonStringEnd([string]$Text, [int]$Open) {
    for ($i = $Open + 1; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq '\') { $i++ } elseif ($Text[$i] -eq '"') { return $i }
    }
    throw 'settings.json has an unterminated string'
}

# Find the value of the top-level property $Key when it is a string. Returns its
# offset and length inside the quotes (so the caller can splice just that text), or
# $null when there is no such top-level key. Keys inside nested objects or arrays,
# and anything in a comment or string, are skipped. Throws on a duplicate top-level
# key or a non-string value, since either way which one Terminal uses is unclear.
function Find-TopLevelJsonString([string]$Text, [string]$Key) {
    $i = Skip-JsonTrivia $Text 0
    if ($i -ge $Text.Length -or $Text[$i] -ne '{') { throw 'settings.json is not a JSON object' }
    $depth = 0
    $found = $null
    while (($i = Skip-JsonTrivia $Text $i) -lt $Text.Length) {
        $c = $Text[$i]
        if ($c -eq '{' -or $c -eq '[') { $depth++; $i++; continue }
        if ($c -eq '}' -or $c -eq ']') {
            $depth--
            if ($depth -lt 0) { throw 'settings.json has an unbalanced closing bracket' }
            $i++
            if ($depth -eq 0) {
                if ((Skip-JsonTrivia $Text $i) -lt $Text.Length) { throw 'settings.json has text after its top-level object' }
                break
            }
            continue
        }
        if ($c -ne '"') { $i++; continue }
        $end = Get-JsonStringEnd $Text $i
        if ($depth -eq 1) {
            $colon = Skip-JsonTrivia $Text ($end + 1)
            $name = $Text.Substring($i + 1, $end - $i - 1)
            # "defaultProfile" is the same key: decode escapes before comparing.
            if ($name.Contains('\')) { $name = ConvertFrom-Json -InputObject "`"$name`"" }
            if ($colon -lt $Text.Length -and $Text[$colon] -eq ':' -and $name -ceq $Key) {
                if ($found) { throw "settings.json has more than one top-level `"$Key`"" }
                $v = Skip-JsonTrivia $Text ($colon + 1)
                if ($v -ge $Text.Length -or $Text[$v] -ne '"') { throw "top-level `"$Key`" in settings.json is not a string" }
                $vEnd = Get-JsonStringEnd $Text $v
                $found = [pscustomobject]@{ Start = $v + 1; Length = $vEnd - $v - 1; Value = $Text.Substring($v + 1, $vEnd - $v - 1) }
                $end = $vEnd
            }
        }
        $i = $end + 1
    }
    if ($depth -ne 0) { throw 'settings.json has an unclosed { or [' }
    $found
}

function Get-BytesHash([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

# Read settings.json once: the bytes (backed up, and hashed for the unchanged check
# before the write), whether it starts with a BOM (kept on write), and the text,
# decoded strictly so invalid UTF-8 throws instead of coming back as U+FFFD.
function Read-TerminalSettings([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $skip = if ($bom) { 3 } else { 0 }
    [pscustomobject]@{
        Path  = $Path
        Bytes = $bytes
        Bom   = $bom
        Hash  = Get-BytesHash $bytes
        Text  = [Text.UTF8Encoding]::new($false, $true).GetString($bytes, $skip, $bytes.Length - $skip)
    }
}

# Set the top-level "defaultProfile" of a file read by Read-TerminalSettings to
# $Guid, changing only that value's text: Terminal rewrites the rest itself.
#
# Terminal saves by writing settings.json.tmp and renaming it over settings.json,
# so a plain "check the hash, then rename ours over it" could still overwrite a
# save that lands between the two. Instead:
#   1. back up the bytes that were read; write the new bytes to a temp file beside
#      the original and read them back;
#   2. open the original locked (see DotfilesTweaks.FileOps): from here on nothing
#      else can write it or rename over it. If something has it open for writing,
#      this fails and nothing changes;
#   3. through that handle, check it still hashes as read (else throw: re-run);
#   4. through that handle, rename the original aside to *.dotfiles-<pid>.old,
#      then rename the temp file into place without replacing anything. If a new
#      settings.json appeared in that instant, it is left alone and the original
#      is put back if it can be (else the error names where it is);
#   5. close the handle and delete the .old file (the backup holds the same bytes).
function Write-TerminalDefaultProfile($Settings, [string]$Guid, [string]$BackupFile) {
    $loc = Find-TopLevelJsonString $Settings.Text 'defaultProfile'
    if (-not $loc) { throw 'no top-level "defaultProfile" in settings.json; set it once in Terminal > Settings > Startup' }
    [IO.File]::WriteAllBytes($BackupFile, $Settings.Bytes)
    $text = $Settings.Text.Remove($loc.Start, $loc.Length).Insert($loc.Start, $Guid)
    if ((Find-TopLevelJsonString $text 'defaultProfile').Value -cne $Guid) { throw 'the edited text does not read back with the new defaultProfile' }
    $enc = [Text.UTF8Encoding]::new($Settings.Bom)
    [byte[]]$bytes = @($enc.GetPreamble()) + @($enc.GetBytes($text))
    $path = $Settings.Path
    $base = Join-Path (Split-Path -Parent $path) ".$(Split-Path -Leaf $path).dotfiles-$PID"
    $tmp = "$base.tmp"
    $old = "$base.old"
    $handle = $null
    $replaced = $false
    try {
        [IO.File]::WriteAllBytes($tmp, $bytes)
        if ((Get-BytesHash ([IO.File]::ReadAllBytes($tmp))) -ne (Get-BytesHash $bytes)) { throw "temp file $tmp did not read back as written" }
        try { $handle = [DotfilesTweaks.FileOps]::OpenLocked($path) }
        catch { throw "could not lock $path ($($_.Exception.GetBaseException().Message)); another program may be writing it. Nothing was changed; re-run" }
        $stream = [IO.FileStream]::new($handle, [IO.FileAccess]::Read)
        $current = [IO.MemoryStream]::new()
        $stream.CopyTo($current)
        if ((Get-BytesHash $current.ToArray()) -ne $Settings.Hash) {
            throw "$path changed after it was read (Terminal may have saved it). Nothing was changed; re-run"
        }
        [DotfilesTweaks.FileOps]::RenameByHandle($handle, $old)
        try {
            [IO.File]::Move($tmp, $path, $false)
        } catch {
            $why = $_.Exception.Message
            try { [DotfilesTweaks.FileOps]::RenameByHandle($handle, $path) }
            catch { throw "could not put the new settings.json in place ($why), and a settings.json that appeared meanwhile was kept; the file that was read is at $old" }
            throw "could not put the new settings.json in place ($why). The original was put back; re-run"
        }
        $replaced = $true
    } finally {
        if ($handle) { $handle.Dispose() }
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        if ($replaced -and (Test-Path -LiteralPath $old)) { Remove-Item -LiteralPath $old -Force }
    }
}

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
        Label  = 'Game Mode on'
        # Windows defaults Game Mode on, but AutoGameModeEnabled doesn't exist until
        # something writes it (the Settings toggle, or this script). So a PC that was
        # never toggled reads "would set" here, and the first real run writes the 1
        # that Windows was already assuming.
        Why    = 'Windows prioritizes the game in the foreground; on by default, but the value is absent until written.'
        Registry = @( RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 'DWord' 1 )   # 1 on, 0 off
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
        # Correct values don't prove the service uses them (this PC had them and had
        # never synced), so also check the source the running service reports. It
        # reads "Local CMOS Clock" until the first poll after boot, so a run just
        # after boot may resync; that is harmless.
        Live   = {
            $src = (w32tm /query /source 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { $src = '<unavailable>' }
            "source=$src"
        }
        LiveWant = 'source=time.windows.com,0x9'
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
        # defaultProfile, so only that one value is edited in place.
        Get   = {
            $p = Get-TerminalSettingsPath
            if (-not $p) { return '<settings.json not found>' }
            $loc = Find-TopLevelJsonString (Read-TerminalSettings $p).Text 'defaultProfile'
            if ($loc) { $loc.Value } else { '<no top-level defaultProfile>' }
        }
        Want  = $Pwsh7ProfileGuid
        Set   = {
            $p = Get-TerminalSettingsPath
            if (-not $p) { throw 'Windows Terminal settings.json not found: launch Terminal once, then re-run' }
            # Edit a symlinked settings.json at its target, so the rename below
            # replaces the real file and leaves the link in place.
            $item = Get-Item -LiteralPath $p -Force
            if ($item.LinkTarget) { $p = $item.ResolveLinkTarget($true).FullName }
            Write-TerminalDefaultProfile (Read-TerminalSettings $p) $Pwsh7ProfileGuid (Join-Path (Get-BackupDir) 'windows-terminal-settings.json')
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

# Dot-sourcing (`. windows/tweaks.ps1`) defines the functions and $Tweaks for tests
# and stops here, before anything is read or changed.
if ($MyInvocation.InvocationName -eq '.') { return }

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
