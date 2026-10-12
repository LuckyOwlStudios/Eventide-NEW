<#
.SYNOPSIS
Runs the two-process CharacterNetSync test: one server, one client, over localhost.

.DESCRIPTION
Starts a headless server and a headless client on NetSyncTest.tscn, optionally with
simulated lag and packet loss, then compares where the server says the player ended
up with where the client thinks it is. The server's world has a wall the client does
not, so the client has to be corrected along the way.

.EXAMPLE
./run_net_sync_test.ps1
./run_net_sync_test.ps1 -LatencyMs 250 -LossPercent 15
./run_net_sync_test.ps1 -Teleport
./run_net_sync_test.ps1 -SpeedHack
#>
param(
	[string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
	[int]$LatencyMs = 100,
	[int]$LossPercent = 5,
	[int]$Seconds = 14,
	## The server moves the player mid-run; everyone has to follow.
	[switch]$Teleport,
	## The client sends commands twice as fast as it is allowed to.
	[switch]$SpeedHack
)

$project = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$scene = "res://Components/Movement/Testing/NetSyncTest.tscn"
$serverLog = Join-Path $env:TEMP "netsync_server.log"
$clientLog = Join-Path $env:TEMP "netsync_client.log"
$mode = if ($SpeedHack) { "hack" } else { "honest" }

if ($Teleport) { $env:TELEPORT = "1" } else { Remove-Item Env:TELEPORT -ErrorAction SilentlyContinue }

$serverArgs = @("--headless", "--path", "$project", $scene, "--", "server", $LatencyMs, $LossPercent, ($Seconds + 8))
$clientArgs = @("--headless", "--path", "$project", $scene, "--", "client", $LatencyMs, $LossPercent, $Seconds, $mode)

$server = Start-Process -FilePath $Godot -ArgumentList $serverArgs -RedirectStandardOutput $serverLog -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 4
$client = Start-Process -FilePath $Godot -ArgumentList $clientArgs -RedirectStandardOutput $clientLog -PassThru -WindowStyle Hidden
$client | Wait-Process
$server | Wait-Process

function Get-Result($path, $who, $name) {
	$line = Select-String -Path $path -Pattern "^RESULT $who $name " | Select-Object -First 1
	if (-not $line) { return $null }
	$parts = $line.Line.Split(" ")
	return [pscustomobject]@{ X = [double]$parts[3]; Y = [double]$parts[4]; Z = [double]$parts[5] }
}

$serverPlayer = $null
$clientPlayer = $null
$line = Select-String -Path $serverLog -Pattern "^RESULT server P" | Select-Object -First 1
if ($line) {
	$name = $line.Line.Split(" ")[2]
	$serverPlayer = Get-Result $serverLog "server" $name
	$clientPlayer = Get-Result $clientLog "client" $name
}
$serverNpc = Get-Result $serverLog "server" "NPC"
$clientNpc = Get-Result $clientLog "client" "NPC"

if (-not $serverPlayer -or -not $clientPlayer -or -not $serverNpc -or -not $clientNpc) {
	Write-Host "FAIL: a result line is missing. See $serverLog and $clientLog."
	exit 1
}

function Get-Distance($a, $b) {
	return [math]::Sqrt([math]::Pow($a.X - $b.X, 2) + [math]::Pow($a.Y - $b.Y, 2) + [math]::Pow($a.Z - $b.Z, 2))
}

$playerError = Get-Distance $serverPlayer $clientPlayer
$npcError = Get-Distance $serverNpc $clientNpc
Write-Host ("Server player: {0:N3} {1:N3} {2:N3}" -f $serverPlayer.X, $serverPlayer.Y, $serverPlayer.Z)
Write-Host ("Client player: {0:N3} {1:N3} {2:N3}   (off by {3:N4} m)" -f $clientPlayer.X, $clientPlayer.Y, $clientPlayer.Z, $playerError)
Write-Host ("NPC on client is off by {0:N4} m" -f $npcError)
Select-String -Path $clientLog -Pattern "^INFO reconciles" | ForEach-Object { Write-Host $_.Line }

if ($playerError -lt 0.05 -and $npcError -lt 0.05) {
	Write-Host "PASS"
	exit 0
}
Write-Host "FAIL"
exit 1
