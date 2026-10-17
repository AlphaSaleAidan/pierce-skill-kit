# ssh-setup.ps1 - run once ON YOUR WINDOWS PC. Afterwards `ssh box` logs in to your server with no password,
# `lead` opens the lead there, and `tab <name>` opens one project tab.
#   .\ssh-setup.ps1 me@my-server [-Port 22] [-Name box] [-NoShortcuts]
# Without downloading the kit first (PowerShell):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/AlphaSaleAidan/pierce-skill-kit/main/bin/windows/ssh-setup.ps1))) me@my-server
# Safe to run again: it keeps your key, adds it to the server once, and rewrites only its own lines.
param([Parameter(Mandatory = $true)][string]$Dest, [int]$Port = 22, [string]$Name = 'box', [switch]$NoShortcuts)
$ErrorActionPreference = 'Stop'
if ($Dest -notmatch '^[^@\s]+@[^@\s]+$') { throw "usage: ssh-setup.ps1 me@my-server [-Port 22] [-Name box]" }
if ($Name -notmatch '^[A-Za-z0-9._-]+$') { throw "-Name takes letters, digits, dot, dash" }
$user, $hostName = $Dest -split '@', 2
$dir = Join-Path $HOME '.ssh'; $key = Join-Path $dir 'id_ed25519'; $cfg = Join-Path $dir 'config'
New-Item -ItemType Directory -Force $dir | Out-Null
if (-not (Test-Path $cfg)) { New-Item -ItemType File $cfg | Out-Null }

# 1. a key on this PC (kept if you already have one)
if (Test-Path $key) { "1/4 key: using your existing $key" }
else {
  # an empty passphrase: Windows PowerShell 5.1 drops a bare '' argument, PowerShell 7.3+ passes it as is
  $empty = if ($PSVersionTable.PSVersion -ge [version]'7.3') { '' } else { '""' }
  ssh-keygen -q -t ed25519 -N $empty -C "$env:USERNAME@$env:COMPUTERNAME pierce-skill-kit" -f $key; "1/4 key: made $key" }
if (-not (Test-Path $key)) { throw "ssh-keygen did not make $key" }

# 2. the short name: a "Host <name>" block in ~/.ssh/config, between our own markers
$begin = "# BEGIN pierce-skill-kit $Name"; $end = "# END pierce-skill-kit $Name"
$lines = @(Get-Content $cfg)
$ours = $lines -contains $begin
if (-not $ours -and ($lines | Where-Object { $_ -match "^\s*Host\s+(.*\s)?$([regex]::Escape($Name))(\s|$)" })) {
  throw "~/.ssh/config already has a 'Host $Name' you wrote; pick another name with -Name" }
$keep = @(); $skip = $false
foreach ($l in $lines) { if ($l -eq $begin) { $skip = $true }; if (-not $skip) { $keep += $l }; if ($l -eq $end) { $skip = $false } }
$keyPath = $key -replace '\\', '/'
$keep += @($begin, "Host $Name", "  HostName $hostName", "  User $user", "  Port $Port", "  IdentityFile $keyPath",
  '  IdentitiesOnly yes', "  # keeps an idle connection open, so a quiet session isn't dropped",
  '  ServerAliveInterval 30', '  ServerAliveCountMax 6', $end)
[IO.File]::WriteAllLines($cfg, [string[]]$keep)   # no BOM: ssh can't read a config that starts with one
"2/4 name: 'ssh $Name' now means $Dest (port $Port)"

# 3. put the key on the server once (asks for the server password this one time)
function Test-Login { ssh -o BatchMode=yes -o ConnectTimeout=10 $Name true 2>$null; return $LASTEXITCODE -eq 0 }
if (Test-Login) { "3/4 server: already trusts this key" }
else {
  "3/4 server: type your server password (the last time you'll need it)"
  Get-Content "$key.pub" | ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password,keyboard-interactive $Name 'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; k=$(cat | tr -d "\r"); grep -qxF "$k" ~/.ssh/authorized_keys || echo "$k" >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys'
}
if (-not (Test-Login)) { throw "the server still asks for a password. Check: ssh -v $Name" }
"4/4 check: 'ssh $Name' logs in with no password"

# shortcuts: lead + tab in your PowerShell profile
if (-not $NoShortcuts) {
  $p = $PROFILE.CurrentUserAllHosts
  New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
  $old = if (Test-Path $p) { @(Get-Content $p | Where-Object { $_ -notmatch '# pierce-skill-kit ssh-setup$' }) } else { @() }
  $new = $old + @(
    "function lead { ssh -t $Name '~/.local/bin/lead' }   # pierce-skill-kit ssh-setup",
    "function tab { param([string]`$t) ssh -t $Name `"~/.local/bin/tab-view hub:`$t`" }   # pierce-skill-kit ssh-setup")
  Set-Content -Path $p -Value $new
  "shortcuts: 'lead' and 'tab <name>' added to $p (open a new terminal)"
}
"Done."
