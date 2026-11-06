# bridge.ps1 - Windows side of the Pierce Skill Kit bridge: talk to the lead on your server over SSH only.
# Needs Windows PowerShell 5.1 or PowerShell 7, and the built-in OpenSSH client (ssh, ssh-keygen) and tar.exe.
#   .\bridge.ps1 setup me@my-server [-Name N] [-Harden]   one-time setup
#   bridge send "<text>"          type a message into the server's lead window (no text: read stdin)
#   bridge inbox [--all]          show new replies from the lead, then mark them read
#   bridge sync [--watch [N]]     mirror the shared context folder both ways (--watch: every N s, default 60)
#   bridge share <path>           write one file (content on stdin) into the context folder, then sync
#   bridge pull [path]            sync, then list the context folder (or print one file)
#   bridge sync --list            list what sync would send, after the deny-list and size caps
#   bridge files [path]           the file store: what's the same, to push, to pull, or changed on both sides
#   bridge files setup [folder]   your file store folder (default ~\PierceFiles); files there can be big (100 MB each)
#   bridge files push [path]      send new/changed files to the server (a path: only that; a file elsewhere: copied in)
#   bridge files pull [path]      get new/changed files from the server (changed on both sides: keeps both)
#   bridge files share <path> [minutes]   push, then a time-limited public link (only if the server owner turned sharing on)
$ErrorActionPreference = 'Stop'
try { [Console]::InputEncoding = [Text.UTF8Encoding]::new($false); [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
$MaxFile = 1048576; $MaxTotal = 52428800; $MaxEntries = 5000
$FilesMaxFile = 104857600; $FilesMaxTotal = 1073741824   # file store: 100 MB per file, 1 GB per ssh call
$FilesBatch = if ($env:FILES_BATCH) { [long]$env:FILES_BATCH } else { 104857600 }   # batches of up to 100 MB: a dropped link loses one batch
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
    if ($f.Length -gt $MaxFile) { [Console]::Error.WriteLine("bridge: skipped ${rel}: $([Math]::Ceiling($f.Length / 1MB)) MB, over the $($MaxFile / 1MB) MB cap"); continue }
    $out.Add($rel)
  }
  $sorted = [string[]]@($out | Sort-Object -CaseSensitive)
  return ,$sorted
}

function New-Pack([string]$root, $files, [string]$tarPath) {
  $total = 0; foreach ($f in $files) { $total += (Get-Item -LiteralPath (Join-Path $root $f) -Force).Length }
  if ($total -gt $MaxTotal) { Fail "refusing: $([Math]::Floor($total / 1MB)) MB is over the $($MaxTotal / 1MB) MB cap for one transfer" }
  # ./ first: a name starting with - is never read as a tar option
  $list = "$tarPath.list"; [IO.File]::WriteAllLines($list, [string[]]@($files | ForEach-Object { "./$_" }), $Utf8)
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
    if ($size -gt $MaxFile) { Fail "refusing archive: a file over the $($MaxFile / 1MB) MB cap" }
    $total += $size
  }
  if ($total -gt $MaxTotal) { Fail "refusing archive: over the $($MaxTotal / 1MB) MB total cap" }
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
  $c = @{ BRIDGE_CONTEXT = (Join-Path $Dir 'context'); BRIDGE_KEY = ''; BRIDGE_FILES = (Join-Path $HOME 'PierceFiles') }
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
  return [pscustomobject]@{ Code = $p.ExitCode; Err = $err; Out = $(if ($OutFile) { '' } else { $outTask.Result }) }
}

