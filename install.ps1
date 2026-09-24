#Requires -Version 7
<#
.SYNOPSIS
    Windows counterpart of ./install. Sets up a Windows machine from this repo.

.DESCRIPTION
    Dotbot is not used on Windows: its shell directives assume a POSIX shell, and
    the glue layer stays in the platform's native shell (see
    docs/solutions/best-practices/keep-dotfiles-glue-layer-in-shell-not-rust-lua-2026-05-30.md).
    Instead this script runs the Windows layer directly:

      1. winget packages from windows/packages.json   (the Brewfile counterpart)
      2. symlinks for configs shared with macOS, plus the Windows Terminal fragment
      3. stubs for files that must chain or be OneDrive-safe (~/.gitconfig, $PROFILE)
      4. ~/.claude/settings.json seeded from windows/claude-settings.json, only if absent
      5. pre-commit + the gitleaks hook for this repo
      6. the nvim plugin set pinned in nvim/lazy-lock.json (windows/install_nvim.ps1)

    Idempotent: re-running changes nothing that is already in place. A real file
    found where a link belongs is moved aside to <name>.pre-dotfiles (timestamped
    if that name is taken), never deleted. A failing step does not stop the later
    ones; the script exits 1 and lists what failed.
    Symlinks need Developer Mode (Settings > System > For developers) or an
    elevated shell.

.EXAMPLE
    pwsh -File install.ps1 -DryRun      # preview; mutates nothing
    pwsh -File install.ps1              # apply
    pwsh -File install.ps1 -SkipPackages
#>
param(
    [switch]$DryRun,
    [switch]$SkipPackages
)
$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot
$Failures = [System.Collections.Generic.List[string]]::new()

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Would($msg) { Write-Host "[dry-run] would $msg" -ForegroundColor Yellow }

# Native commands don't throw on a non-zero exit, even with $ErrorActionPreference
# = 'Stop'. Record the failure and keep going, so one bad package doesn't block the
# config links.
function Test-NativeExit([string]$what) {
    if ($LASTEXITCODE -ne 0) {
        $Failures.Add("$what (exit $LASTEXITCODE)")
        Write-Warning "$what failed with exit code $LASTEXITCODE"
        return $false
    }
    return $true
}

# Run a PowerShell-level step (link, stub); on error record it and continue, so
# one bad link can't abort the rest of the install or the failure summary.
function Invoke-Step([string]$what, [scriptblock]$action) {
    try { & $action }
    catch {
        $Failures.Add("${what}: $($_.Exception.Message)")
        Write-Warning "$what failed: $($_.Exception.Message)"
    }
}

