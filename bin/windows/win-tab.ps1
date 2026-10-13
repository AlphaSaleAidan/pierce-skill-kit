# win-tab.ps1 - open hub tabs from your server as Windows Terminal tabs (one independent view per tab).
#   .\win-tab.ps1 acme-app data-sync     open those tabs     .\win-tab.ps1 -All    every tab in the hub
# Set your server once:  setx LK_VPS "me@my-server"   (then open a new terminal)
param([string[]]$Tabs = @(), [switch]$All, [string]$Server = $env:LK_VPS)
if (-not $Server) { Write-Error 'Set LK_VPS (e.g. setx LK_VPS "me@my-server") or pass -Server me@my-server'; exit 1 }
if ($All) { $Tabs = @(ssh $Server "tmux list-windows -t hub -F '#W'") }
if ($Tabs.Count -eq 0) { Write-Error 'Name at least one tab, or use -All'; exit 1 }
foreach ($t in $Tabs) {
  # tab-view gives each terminal its own view, so switching here doesn't move your other tabs
  wt -w 0 new-tab --title $t ssh -t $Server "~/.local/bin/tab-view hub:$t"
  Start-Sleep -Milliseconds 300
}
