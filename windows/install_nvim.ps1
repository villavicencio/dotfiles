#Requires -Version 7
<#
.SYNOPSIS
    Windows counterpart of helpers/install_nvim.sh: restore the nvim plugin set
    pinned in nvim/lazy-lock.json, headlessly, and verify every pin.

.DESCRIPTION
    install.ps1 runs this after it links %LOCALAPPDATA%\nvim -> nvim/. It is also
    runnable on its own:  pwsh -File windows/install_nvim.ps1 [-DryRun]

    Same sequence as the POSIX helper (read that file's comments for the why):
      1. snapshot the lockfile
      2. `nvim --headless +qa` - lazy.nvim bootstraps itself and installs the
         missing plugins. On a fresh machine this DRIFTS pins and rewrites the
         lockfile through the link (plugins imported from NvChad lose their lock
         entry between install rounds), so:
      3. put the snapshot back, then `Lazy! restore` to the pinned commits
      4. put the snapshot back again, and verify with helpers/nvim_verify_lock.lua
    An nvim older than 0.12 is upgraded with winget first (install.ps1 imports with
    --no-upgrade); if it is still too old, that is a failure.
    Exit code: 0 ok (or skipped because nvim is missing), 1 nvim too old, snapshot or
    restore failure, or incomplete bootstrap.
#>
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot
$MinNvim = [version]'0.12'   # the pinned nvim-treesitter (main) requires 0.12

if ($DryRun) {
    Write-Host '[dry-run] would bootstrap nvim plugins: nvim --headless "+Lazy! restore" +qa' -ForegroundColor Yellow
    exit 0
}
if (-not (Get-Command nvim -ErrorAction SilentlyContinue)) {
    Write-Warning 'nvim not on PATH - skipping the plugin bootstrap. Install Neovim.Neovim (winget) and re-run.'
    exit 0
}
function Get-NvimVersionLine { (& nvim --version | Select-Object -First 1) }
function Test-NvimNewEnough([string]$line) {
    $line -match 'v(\d+)\.(\d+)' -and [version]"$($Matches[1]).$($Matches[2])" -ge $MinNvim
}
# An installed-but-too-old nvim is a failure, not a skip: install.ps1 imports with
# --no-upgrade, so a machine that already had 0.11 keeps it. Upgrade it and re-check;
# exit 1 (recorded by install.ps1) if that still does not reach the minimum.
$verLine = Get-NvimVersionLine
if (-not (Test-NvimNewEnough $verLine)) {
    Write-Host "Neovim is too old for this config ('$verLine'); running winget upgrade --id Neovim.Neovim -e..."
    winget upgrade --id Neovim.Neovim -e --accept-package-agreements --accept-source-agreements
    # The MSI keeps its install dir, but pick up any PATH change it made anyway.
    $env:Path = (@($env:Path) + [Environment]::GetEnvironmentVariable('Path', 'Machine') +
        [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';'
    $verLine = Get-NvimVersionLine
    if (-not (Test-NvimNewEnough $verLine)) {
        Write-Warning "this config needs Neovim $MinNvim+, found '$verLine' at $((Get-Command nvim).Source)."
        exit 1
    }
}

# Ask nvim where its config lives (%LOCALAPPDATA%\nvim unless XDG_CONFIG_HOME is set)
# rather than hardcoding it. --clean: don't load the config (and its installer) for this.
$configDir = (& nvim --clean --headless --cmd "lua io.write(vim.fn.stdpath('config'))" +qa) -join ''
$lock = Join-Path $configDir 'lazy-lock.json'
if (-not (Test-Path -LiteralPath $lock)) {
    Write-Warning "no lockfile at $lock - is $configDir linked to nvim/? (run install.ps1 first)"
    exit 1
}

function Test-SameBytes([string]$a, [string]$b) {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($a)) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($b))
}
function Restore-Pins {
    # Byte-compare so a clean run never touches the tracked file; after a write,
    # prove it landed rather than trusting the copy.
    if (Test-SameBytes $lock $pinned) { return }
    Copy-Item -LiteralPath $pinned $lock -Force
    if (-not (Test-SameBytes $lock $pinned)) { throw "could not restore the pinned $lock (it is left drifted)" }
    Write-Host '    restored the pinned lazy-lock.json (the bootstrap install had rewritten it)'
}

$pinned = $null; $diag = $null
try {
    $pinned = New-TemporaryFile
    $diag = New-TemporaryFile
    # The snapshot is the only copy of the pins once nvim starts: prove it complete
    # (non-empty, byte-equal) before launching nvim. Restore-Pins only ever writes from it.
    Copy-Item -LiteralPath $lock $pinned -Force
    if ((Get-Item $pinned).Length -eq 0 -or -not (Test-SameBytes $lock $pinned)) {
        throw "could not snapshot $lock - not starting nvim"
    }

    Write-Host 'Bootstrapping nvim plugins (Lazy restore from pinned lazy-lock.json)...'
    # Output is ~all git progress; the restore pass keeps stderr for diagnostics.
    & nvim --headless +qa *> $null
    Restore-Pins
    & nvim --headless '+Lazy! restore' +qa 2> $diag > $null
    Restore-Pins

    & nvim -l (Join-Path $Repo 'helpers/nvim_verify_lock.lua') $pinned.FullName
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'nvim: all pinned plugins present at their locked commits; bootstrap complete.'
        exit 0
    }
    Write-Warning 'nvim plugin bootstrap INCOMPLETE (see above).'
    if ((Get-Item $diag).Length) {
        Write-Host '  --- last restore stderr ---'
        Get-Content $diag | ForEach-Object { "  $_" }
    }
    Write-Host '  Open nvim (it finishes installing on launch), then run :Lazy restore + :checkhealth.'
    exit 1
} catch {
    Write-Warning "nvim plugin bootstrap failed: $($_.Exception.Message)"
    exit 1
} finally {
    foreach ($t in @($pinned, $diag)) { if ($t) { Remove-Item $t -Force -ErrorAction SilentlyContinue } }
}
