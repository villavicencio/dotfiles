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
    Exit code: 0 ok (or skipped because nvim is missing), 1 incomplete bootstrap.
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
$verLine = (& nvim --version | Select-Object -First 1)
if ($verLine -notmatch 'v(\d+)\.(\d+)' -or [version]"$($Matches[1]).$($Matches[2])" -lt $MinNvim) {
    Write-Warning "this config needs Neovim $MinNvim+, found '$verLine' - skipping the plugin bootstrap."
    exit 0
}

# Ask nvim where its config lives (%LOCALAPPDATA%\nvim unless XDG_CONFIG_HOME is set)
# rather than hardcoding it. --clean: don't load the config (and its installer) for this.
$configDir = (& nvim --clean --headless --cmd "lua io.write(vim.fn.stdpath('config'))" +qa) -join ''
$lock = Join-Path $configDir 'lazy-lock.json'
if (-not (Test-Path -LiteralPath $lock)) {
    Write-Warning "no lockfile at $lock - is $configDir linked to nvim/? (run install.ps1 first)"
    exit 1
}

$pinned = New-TemporaryFile
$diag = New-TemporaryFile
Copy-Item -LiteralPath $lock $pinned -Force
function Restore-Pins {
    # Byte-compare so a clean run never touches the tracked file.
    $a = [IO.File]::ReadAllBytes($lock); $b = [IO.File]::ReadAllBytes($pinned)
    if ([Convert]::ToBase64String($a) -ne [Convert]::ToBase64String($b)) {
        Copy-Item -LiteralPath $pinned $lock -Force
        Write-Host '    restored the pinned lazy-lock.json (the bootstrap install had rewritten it)'
    }
}

try {
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
} finally {
    Remove-Item $pinned, $diag -Force -ErrorAction SilentlyContinue
}