# winget adds to the user PATH in the registry, which this already-running process
# never sees. Append the registry entries this process lacks, keeping the existing
# (possibly process-only) entries and their order, so tools installed a moment ago
# resolve without losing anything the caller had on PATH.
function Update-SessionPath {
    $entries = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $candidates = @($env:Path -split ';') + "$HOME\.local\bin" +
        ([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';') +
        ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';')
    foreach ($p in $candidates) {
        # Trailing '\' is ignored only for the duplicate check; entries are kept as written.
        if ($p -and $seen.Add($p.TrimEnd('\'))) { $entries.Add($p) }
    }
    $env:Path = $entries -join ';'
}

# Move a real file out of the way without ever overwriting an earlier backup.
function Backup-File([string]$Target) {
    $backup = "$Target.pre-dotfiles"
    if (Test-Path -LiteralPath $backup) { $backup = "$backup.$(Get-Date -Format yyyyMMdd-HHmmss)" }
    Move-Item -LiteralPath $Target $backup
    Write-Host "    backup  $backup"
}

# Link $Target -> $Repo/$Source, dotbot `relink: true` style.
function Set-DotLink([string]$Target, [string]$Source) {
    # GetFullPath normalizes to backslashes; a symlink target with mixed separators
    # is not reliably resolvable on Windows.
    $src = [IO.Path]::GetFullPath((Join-Path $Repo $Source))
    if (-not (Test-Path $src)) { throw "link source missing: $Source" }
    $item = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'SymbolicLink' -and $item.Target -eq $src) {
        Write-Host "    ok      $Target"; return
    }
    if ($DryRun) { Write-Would "link $Target -> $Source"; return }
    New-Item -ItemType Directory -Force (Split-Path $Target) | Out-Null
    if ($item -and $item.LinkType) {
        Remove-Item -LiteralPath $Target -Force   # stale/other link: relink
    } elseif ($item) {
        Backup-File $Target                       # real file: keep it
    }
    New-Item -ItemType SymbolicLink -Path $Target -Target $src | Out-Null
    Write-Host "    linked  $Target -> $Source"
}

# Write $Content to $Target unless it already matches; back up a differing file first.
function Set-Stub([string]$Target, [string]$Content) {
    if ((Test-Path $Target) -and ((Get-Content -Raw $Target) -eq $Content)) {
        Write-Host "    ok      $Target"; return
    }
    if ($DryRun) { Write-Would "write stub $Target"; return }
    New-Item -ItemType Directory -Force (Split-Path $Target) | Out-Null
    if (Test-Path $Target) { Backup-File $Target }
    [IO.File]::WriteAllText($Target, $Content, [Text.UTF8Encoding]::new($false))
    Write-Host "    wrote   $Target"
}

# Also refresh once up front: a shell started before the tools were installed (an
# old terminal, a Claude Code session) otherwise reports them missing under
# -SkipPackages, where the post-winget refresh never runs. Merging is harmless.
Update-SessionPath

# 1. Packages ---------------------------------------------------------------
Write-Step 'winget packages (windows/packages.json)'
if ($SkipPackages) {
    Write-Host '    skipped (-SkipPackages)'
} elseif ($DryRun) {
    Write-Would 'run: winget import windows/packages.json'
} else {
    # --no-upgrade: install what is missing, never upgrade what is present. Without it,
    # `winget import` upgrades every outdated package in the list, including apps that
    # are running (Logi Options+ failed mid-upgrade with exit 1008 on the first run).
    # Upgrades are topgrade's job (`update`). Exits 0 when everything is already there.
    winget import --import-file (Join-Path $Repo 'windows/packages.json') `
        --accept-package-agreements --accept-source-agreements --ignore-unavailable --no-upgrade
    $null = Test-NativeExit 'winget import'
    Update-SessionPath
}

# 2. Links ------------------------------------------------------------------
Write-Step 'links'
$links = [ordered]@{
    "$HOME/.config/git/gitignore"     = 'git/gitignore'
    "$HOME/.config/git/gitattributes" = 'git/gitattributes'
    "$HOME/.config/starship.toml"     = 'starship/starship.toml'
    "$env:APPDATA/lazygit/config.yml" = 'lazygit/config.yml'
    "$HOME/.claude/CLAUDE.md"         = 'claude/CLAUDE.md'
    # Runs under Git Bash's sh (the seeded statusLine invokes it); needs jq from packages.json.
    "$HOME/.claude/statusline-command.sh" = 'claude/statusline-command.sh'
    "$env:LOCALAPPDATA/Microsoft/Windows Terminal/Fragments/dotfiles/dotfiles.json" = 'windows/terminal/dotfiles.json'
    # Whole-directory link, like ~/.config/nvim on macOS/Linux: Windows nvim reads its
    # config from %LOCALAPPDATA%\nvim (plugins/data go to %LOCALAPPDATA%\nvim-data).
    "$env:LOCALAPPDATA/nvim"          = 'nvim'
}
foreach ($t in $links.Keys) {
    Invoke-Step "link $($links[$t])" { Set-DotLink ([IO.Path]::GetFullPath($t)) $links[$t] }
}

# 3. Stubs ------------------------------------------------------------------
Write-Step 'stubs'
$repoFwd = $Repo -replace '\\', '/'
# autocrlf lives HERE, not in windows/gitconfig: that file is inside the worktree,
# so checking out any commit without it (everything before the Windows layer)
# silently drops the include, and git falls back to Git for Windows' system
# autocrlf=true for the rest of that checkout - rewriting every file it touches
# with CRLF, including windows/gitconfig itself. This stub is outside the repo.
# Joined with "`n" rather than a here-string, whose line endings would follow
# this script's own and make the stub differ between LF and CRLF checkouts.
$gitStub = @(
    '# Written by install.ps1 - edit the tracked files, not this stub.'
    '[include]'
    "    path = $repoFwd/git/gitconfig"
    '[include]'
    "    path = $repoFwd/windows/gitconfig"
    '[core]'
    '    autocrlf = input'
    ''
) -join "`n"
Invoke-Step 'stub ~/.gitconfig' { Set-Stub "$HOME/.gitconfig" $gitStub }
# PowerShell 7's $PROFILE (Documents may be redirected into OneDrive; resolve it rather than guess).
$pwshProfile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell/Microsoft.PowerShell_profile.ps1'
Invoke-Step 'stub $PROFILE' { Set-Stub $pwshProfile ". `"$Repo\windows\powershell\profile.ps1`"`n" }

# 4. Claude Code settings (seed only) ------------------------------------------
Write-Step 'Claude Code settings (seed if absent)'
# COPIED, never linked, and only when absent: Claude Code rewrites this file in
# place, so a link would be orphaned on its first write, and an existing file is
# the user's live config. Same contract as helpers/install_claude_settings.sh.
# The source is the Windows sibling, not claude/settings.json, whose hooks are
# tmux/herdr bash scripts that would error on every event here.
Invoke-Step 'seed ~/.claude/settings.json' {
    $src = Join-Path $Repo 'windows/claude-settings.json'
    $dest = [IO.Path]::GetFullPath("$HOME/.claude/settings.json")
    if (-not (Test-Path -LiteralPath $src)) { throw 'seed source missing: windows/claude-settings.json' }
    # Get-Item -Force also catches a dangling link, which Test-Path reports as absent.
    $existing = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    if ($existing) {
        # A directory (or a link to one) is not a settings file: fail, don't report ok.
        if ($existing.PSIsContainer -or (Test-Path -LiteralPath $dest -PathType Container)) {
            throw "$dest exists but is not a file"
        }
        Write-Host "    ok      $dest (present, left alone)"; return
    }
    if ($DryRun) { Write-Would "seed $dest from windows/claude-settings.json"; return }
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    # Write a temp file beside the destination and verify it, THEN publish it
    # with File.Move(overwrite: false), a same-volume rename that fails if
    # settings.json appeared since the check above (Claude Code starting up,
    # say). A live file is never overwritten, and a failed write never leaves a
    # partial settings.json that later runs would mistake for a live config.
    $tmp = "$dest.seed.$PID"
    try {
        Copy-Item -LiteralPath $src -Destination $tmp -Force
        if ((Get-FileHash -LiteralPath $tmp).Hash -ne (Get-FileHash -LiteralPath $src).Hash) {
            throw "seed copy did not verify: $tmp"
        }
        try {
            [IO.File]::Move($tmp, $dest, $false)
        } catch [System.IO.IOException] {
            if (Test-Path -LiteralPath $dest) {
                Write-Host "    ok      $dest (appeared meanwhile, left alone)"; return
            }
            throw
        }
        Write-Host "    seeded  $dest"
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }  # a failure throws, so Invoke-Step records it
    }
}

# 5. pre-commit + gitleaks hook -----------------------------------------------
Write-Step 'pre-commit + gitleaks hook'
if ($DryRun) {
    Write-Would 'install pre-commit (uv tool) if missing, then run: pre-commit install'
} else {
    if (-not (Get-Command gitleaks -ErrorAction SilentlyContinue)) {
        $Failures.Add('gitleaks not on PATH (the hook would block every commit)')
        Write-Warning 'gitleaks not on PATH; the pre-commit hook will refuse commits until it is'
    }
    $hasPreCommit = [bool](Get-Command pre-commit -ErrorAction SilentlyContinue)
    if (-not $hasPreCommit) {
        if (Get-Command uv -ErrorAction SilentlyContinue) {
            uv tool install pre-commit
            $hasPreCommit = Test-NativeExit 'uv tool install pre-commit'
            Update-SessionPath
        } else {
            $Failures.Add('uv not found, so pre-commit could not be installed')
        }
    }
    if ($hasPreCommit) {
        Push-Location $Repo
        try { pre-commit install; $null = Test-NativeExit 'pre-commit install' } finally { Pop-Location }
    }
}

# 6. nvim plugins ---------------------------------------------------------------
Write-Step 'nvim plugins (nvim/lazy-lock.json)'
Invoke-Step 'nvim plugin bootstrap' {
    # Upgrades a too-old nvim; exit 1 = nvim missing or still too old, or a pin didn't
    # restore. Under -SkipPackages a missing nvim is a skip and an old one fails
    # without running winget.
    & (Join-Path $Repo 'windows/install_nvim.ps1') -DryRun:$DryRun -AllowMissing:$SkipPackages -NoUpgrade:$SkipPackages
    $null = Test-NativeExit 'nvim plugin bootstrap'
}

if ($Failures.Count) {
    Write-Host "`nCompleted with $($Failures.Count) failure(s)$(if ($DryRun) { ' (dry run - nothing was changed)' }):" -ForegroundColor Red
    $Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
} elseif ($DryRun) {
    Write-Step 'Dry run complete - nothing was changed.'
} else {
    Write-Step 'Installation complete!'
}
