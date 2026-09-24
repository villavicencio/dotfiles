# PowerShell 7 profile — the Windows counterpart of zsh/zshrc + zsh/alias.sh.
# Loaded by a one-line stub at $PROFILE that dot-sources this file (written by install.ps1).
# A stub rather than a symlink: $PROFILE lives under Documents, which OneDrive may sync,
# and OneDrive handles symlinks badly.

# --- Line editing: zsh-like behaviour ---------------------------------------
# Skipped when output is redirected (scripts, Claude Code's shell tool): PSReadLine's
# prediction option throws "console output doesn't support virtual terminal processing".
if ((Get-Module -ListAvailable PSReadLine) -and -not [Console]::IsOutputRedirected) {
    Set-PSReadLineOption -EditMode Emacs                   # Ctrl+A / Ctrl+E / Ctrl+K etc. like zsh
    Set-PSReadLineOption -PredictionSource History         # grey inline suggestions, like zsh-autosuggestions
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward    # type a prefix, then Up
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar           # accepts the inline suggestion at end of line
}

# --- Prompt & navigation ----------------------------------------------------
# Starship reads ~/.config/starship.toml, linked from starship/starship.toml (shared with macOS).
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell --print-full-init | Out-String)
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })          # `z <dir>` to jump
}

# --- Aliases ported from zsh/alias.sh ---------------------------------------
# PowerShell aliases cannot take arguments, so these are functions. Built-in aliases
# outrank functions, so `ls` has to be removed before the eza version can take effect.
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls  { eza --group-directories-first @args }
    function l   { eza -lh --git --group-directories-first @args }        # long, human sizes, git
    function ll  { eza -lh --git --group-directories-first @args }
    function la  { eza -lah --git --group-directories-first @args }       # + dotfiles
    function lsd { eza -lhD --git @args }                                 # dirs only
    function lt  { eza --tree --level=2 --git @args }                     # 2-level tree
} else {
    function ll { Get-ChildItem -Force @args }
}
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Set-Alias vim nvim
    Set-Alias vi nvim
}
function update { topgrade @args }
function reload { . $PROFILE }                                          # re-read this profile
function week { Get-Date -UFormat %V }
function localip {
    Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual -ErrorAction SilentlyContinue |
        Where-Object InterfaceAlias -notmatch 'Loopback|vEthernet' | Select-Object -ExpandProperty IPAddress
}
function c { ($input | Out-String) -replace "`r?`n", '' | Set-Clipboard }   # trim newlines, copy (pbcopy)
function mkd($path) { New-Item -ItemType Directory -Force $path | Out-Null; Set-Location $path }   # mkdir_and_cd
function fs {                                                               # size_of_file_or_directory
    $targets = if ($args) { $args } else { Get-ChildItem -Force | Select-Object -ExpandProperty Name }
    foreach ($t in $targets) {
        $bytes = (Get-ChildItem -LiteralPath $t -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        '{0,10:N1} MB  {1}' -f ($bytes / 1MB), $t
    }
}

# --- Mac muscle-memory helpers ----------------------------------------------
function which($name) { Get-Command $name -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source }
function open($path = '.') { Invoke-Item $path }                            # like macOS `open`
function touch($file) { if (Test-Path $file) { (Get-Item $file).LastWriteTime = Get-Date } else { New-Item -ItemType File $file | Out-Null } }
function dotfiles { Set-Location (Split-Path (Split-Path $PSScriptRoot)) }  # cd to the repo root

# --- Machine-local overrides (untracked) — the counterpart of ~/env.sh ------
$localProfile = Join-Path $HOME 'env.ps1'
if (Test-Path $localProfile) { . $localProfile }