function Invoke-Remote($c, [string]$cmd, [string]$InFile, [byte[]]$InBytes, [string]$OutFile) {
  $serve = if ($env:BRIDGE_SERVE) { $env:BRIDGE_SERVE } else { '~/.local/bin/bridge-serve' }   # BRIDGE_SERVE: the Windows test pack's throwaway copy
  Invoke-Ssh $c.BRIDGE_VPS "$serve $cmd" $c.BRIDGE_KEY $InFile $InBytes $OutFile
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

# ---------- the file store: BRIDGE_FILES (default ~\PierceFiles) <-> ~/.pierce-skill-kit/files on the server ----------
function Set-BigCaps { $script:MaxFile = $FilesMaxFile; $script:MaxTotal = $FilesMaxTotal }
function Get-Hash([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-Manifest([string]$root) {   # path -> sha256 (case-sensitive keys, like the server); only changed files are hashed again
  $h = New-Object 'Collections.Generic.Dictionary[string,string]'; $cp = Join-Path $Dir 'files-hash.tsv'
  $cache = @{}; if (Test-Path $cp) { foreach ($l in [IO.File]::ReadAllLines($cp, $Utf8)) { $x = $l.Split("`t"); if ($x.Count -eq 4) { $cache["$($x[0])`t$($x[1])`t$($x[2])"] = $x[3] } } }
  $out = New-Object Collections.Generic.List[string]
  foreach ($f in (Get-SyncFiles $root)) {
    $i = Get-Item -LiteralPath (Join-Path $root $f) -Force; $k = "$f`t$($i.Length)`t$($i.LastWriteTimeUtc.Ticks)"
    $h[$f] = if ($cache.ContainsKey($k)) { $cache[$k] } else { Get-Hash $i.FullName }; $out.Add("$k`t$($h[$f])")
  }
  try { [IO.File]::WriteAllLines($cp, [string[]]$out, $Utf8) } catch { }
  return $h
}
function Save-Old([string]$root, [string]$rel) {  # move the copy about to be replaced into files-trash\<time>\<rel>
  $src = Join-Path $root $rel; if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return }
  $k = Join-Path (Join-Path (Join-Path $Dir 'files-trash') (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')) $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $k) | Out-Null; Move-Item -LiteralPath $src -Destination $k -Force
}
function Stop-Remote($c, $r) {   # an ssh call failed: say why in plain words
  if ($r.Err -match 'not a bridge action') { Fail "the server has an older bridge. Update it once:  .\bridge.ps1 setup $($c.BRIDGE_VPS) -Name $($c.BRIDGE_NAME)" }
  if ($r.Err -match 'refused:') { Fail 'the server said no (above)' }
  Fail "can't reach $($c.BRIDGE_VPS) (offline, asleep or no network). Nothing changed; your files are still in $($c.BRIDGE_FILES). Try again later."
}
function Get-ServerFiles($c) {
  $r = Invoke-Remote $c 'files-ls' -InBytes ([byte[]]@()); if ($r.Code) { Stop-Remote $c $r }
  $h = New-Object 'Collections.Generic.Dictionary[string,string]'; $script:SrvSize = New-Object 'Collections.Generic.Dictionary[string,long]'
  foreach ($l in ($r.Out -split "`n")) { $p = $l.TrimEnd("`r").Split("`t"); if ($p.Count -ge 2 -and $p[0]) { $h[$p[0]] = $p[1]; if ($p.Count -ge 3) { $script:SrvSize[$p[0]] = [long]$p[2] } } }
  return $h
}
function Split-Batches([string[]]$files, $sizeOf) {  # lists of up to $FilesBatch bytes each
  $out = New-Object Collections.Generic.List[object]; $cur = New-Object Collections.Generic.List[string]; $tot = [long]0
  foreach ($f in $files) { $s = [long](& $sizeOf $f); if ($cur.Count -and $tot + $s -gt $FilesBatch) { $out.Add([string[]]$cur.ToArray()); $cur.Clear(); $tot = 0 }; $cur.Add($f); $tot += $s }
  if ($cur.Count) { $out.Add([string[]]$cur.ToArray()) }
  return ,$out
}
function Test-InScope([string]$f, [string]$scope) { return (-not $scope -or $f -eq $scope -or $f.StartsWith("$scope/")) }
$PathCmp = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
function Get-Count([int]$n) { if ($n -eq 1) { return '1 file' } return "$n files" }
function Get-Size([long]$b) { if ($b -ge 1MB) { return '{0:N1} MB' -f ($b / 1MB) } if ($b -ge 1KB) { return "$([Math]::Floor($b / 1KB)) KB" } return "$b bytes" }
function Get-Scope($c, [string]$mode, [string]$p) {  # a path inside the store -> relative; push: a file elsewhere is copied in first
  if (-not $p) { return '' }
  if ($mode -ne 'push' -and -not [IO.Path]::IsPathRooted($p)) {   # pull/status: a relative path means a path in the store
    $s = $p.Replace('\', '/').TrimEnd('/'); if ($s.StartsWith('./')) { $s = $s.Substring(2) }
    if ($s.Contains('..') -or $s.Contains(':')) { Fail "refused path: $p" }; return $s
  }
  $root = [IO.Path]::GetFullPath($c.BRIDGE_FILES).TrimEnd('\', '/')
  if (Test-Path -LiteralPath $p) {
    $full = (Resolve-Path -LiteralPath $p).ProviderPath.TrimEnd('\', '/')
    if ($full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, $PathCmp)) { return $full.Substring($root.Length + 1).Replace('\', '/') }
    if (Test-Path -LiteralPath $full -PathType Container) { Fail "$p is a folder outside $root. Push takes outside files one at a time; for a whole folder, copy it into $root first" }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      if ($mode -ne 'push') { Fail "$p is not in $root. Pull takes a path inside the store, e.g. bridge files pull clients" }
      $b = Split-Path $full -Leaf
      if (Test-Denied $b) { Fail "refused: $b looks like a secret or key (.env, *.pem, token...), so it never leaves this computer" }
      if ((Get-Item -LiteralPath $full -Force).Length -gt $MaxFile) { Fail "$b is over the 100 MB cap" }
      if (Test-Path -LiteralPath (Join-Path $root $b)) { [Console]::Out.WriteLine("replaced $b in $root (old copy in $(Join-Path $Dir 'files-trash'))") }
      Save-Old $root $b; Copy-Item -LiteralPath $full -Destination (Join-Path $root $b) -Force
      [Console]::Out.WriteLine("copied $b into $root"); return $b
    }
  }
  if ([IO.Path]::IsPathRooted($p)) { Fail "no such file: $p" }
  $s = $p.Replace('\', '/').TrimEnd('/')
  if ($s.StartsWith('/') -or $s.Contains('..') -or $s.Contains(':')) { Fail "refused path: $p" }
  return $s
}
function Read-Base {
  $h = New-Object 'Collections.Generic.Dictionary[string,string]'; $p = Join-Path $Dir 'files-base.tsv'
  if (Test-Path $p) { foreach ($l in [IO.File]::ReadAllLines($p, $Utf8)) { $i = $l.IndexOf("`t"); if ($i -gt 0) { $h[$l.Substring(0, $i)] = $l.Substring($i + 1) } } }
  return $h
}
function Save-Agreed($manifest, $paths) {  # record those files' hashes as agreed by both sides
  $b = Read-Base; foreach ($f in $paths) { if ($manifest.ContainsKey($f)) { $b[$f] = $manifest[$f] } }
  [IO.File]::WriteAllLines((Join-Path $Dir 'files-base.tsv'), [string[]]@($b.Keys | ForEach-Object { "$_`t$($b[$_])" }), $Utf8)
}
function Get-Plan($c, [string]$scope) {  # same | up | down | both | clash | case, for every path in scope
  $script:Srv = Get-ServerFiles $c; $script:Mine = Get-Manifest $c.BRIDGE_FILES; $base = Read-Base
  $all = New-Object 'Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
  foreach ($k in $script:Srv.Keys) { [void]$all.Add($k) }; foreach ($k in $script:Mine.Keys) { [void]$all.Add($k) }
  # clash = a file on one side has the name of a folder on the other; case = names that differ only in capitals
  $dirs = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal); $lc = @{}
  foreach ($f in $all) { $k = $f.ToLowerInvariant(); $lc[$k] = 1 + $(if ($lc.ContainsKey($k)) { $lc[$k] } else { 0 }); $i = $f.IndexOf('/'); while ($i -gt 0) { [void]$dirs.Add($f.Substring(0, $i)); $i = $f.IndexOf('/', $i + 1) } }
  $plan = New-Object Collections.Generic.List[object]
  foreach ($f in $all) {
    if (-not (Test-InScope $f $scope)) { continue }
    $bad = $dirs.Contains($f); $i = $f.IndexOf('/'); while (-not $bad -and $i -gt 0) { if ($all.Contains($f.Substring(0, $i))) { $bad = $true }; $i = $f.IndexOf('/', $i + 1) }
    if ($bad) { [Console]::Error.WriteLine("bridge: skipped ${f}: a file on one side has the name of a folder on the other. Rename one"); $plan.Add([pscustomobject]@{ A = 'clash'; F = $f }); continue }
    if ($lc[$f.ToLowerInvariant()] -gt 1) { [Console]::Error.WriteLine("bridge: skipped ${f}: another name differs only in capitals, and Windows and Macs can't keep both. Rename one"); $plan.Add([pscustomobject]@{ A = 'case'; F = $f }); continue }
    $l = if ($script:Mine.ContainsKey($f)) { $script:Mine[$f] } else { '' }; $v = if ($script:Srv.ContainsKey($f)) { $script:Srv[$f] } else { '' }
    $o = if ($base.ContainsKey($f)) { $base[$f] } else { '' }
    $a = if ($l -eq $v) { 'same' } elseif (-not $v) { 'up' } elseif (-not $l) { 'down' } elseif ($l -eq $o) { 'down' } elseif ($v -eq $o) { 'up' } else { 'both' }
    $plan.Add([pscustomobject]@{ A = $a; F = $f })
  }
  return ,$plan
}
function Get-StoreNotes($c, [string]$scope) {  # say once per file what stays home; count files over the cap
  $full = (Resolve-Path -LiteralPath $c.BRIDGE_FILES).ProviderPath.TrimEnd('\', '/'); $wp = Join-Path $Dir 'files-warned'
  $warned = if (Test-Path $wp) { @([IO.File]::ReadAllLines($wp, $Utf8)) } else { @() }; $big = 0
  foreach ($f in Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue) {
    $rel = $f.FullName.Substring($full.Length + 1).Replace('\', '/')
    if (-not (Test-InScope $rel $scope)) { continue }
    if (Test-Denied $rel) { if ($warned -notcontains $rel) { [Console]::Error.WriteLine("bridge: kept on this computer (looks like a secret or key): $rel"); [IO.File]::AppendAllText($wp, "$rel`n", $Utf8) } }
    elseif ($f.Length -gt $MaxFile) { $big++ }
  }
  return $big
}
function Show-Speed([long]$bytes, $sw) { if ($bytes -ge 5MB) { $s = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalSeconds)); Write-Output ('  ... {0:N1} MB in {1} s ({2:N1} MB/s)' -f ($bytes / 1MB), $s, ($bytes / 1MB / $s)) } }
function Test-Nope($c, [string]$scope, $plan) { if ($scope -and -not $plan.Count) { Fail "no file or folder called $scope in $($c.BRIDGE_FILES) or on the server" } }
function Show-Status($c, [string]$p) {
  $scope = Get-Scope $c 'pull' $p; $plan = Get-Plan $c $scope; Test-Nope $c $scope $plan
  if (-not $plan.Count) { Write-Output "the file store is empty: put files in $($c.BRIDGE_FILES), then bridge files push"; return }
  foreach ($x in $plan) { $w = switch ($x.A) { 'same' { 'same     ' } 'up' { 'to push  ' } 'down' { 'to pull  ' } 'both' { 'CHANGED BOTH SIDES (pull keeps both)  ' } default { 'SKIPPED (see above)  ' } }; Write-Output "  $w $($x.F)" }
  $n = @{}; foreach ($x in $plan) { $n[$x.A] = 1 + $(if ($n.ContainsKey($x.A)) { $n[$x.A] } else { 0 }) }
  $g = { param($k) if ($n.ContainsKey($k)) { $n[$k] } else { 0 } }
  Write-Output "$(& $g 'same') same, $(& $g 'up') to push, $(& $g 'down') to pull, $(& $g 'both') changed on both sides, $((& $g 'clash') + (& $g 'case')) skipped"
}
function Push-Files($c, [string]$p, [bool]$quiet = $false) {
  $script:Scope = Get-Scope $c 'push' $p; $root = $c.BRIDGE_FILES
  $plan = Get-Plan $c $script:Scope; Test-Nope $c $script:Scope $plan; $big = Get-StoreNotes $c $script:Scope
  $both = @($plan | Where-Object { $_.A -eq 'both' } | ForEach-Object { $_.F })
  foreach ($f in $both) { [Console]::Error.WriteLine("bridge: not sent: $f changed here AND on the server. Run  bridge files pull  first (it keeps both copies)") }
  $same = @($plan | Where-Object { $_.A -eq 'same' } | ForEach-Object { $_.F }); if ($same.Count) { Save-Agreed $script:Mine $same }
  $up = [string[]]@($plan | Where-Object { $_.A -eq 'up' } | ForEach-Object { $_.F })
  $script:Left = @($plan | Where-Object { $_.A -in @('both', 'clash', 'case') }).Count
  if (-not $up.Count) {
    if (-not $quiet) { if ($big -or $script:Left) { Write-Output "nothing else to send ($(Get-Count ($big + $script:Left)) held back, see above)" } else { Write-Output "up to date: the server already has $(if ($script:Scope) { $script:Scope } else { "everything in $root" })" } }
    return
  }
  $t = Join-Path ([IO.Path]::GetTempPath()) ("bridge-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $t | Out-Null
  try {
    $done = 0
    foreach ($batch in (Split-Batches $up { param($f) (Get-Item -LiteralPath (Join-Path $root $f) -Force).Length })) {
      foreach ($f in $batch) { Write-Output "  sending $f ($(Get-Size (Get-Item -LiteralPath (Join-Path $root $f) -Force).Length))" }
      New-Pack $root $batch "$t/up.tar"; $sw = [Diagnostics.Stopwatch]::StartNew()
      $r = Invoke-Remote $c "files-put $($c.BRIDGE_NAME)" -InFile "$t/up.tar"; Show-Speed (Get-Item "$t/up.tar").Length $sw
      if ($r.Code) { Fail "push stopped after $(Get-Count $done) of $($up.Count). Run it again to send the rest (finished files aren't sent twice)" }
      Save-Agreed $script:Mine $batch; $done += $batch.Count
    }
    Write-Output "sent $(Get-Count $done) to the server"; if ($big -or $script:Left) { Write-Output "$(Get-Count ($big + $script:Left)) held back (see above)" }
  } finally { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
}
function Pull-Files($c, [string]$p) {
  $scope = Get-Scope $c 'pull' $p; $root = $c.BRIDGE_FILES
  $plan = Get-Plan $c $scope; Test-Nope $c $scope $plan
  $script:Left = @($plan | Where-Object { $_.A -in @('clash', 'case') }).Count
  $same = @($plan | Where-Object { $_.A -eq 'same' } | ForEach-Object { $_.F }); if ($same.Count) { Save-Agreed $script:Srv $same }
  $both = @($plan | Where-Object { $_.A -eq 'both' } | ForEach-Object { $_.F })
  $want = [string[]]@($plan | Where-Object { $_.A -eq 'down' -or $_.A -eq 'both' } | ForEach-Object { $_.F })
  if ($env:OS -eq 'Windows_NT') {   # Windows can't hold Report.md and report.md in one folder: keep the first, say so
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $script:Mine.Keys) { [void]$seen.Add($k) }
    $want = [string[]]@($want | Where-Object {
      if ($seen.Add($_) -or $script:Mine.ContainsKey($_)) { $true } else { [Console]::Error.WriteLine("bridge: skipped ${_}: Windows can't keep two names that differ only in capitals. Rename one on the server"); $false } })
  }
  if (-not $want.Count) { Write-Output 'up to date: nothing new on the server'; return }
  $t = Join-Path ([IO.Path]::GetTempPath()) ("bridge-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $t | Out-Null
  try {
    $n = 0
    foreach ($batch in (Split-Batches $want { param($f) if ($script:SrvSize.ContainsKey($f)) { $script:SrvSize[$f] } else { 0 } })) {
    $ok = New-Object Collections.Generic.List[string]
    Remove-Item -LiteralPath "$t/d" -Recurse -Force -ErrorAction SilentlyContinue
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-Remote $c 'files-get' -InBytes ($Utf8.GetBytes(($batch -join "`n") + "`n")) -OutFile "$t/down.tar"
    if ($r.Code) { Fail "pull stopped after $(Get-Count $n) of $($want.Count). Run it again to get the rest (finished files aren't fetched twice)" }
    Expand-Safe "$t/down.tar" "$t/d"; Show-Speed (Get-Item "$t/down.tar").Length $sw
    foreach ($f in (Get-SyncFiles "$t/d")) {
      if (-not (Test-SafeDest $root $f)) { [Console]::Error.WriteLine("bridge: ${f}: a folder on its path is a link here; not written"); continue }
      $dst = Join-Path $root $f
      if (Test-Path -LiteralPath $dst -PathType Container) { [Console]::Error.WriteLine("bridge: not written: $f is a folder here. Rename one"); continue }
      $pd = Split-Path $dst; if ((Test-Path -LiteralPath $pd -PathType Leaf)) { [Console]::Error.WriteLine("bridge: not written: a file here has the name of a folder in $f. Rename one"); continue }
      if ($both -contains $f) {   # changed on both sides: the server copy takes the name, yours moves beside it
        $leaf = Split-Path $f -Leaf; $ext = [IO.Path]::GetExtension($leaf); $stem = if ($ext -and $leaf.Length -gt $ext.Length) { $leaf.Substring(0, $leaf.Length - $ext.Length) } else { $leaf; $ext = '' }
        $cn = "$stem.conflict-$($c.BRIDGE_NAME)-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))$ext"
        $cr = if ($f.Contains('/')) { $f.Substring(0, $f.LastIndexOf('/') + 1) + $cn } else { $cn }
        Move-Item -LiteralPath $dst -Destination (Join-Path $root $cr) -Force; Write-Output "  kept both: $f (yours: $cr)"
      } else { Save-Old $root $f }
      New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
      Copy-Item -LiteralPath (Join-Path "$t/d" $f) -Destination "$dst.part-$PID" -Force; Move-Item -LiteralPath "$dst.part-$PID" -Destination $dst -Force; $n++; $ok.Add($f)   # temp name, then rename
      if ($both -notcontains $f) { Write-Output "  got $f ($(Get-Size (Get-Item -LiteralPath $dst -Force).Length))" }
    }
    if ($ok.Count) { Save-Agreed $script:Srv $ok }
    }
    Write-Output "got $(Get-Count $n) from the server, in $root"
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
  $cfgPath = Join-Path $Dir 'config'   # a re-run keeps the file store folder
  $keepF = if (Test-Path $cfgPath) { @([IO.File]::ReadAllLines($cfgPath) | Where-Object { $_.StartsWith('BRIDGE_FILES=') }) } else { @() }
  [IO.File]::WriteAllLines($cfgPath, [string[]](@("BRIDGE_VPS=$vps", "BRIDGE_NAME=$name", "BRIDGE_KEY=$key", "BRIDGE_CONTEXT=$(Join-Path $Dir 'context')") + $keepF), $Utf8)
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
$rest = [string[]]@($args | Select-Object -Skip 1)   # always an array: a lone argument must not become a string
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
    if ($rest.Count -and $rest[0] -eq '--list') { Get-SyncFiles $c.BRIDGE_CONTEXT; break }
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
  'files' {
    $c = Read-Config; $sub = if ($rest.Count) { $rest[0] } else { '' }; $a1 = if ($rest.Count -gt 1) { $rest[1] } else { '' }
    if ($sub -eq '' -or $sub -eq 'status') { New-Item -ItemType Directory -Force -Path $c.BRIDGE_FILES | Out-Null; Set-BigCaps; Show-Status $c $a1; break }
    if ($sub -eq 'setup') {
      $r = Invoke-Remote $c 'files-ls' -InBytes ([byte[]]@()); if ($r.Code) { Stop-Remote $c $r }   # server first: offline changes nothing
      $f = if ($a1) { $a1 } else { $c.BRIDGE_FILES }   # no folder given: keep the one you have
      New-Item -ItemType Directory -Force -Path $f | Out-Null; $f = (Resolve-Path -LiteralPath $f).ProviderPath
      if ($f -ne $c.BRIDGE_FILES) { foreach ($x in 'files-base.tsv', 'files-warned', 'files-hash.tsv') { Remove-Item -LiteralPath (Join-Path $Dir $x) -Force -ErrorAction SilentlyContinue } }   # a new folder starts with no history
      $cp = Join-Path $Dir 'config'
      $lines = @([IO.File]::ReadAllLines($cp) | Where-Object { -not $_.StartsWith('BRIDGE_FILES=') }) + "BRIDGE_FILES=$f"
      [IO.File]::WriteAllLines($cp, [string[]]$lines, $Utf8); $c.BRIDGE_FILES = $f
      Write-Output "file store ready: $f <-> $($c.BRIDGE_VPS):~/.pierce-skill-kit/files"
      Write-Output "put files in $f, then: bridge files push    (and bridge files pull to get the server's)"; break
    }
    if ($sub.StartsWith('-')) { Fail 'usage: bridge files [path] | setup [folder] | push [path] | pull [path] | share <path> [minutes]' }
    if ($sub -notin @('push', 'pull', 'share', 'sync')) { New-Item -ItemType Directory -Force -Path $c.BRIDGE_FILES | Out-Null; Set-BigCaps; Show-Status $c $sub; break }   # bridge files <path>
    New-Item -ItemType Directory -Force -Path $c.BRIDGE_FILES | Out-Null; Set-BigCaps
    switch ($sub) {
      'push' { Push-Files $c $a1 }
      'pull' { Pull-Files $c $a1 }
      'sync' { Pull-Files $c $a1; Push-Files $c $a1 }   # pull first: a two-sided change keeps both
      'share' {
        if (-not $a1) { Fail 'usage: bridge files share <path> [minutes, default 60]' }
        $m = if ($rest.Count -gt 2) { $rest[2] } else { '60' }
        if ($m -notmatch '^\d{1,4}$' -or [int]$m -lt 1 -or [int]$m -gt 1440) { Fail 'minutes must be a number from 1 to 1440' }
        Push-Files $c $a1 $true
        $r = Invoke-Remote $c "files-share $m" -InBytes ($Utf8.GetBytes("$script:Scope`n")); if ($r.Code) { Fail 'no link made' }
        Write-Output $r.Out.Trim()
      }
    }
    if ($script:Left) { exit 3 }   # something was held back (see above)
  }
  default { Get-Content $PSCommandPath -TotalCount 14 | Select-Object -Skip 2 | ForEach-Object { $_.TrimStart('# ') }; exit 2 }
}
