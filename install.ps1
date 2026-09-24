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
      4. pre-commit + the gitleaks hook for this repo

    Idempotent: re-running changes nothing that is already in place. A real file
    found where a link belongs is moved aside to <name>.pre-dotfiles, never deleted.
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

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Would($msg) { Write-Host "[dry-run] would $msg" -ForegroundColor Yellow }

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
        Remove-Item -LiteralPath $Target -Force                       # stale/other link: relink
    } elseif ($item) {
        Move-Item -LiteralPath $Target "$Target.pre-dotfiles" -Force  # real file: keep a backup
        Write-Host "    backup  $Target.pre-dotfiles"
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
    if (Test-Path $Target) {
        Move-Item -LiteralPath $Target "$Target.pre-dotfiles" -Force
        Write-Host "    backup  $Target.pre-dotfiles"
    }
    [IO.File]::WriteAllText($Target, $Content, [Text.UTF8Encoding]::new($false))
    Write-Host "    wrote   $Target"
}

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
    # Upgrades are topgrade's job (`update`).
    winget import --import-file (Join-Path $Repo 'windows/packages.json') `
        --accept-package-agreements --accept-source-agreements --ignore-unavailable --no-upgrade
    # winget exits non-zero when anything was already installed; not a failure here.
}

# 2. Links ------------------------------------------------------------------
Write-Step 'links'
$links = [ordered]@{
    "$HOME/.config/git/gitignore"     = 'git/gitignore'
    "$HOME/.config/git/gitattributes" = 'git/gitattributes'
    "$HOME/.config/starship.toml"     = 'starship/starship.toml'
    "$env:APPDATA/lazygit/config.yml" = 'lazygit/config.yml'
    "$HOME/.claude/CLAUDE.md"         = 'claude/CLAUDE.md'
    "$env:LOCALAPPDATA/Microsoft/Windows Terminal/Fragments/dotfiles/dotfiles.json" = 'windows/terminal/dotfiles.json'
}
foreach ($t in $links.Keys) { Set-DotLink ([IO.Path]::GetFullPath($t)) $links[$t] }

# 3. Stubs ------------------------------------------------------------------
Write-Step 'stubs'
$repoFwd = $Repo -replace '\\', '/'
Set-Stub "$HOME/.gitconfig" @"
# Written by install.ps1 — edit the tracked files, not this stub.
[include]
    path = $repoFwd/git/gitconfig
[include]
    path = $repoFwd/windows/gitconfig

"@
# PowerShell 7's $PROFILE (Documents may be redirected into OneDrive; resolve it rather than guess).
$pwshProfile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell/Microsoft.PowerShell_profile.ps1'
Set-Stub $pwshProfile ". `"$Repo\windows\powershell\profile.ps1`"`n"

# 4. pre-commit + gitleaks hook -----------------------------------------------
Write-Step 'pre-commit + gitleaks hook'
if ($DryRun) {
    Write-Would 'install pre-commit (uv tool) if missing, then run: pre-commit install'
} else {
    if (-not (Get-Command gitleaks -ErrorAction SilentlyContinue)) {
        Write-Warning 'gitleaks not on PATH (installed by winget above; open a new shell and re-run)'
    }
    if (-not (Get-Command pre-commit -ErrorAction SilentlyContinue)) {
        uv tool install pre-commit
        $env:Path = "$HOME\.local\bin;$env:Path"
    }
    Push-Location $Repo
    try { pre-commit install } finally { Pop-Location }
}

Write-Step ($DryRun ? 'Dry run complete — nothing was changed.' : 'Installation complete!')
