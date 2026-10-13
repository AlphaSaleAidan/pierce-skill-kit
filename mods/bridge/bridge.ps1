# bridge.ps1 - Windows side of the Pierce Skill Kit bridge: talk to the lead on your server over SSH only.
# Needs Windows PowerShell 5.1 or PowerShell 7, and the built-in OpenSSH client (ssh, ssh-keygen) and tar.exe.
#   .\bridge.ps1 setup me@my-server [-Name N] [-Harden]   one-time setup
#   bridge send "<text>"          type a message into the server's lead window (no text: read stdin)
#   bridge inbox [--all]          show new replies from the lead, then mark them read
#   bridge sync [--watch [N]]     mirror the shared context folder both ways (--watch: every N s, default 60)
#   bridge share <path>           write one file (content on stdin) into the context folder, then sync
#   bridge pull [path]            sync, then list the context folder (or print one file)
#   bridge files                  list what sync would send, after the deny-list and size caps
$ErrorActionPreference = 'Stop'
try { [Console]::InputEncoding = [Text.UTF8Encoding]::new($false); [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
$MaxFile = 1048576; $MaxTotal = 52428800; $MaxEntries = 5000
$Dir = if ($env:BRIDGE_DIR) { $env:BRIDGE_DIR } else { Join-Path $HOME 'pierce-bridge' }
$Utf8 = New-Object Text.UTF8Encoding $false
# Same deny-list as the sh side; matched against every part of the path, lower-cased.
# Names only: file contents are not checked.
$DenyParts = @('..', '.env*', '*.pem', '*.key', 'id_*', '*secret*', '*.p12', '*.pfx', '.ssh', '*credential*', '*token*', '.git',
  '.netrc', '.npmrc', '.pypirc', '.pgpass', '.aws', '.docker', 'kubeconfig*', '*.kdbx', '*.ppk', '*.gpg', '*.asc', '.htpasswd')

function Fail([string]$m) { [Console]::Error.WriteLine("bridge: $m"); exit 1 }

function Test-Denied([string]$rel) {
  if ($rel -match '[\x00-\x1f\\]' -or $rel.StartsWith('/')) { return $true }
  foreach ($part in $rel.ToLowerInvariant().Split('/')) { foreach ($p in $DenyParts) { if ($part -like $p) { return $true } } }
  return $false
}

function Get-SyncFiles([string]$root) {   # relative paths ('/' separated) that may sync
  if (-not (Test-Path -LiteralPath $root)) { return ,[string[]]@() }
  $full = (Resolve-Path -LiteralPath $root).ProviderPath.TrimEnd('\', '/')
  $out = New-Object Collections.Generic.List[string]
  # ponytail: links are skipped as files; a linked folder is still walked on Windows PowerShell 5.1
  foreach ($f in Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue) {
    if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
    $rel = $f.FullName.Substring($full.Length + 1).Replace('\', '/')
    if (Test-Denied $rel) { continue }
    if ($f.Length -gt $MaxFile) { [Console]::Error.WriteLine("bridge: not synced: $rel ($($f.Length) bytes, over the 1 MB cap)"); continue }
    $out.Add($rel)
  }
  $sorted = [string[]]@($out | Sort-Object -CaseSensitive)
  return ,$sorted
}

function New-Pack([string]$root, $files, [string]$tarPath) {
  $total = 0; foreach ($f in $files) { $total += (Get-Item -LiteralPath (Join-Path $root $f) -Force).Length }
  if ($total -gt $MaxTotal) { Fail "refusing to sync: $total bytes is over the 50 MB total cap" }
  $list = "$tarPath.list"; [IO.File]::WriteAllLines($list, [string[]]@($files), $Utf8)
  & tar -cf $tarPath -C $root -T $list; if ($LASTEXITCODE) { Fail 'tar failed' }
}

function Expand-Safe([string]$tarPath, [string]$dest) {  # plain uncompressed tar of files and folders; caps checked before extracting
  $fs = [IO.File]::OpenRead($tarPath); $head = New-Object byte[] 512; $got = $fs.Read($head, 0, 512); $fs.Close()
  $empty = -not ($head[0..([Math]::Max($got, 1) - 1)] | Where-Object { $_ -ne 0 })
  if (-not $empty -and ($got -lt 262 -or [Text.Encoding]::ASCII.GetString($head, 257, 5) -ne 'ustar')) { Fail 'refusing archive: not a plain tar (compressed archives are refused)' }
  $v = @(& tar -tvf $tarPath | Where-Object { $_ }); if ($LASTEXITCODE) { Fail 'the server sent an invalid archive' }
  if ($v.Count -gt $MaxEntries) { Fail "refusing archive: over $MaxEntries entries" }
  $total = [long]0
  foreach ($l in $v) {
    if ($l[0] -ne '-' -and $l[0] -ne 'd') { Fail 'refusing archive: it holds links or special files' }
    $p = $l -split '\s+'; $size = [long]$(if ($p[1].Contains('/')) { $p[2] } else { $p[4] })   # GNU tar vs bsdtar listing
    if ($size -gt $MaxFile) { Fail 'refusing archive: a file over the 1 MB cap' }
    $total += $size
  }
  if ($total -gt $MaxTotal) { Fail 'refusing archive: over the 50 MB total cap' }
  foreach ($n in @(& tar -tf $tarPath)) { if ($n -match '^/|[\\:]|(^|/)\.\.(/|$)') { Fail 'refusing archive: unsafe paths' } }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  & tar -xf $tarPath -C $dest; if ($LASTEXITCODE) { Fail 'could not unpack' }
  if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { & chmod -R u+rwX $dest }   # archive modes never lock us out
}

function Test-SafeDest([string]$root, [string]$rel) {  # no folder on the way is a link (reparse point), stays inside root
  $p = $root
  foreach ($part in ($rel.Split('/') | Select-Object -SkipLast 1)) {
    $p = Join-Path $p $part
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
  }
  $full = [IO.Path]::GetFullPath((Join-Path $root $rel)); $r = [IO.Path]::GetFullPath($root).TrimEnd('\', '/')
  return $full.StartsWith($r + [IO.Path]::DirectorySeparatorChar)
}

# strip terminal escapes / control characters (C0, DEL, C1) before printing text from the other side
function Get-Clean([string]$s) { return ($s -replace '[\x00-\x08\x0b-\x1f\x7f-\x9f]', '') }

function Read-Config {
  $c = @{ BRIDGE_CONTEXT = (Join-Path $Dir 'context'); BRIDGE_KEY = '' }
  $p = Join-Path $Dir 'config'
  if (-not (Test-Path $p)) { Fail 'not set up yet: run  .\bridge.ps1 setup me@my-server' }
  foreach ($l in [IO.File]::ReadAllLines($p)) { $i = $l.IndexOf('='); if ($i -gt 0) { $c[$l.Substring(0, $i)] = $l.Substring($i + 1) } }
  if (-not $c.BRIDGE_VPS -or -not $c.BRIDGE_NAME) { Fail "config $p is missing BRIDGE_VPS or BRIDGE_NAME" }
  New-Item -ItemType Directory -Force -Path $c.BRIDGE_CONTEXT | Out-Null
  return $c
}

function Invoke-Ssh([string]$hostSpec, [string]$remoteCmd, [string]$key, [string]$InFile, [byte[]]$InBytes, [string]$OutFile) {
  # Binary-safe ssh: stdin from a file or bytes, stdout to a file or a string. Key auth only (BatchMode).
  $a = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=15')
  if ($key) { $a += @('-i', "`"$key`"", '-o', 'IdentitiesOnly=yes') }
  $a += @($hostSpec, "`"$remoteCmd`"")
  $psi = New-Object Diagnostics.ProcessStartInfo 'ssh'
  $psi.Arguments = $a -join ' '; $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8; $psi.StandardErrorEncoding = $Utf8
  $p = [Diagnostics.Process]::Start($psi)
  $fs = $null
  if ($OutFile) { $fs = [IO.File]::Create($OutFile); $outTask = $p.StandardOutput.BaseStream.CopyToAsync($fs) } else { $outTask = $p.StandardOutput.ReadToEndAsync() }
  $errTask = $p.StandardError.ReadToEndAsync()
  try {
    if ($InFile) { $in = [IO.File]::OpenRead($InFile); $in.CopyTo($p.StandardInput.BaseStream); $in.Close() }
    elseif ($InBytes) { $p.StandardInput.BaseStream.Write($InBytes, 0, $InBytes.Length) }
    $p.StandardInput.Close()
  } catch { }  # the server may refuse and close stdin early; its stderr says why
  $p.WaitForExit(); $outTask.Wait()
  if ($fs) { $fs.Close() }
  $err = $errTask.Result; if ($err) { [Console]::Error.Write($err) }
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $(if ($OutFile) { '' } else { $outTask.Result }) }
}

function Invoke-Remote($c, [string]$cmd, [string]$InFile, [byte[]]$InBytes, [string]$OutFile) {
  Invoke-Ssh $c.BRIDGE_VPS "~/.local/bin/bridge-serve $cmd" $c.BRIDGE_KEY $InFile $InBytes $OutFile
}

function Sync-Context($c) {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("bridge-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  try {
    $ctx = $c.BRIDGE_CONTEXT
    $up = Get-SyncFiles $ctx
    New-Pack $ctx $up "$t/up.tar"
    $r = Invoke-Remote $c "sync $($c.BRIDGE_NAME)" -InFile "$t/up.tar" -OutFile "$t/down.tar"
    if ($r.Code) { Fail 'sync failed' }
    Expand-Safe "$t/down.tar" "$t/d"
    $down = Get-SyncFiles "$t/d"
    $set = New-Object 'Collections.Generic.HashSet[string]' (, [string[]]@($down))
    foreach ($f in $up) { if (-not $set.Contains($f)) { Remove-Item -LiteralPath (Join-Path $ctx $f) -Force } }
    foreach ($f in $down) {
      if (-not (Test-SafeDest $ctx $f)) {
        $b = 'blocked-' + $f.Replace('/', '_'); Copy-Item -LiteralPath (Join-Path "$t/d" $f) -Destination (Join-Path $ctx $b) -Force
        [Console]::Error.WriteLine("bridge: ${f}: a folder on its path is a link here; saved as $b"); continue
      }
      $dst = Join-Path $ctx $f; New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
      Copy-Item -LiteralPath (Join-Path "$t/d" $f) -Destination $dst -Force
    }
    Write-Output "synced $(@($down).Count) files: $ctx <-> $($c.BRIDGE_VPS)"
  } finally { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SafeRel([string]$p, [string]$root) { return ($p -and -not $p.Contains('\') -and -not $p.Contains(':') -and -not (Test-Denied $p) -and (Test-SafeDest $root $p)) }

function Invoke-Setup([string]$vps, [string]$name, [bool]$harden) {
  if (-not $vps) { Fail 'usage: .\bridge.ps1 setup me@my-server [-Name N] [-Harden]' }
  if (-not $name) { $name = ($env:COMPUTERNAME, [Net.Dns]::GetHostName() | Where-Object { $_ } | Select-Object -First 1) }
  $name = ($name -replace '[^A-Za-z0-9._-]', '').TrimStart('.'); if ($name.Length -gt 40) { $name = $name.Substring(0, 40) }
  if (-not $name) { Fail 'pick a name with -Name (letters, digits, . _ -)' }
  $here = $PSScriptRoot
  Write-Output "1/4 checking key login to $vps"
  $r = Invoke-Ssh $vps 'echo bridge-shell-ok' '' -InBytes ([byte[]]@())
  if ($r.Out -notmatch 'bridge-shell-ok') {
    Fail "key login to $vps failed. Set up a key first (docs/windows.md):  ssh-keygen -t ed25519  then  type `$env:USERPROFILE\.ssh\id_ed25519.pub | ssh $vps `"mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys`""
  }
  Write-Output "2/4 installing bridge-serve on $vps (~/.local/bin/bridge-serve)"
  $serve = $Utf8.GetBytes(([IO.File]::ReadAllText((Join-Path $here 'bridge'))).Replace("`r", ''))   # LF only, even after a CRLF checkout
  $r = Invoke-Ssh $vps 'mkdir -p ~/.local/bin && cat > ~/.local/bin/bridge-serve.new && chmod 755 ~/.local/bin/bridge-serve.new && mv ~/.local/bin/bridge-serve.new ~/.local/bin/bridge-serve && cp ~/.local/bin/bridge-serve ~/.local/bin/bridge' '' -InBytes $serve
  if ($r.Code) { Fail 'could not install bridge-serve' }
  $r = Invoke-Ssh $vps '~/.local/bin/bridge-serve ping' '' -InBytes ([byte[]]@()); Write-Output $r.Out.Trim()
  if ($r.Code) { Fail "bridge-serve does not run on $vps" }
  Write-Output "3/4 writing $Dir"
  $bin = Join-Path $Dir 'bin'; New-Item -ItemType Directory -Force -Path $bin, (Join-Path $Dir 'context') | Out-Null
  Copy-Item (Join-Path $here 'bridge.ps1'), (Join-Path $here 'mcp.mjs') -Destination $bin -Force
  $key = ''
  if ($harden) {
    $key = Join-Path $Dir 'bridge_key'
    if (-not (Test-Path $key)) {
      # an empty passphrase: PowerShell before 7.3 drops a bare '' argument, so it needs '""' there
      $empty = if ($PSVersionTable.PSVersion -ge [version]'7.3') { '' } else { '""' }
      & ssh-keygen -q -t ed25519 -N $empty -C "pierce-bridge-$name" -f $key; if ($LASTEXITCODE) { Fail 'ssh-keygen failed' }
    }
    $line = 'command="~/.local/bin/bridge-serve",restrict ' + ([IO.File]::ReadAllText("$key.pub")).Trim()
    Write-Output "This line will be added to ~/.ssh/authorized_keys on $vps. The new key can't open a shell or run commands,"
    Write-Output 'but what it sends (messages, synced files) reaches the lead, a Claude session with a full shell. A stolen'
    Write-Output 'bridge key can still try to talk the lead into things: treat bridge messages and files as untrusted input.'
    Write-Output "  $line"
    $a = Read-Host 'Add it? [y/N]'
    if ($a -eq 'y' -or $a -eq 'Y') {
      $r = Invoke-Ssh $vps '~/.local/bin/bridge-serve add-key' '' -InBytes ($Utf8.GetBytes("$line`n")); if ($r.Code) { Fail 'could not add the key' }
      $r = Invoke-Ssh $vps '~/.local/bin/bridge-serve ping' $key -InBytes ([byte[]]@()); if ($r.Code) { Fail 'the bridge key does not work' }
    } else { $key = ''; Write-Output 'skipped: the bridge will use your normal login (full shell access)' }
  }
  if (-not $key) { Write-Output "note: without -Harden the bridge uses your normal SSH login, which has full shell access on $vps" }
  [IO.File]::WriteAllLines((Join-Path $Dir 'config'), [string[]]@("BRIDGE_VPS=$vps", "BRIDGE_NAME=$name", "BRIDGE_KEY=$key", "BRIDGE_CONTEXT=$(Join-Path $Dir 'context')"), $Utf8)
  Write-Output '4/4 registering the MCP server with Claude Code'
  $mcp = Join-Path $bin 'mcp.mjs'
  $cmd = "claude mcp add -s user bridge -- node `"$mcp`""
  $cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
  if ((Get-Command claude -ErrorAction SilentlyContinue) -and (Get-Command node -ErrorAction SilentlyContinue) -and $cfg.StartsWith($HOME)) {
    & claude mcp add -s user bridge -- node $mcp; if ($LASTEXITCODE) { Write-Output '  (already added? remove it first: claude mcp remove -s user bridge)' }
  } else { Write-Output '  Claude Code / node not found here (or CLAUDE_CONFIG_DIR is outside your home). Run this yourself:'; Write-Output "  $cmd" }
  Write-Output "done. Add a shortcut to your PowerShell profile:  function bridge { & `"$(Join-Path $bin 'bridge.ps1')`" @args }"
}

# ---------- main ----------
$cmd = if ($args.Count) { [string]$args[0] } else { '' }
$rest = if ($args.Count -gt 1) { [string[]]$args[1..($args.Count - 1)] } else { [string[]]@() }
switch ($cmd) {
  'setup' {
    $vps = ''; $name = ''; $harden = $false
    for ($i = 0; $i -lt $rest.Count; $i++) {
      switch -Regex ($rest[$i]) { '^-{1,2}name$' { $i++; $name = $rest[$i] } '^-{1,2}harden$' { $harden = $true } default { $vps = $rest[$i] } }
    }
    Invoke-Setup $vps $name $harden
  }
  'send' {
    $c = Read-Config
    $text = if ($rest.Count) { $rest -join ' ' } else { [Console]::In.ReadToEnd() }
    $r = Invoke-Remote $c "send $($c.BRIDGE_NAME)" -InBytes ($Utf8.GetBytes($text)); Write-Output $r.Out.Trim(); exit $r.Code
  }
  'inbox' {
    $c = Read-Config
    $inbox = Join-Path $Dir 'inbox.txt'; $fp = Join-Path $Dir '.fetched'; $rp = Join-Path $Dir '.read'
    $n = if (Test-Path $fp) { [int]([IO.File]::ReadAllText($fp).Trim()) } else { 0 }
    $r = Invoke-Remote $c "fetch $n" -InBytes ([byte[]]@()); if ($r.Code) { Fail "could not reach $($c.BRIDGE_VPS)" }
    $new = @($r.Out -split "`n" | Where-Object { $_ -ne '' })
    if ($new.Count) { [IO.File]::AppendAllText($inbox, (($new -join "`n") + "`n"), $Utf8) }
    [IO.File]::WriteAllText($fp, [string]($n + $new.Count))
    $all = if (Test-Path $inbox) { @([IO.File]::ReadAllLines($inbox)) } else { @() }
    $read = if ((Test-Path $rp) -and $rest -notcontains '--all') { [int]([IO.File]::ReadAllText($rp).Trim()) } else { 0 }
    $show = @($all | Select-Object -Skip $read)
    if ($show.Count) { $show | ForEach-Object { Get-Clean $_.Replace("`t", ' ') } } else { Write-Output '(no new messages)' }
    [IO.File]::WriteAllText($rp, [string]$all.Count)
  }
  'sync' {
    $c = Read-Config
    if ($rest.Count -and $rest[0] -eq '--watch') {
      $n = if ($rest.Count -gt 1) { [int]$rest[1] } else { 60 }
      Write-Output "syncing every $n s (Ctrl+C stops)"; while ($true) { Sync-Context $c; Start-Sleep -Seconds $n }
    }
    Sync-Context $c
  }
  'share' {
    $c = Read-Config; $p = if ($rest.Count) { $rest[0] } else { '' }
    if (-not (Test-SafeRel $p $c.BRIDGE_CONTEXT)) { Fail "refused path: $p (empty, absolute, .. or on the deny-list)" }
    $bytes = $Utf8.GetBytes([Console]::In.ReadToEnd()); if ($bytes.Length -gt $MaxFile) { Fail 'over the 1 MB cap' }
    $dst = Join-Path $c.BRIDGE_CONTEXT $p; New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    [IO.File]::WriteAllBytes($dst, $bytes); Write-Output "wrote $p"; Sync-Context $c
  }
  'pull' {
    $c = Read-Config; Sync-Context $c | ForEach-Object { [Console]::Error.WriteLine($_) }
    if ($rest.Count) {
      $p = $rest[0]; $f = Join-Path $c.BRIDGE_CONTEXT $p
      if (-not (Test-SafeRel $p $c.BRIDGE_CONTEXT) -or -not (Test-Path -LiteralPath $f -PathType Leaf)) { Fail "no such file: $p" }
      [IO.File]::ReadAllText($f)
    } else { Get-SyncFiles $c.BRIDGE_CONTEXT }
  }
  'files' { $c = Read-Config; Get-SyncFiles $c.BRIDGE_CONTEXT }
  default { Get-Content $PSCommandPath -TotalCount 9 | Select-Object -Skip 2 | ForEach-Object { $_.TrimStart('# ') }; exit 2 }
}
