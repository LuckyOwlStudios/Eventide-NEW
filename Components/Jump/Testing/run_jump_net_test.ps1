<#
.SYNOPSIS
Runs the two-process jump test: a host and a guest over localhost.

.DESCRIPTION
Starts a headless server and a headless client on JumpNetTest.tscn. The host starts a jump, the guest
asks for the next one, and both must end at the same jump count in the same system, with the same
asteroids in the same places. Run it from a copy of the project while the editor is open.

.EXAMPLE
./run_jump_net_test.ps1
./run_jump_net_test.ps1 -Project C:\path\to\mirror
#>
param(
	[string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
	[string]$Project = "",
	[string]$LogFolder = $env:TEMP
)

if ($Project -eq "") {
	$Project = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
}
$scene = "res://Components/Jump/Testing/JumpNetTest.tscn"
$serverLog = Join-Path $LogFolder "jumpnet_server.log"
$clientLog = Join-Path $LogFolder "jumpnet_client.log"

$serverArgs = @("--headless", "--path", "$Project", $scene, "--", "server")
$clientArgs = @("--headless", "--path", "$Project", $scene, "--", "client")

$server = Start-Process -FilePath $Godot -ArgumentList $serverArgs -RedirectStandardOutput $serverLog -RedirectStandardError "$serverLog.err" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 4
$client = Start-Process -FilePath $Godot -ArgumentList $clientArgs -RedirectStandardOutput $clientLog -RedirectStandardError "$clientLog.err" -PassThru -WindowStyle Hidden
$null = $client.Handle
$null = $server.Handle
if (-not $client.WaitForExit(120000)) { Stop-Process -Id $client.Id -Force; Write-Host "client TIMED OUT" }
if (-not $server.WaitForExit(30000)) { Stop-Process -Id $server.Id -Force; Write-Host "server TIMED OUT" }

function Get-Line($path, $prefix) {
	return (Select-String -Path $path -Pattern "^$prefix" | Select-Object -First 1)
}

$serverResult = Get-Line $serverLog "RESULT server"
$clientResult = Get-Line $clientLog "RESULT client"
if (-not $serverResult -or -not $clientResult) {
	Write-Host "FAIL: a RESULT line is missing. See $serverLog and $clientLog."
	exit 1
}
Write-Host $serverResult.Line
Write-Host $clientResult.Line
Get-Line $serverLog "PHASES" | ForEach-Object { Write-Host $_.Line }
Get-Line $clientLog "PHASES" | ForEach-Object { Write-Host $_.Line }

function Get-Field($line, $name) {
	$match = [regex]::Match($line, "$name=(\S+)")
	if ($match.Success) { return $match.Groups[1].Value }
	return $null
}

$failed = $false
function Check($condition, $message) {
	if ($condition) { Write-Host "  ok   $message" } else { Write-Host "  FAIL $message"; $script:failed = $true }
}

$s = $serverResult.Line
$c = $clientResult.Line
Check ((Get-Field $s "count") -eq "2" -and (Get-Field $c "count") -eq "2") "both ended at jump 2"
Check ((Get-Field $s "seed") -eq (Get-Field $c "seed")) "with the same world seed"
Check ((Get-Field $s "system") -eq (Get-Field $c "system")) "in the same system"
Check ((Get-Field $s "arrival") -eq (Get-Field $c "arrival")) "built around the same arrival point"
Check ((Get-Field $s "field") -eq (Get-Field $c "field")) "with the same asteroids in the same places"
Check ((Get-Field $s "first_system") -eq (Get-Field $c "first_system") -and (Get-Field $s "first_system") -ne "0") "and the guest had the same system after the first jump"
Check ((Get-Field $c "crate_outside_gone") -eq "true") "the guest deleted the item lying outside its ship"
Check ((Get-Field $c "bubble_seen") -eq "true") "and showed the bubble while the system changed"
Check ((Get-Field $c "phase") -eq "0" -and (Get-Field $s "phase") -eq "0") "and both are back in a system"
Check ((Get-Field $s "ship") -eq (Get-Field $c "ship")) "the guest's ship is where the host's arrived, though it started a few meters away ($(Get-Field $c 'ship'))"
Check ((Get-Field $s "started") -eq "[1,2]" -and (Get-Field $c "started") -eq "[1,2]") "both were told each jump was starting ([1,2])"
Check ((Get-Field $s "completed") -eq "[1,2]" -and (Get-Field $c "completed") -eq "[1,2]") "and when each ended"
Check ((Get-Field $s "stars") -eq (Get-Field $c "stars") -and (Get-Field $s "heat") -eq (Get-Field $c "heat")) "and the same stars, which only the numbers were sent for (stars $(Get-Field $c 'stars'), heat $(Get-Field $c 'heat'))"

# The Cosmic Presence: the host's bar after each jump reached the guest, and so did the host's speed.
$serverBar = [double](Get-Field $s "bar")
$clientBar = [double](Get-Field $c "bar")
$serverFirst = [double](Get-Field $s "first_bar")
$clientFirst = [double](Get-Field $c "first_bar")
Check ([math]::Abs($serverFirst - $clientFirst) -lt 0.02) "the presence stood at the same place for both after the first jump (host $serverFirst, guest $clientFirst)"
Check ($serverFirst -gt 0.45 -and $serverFirst -lt 0.75) "which is where it began (0.5), plus what it covered since, less the jump's 0.05 ($serverFirst)"
Check ([math]::Abs($serverBar - $clientBar) -lt 0.02) "and after the second (host $serverBar, guest $clientBar)"
Check ((Get-Field $s "multiplier") -eq "2.000" -and (Get-Field $c "multiplier") -eq "2.000") "the host doubled the presence's speed and the guest saw it ($(Get-Field $c 'multiplier'))"
Check ((Get-Field $s "rate") -eq (Get-Field $c "rate")) "going the same speed ($(Get-Field $c 'rate'))"

if ($failed) { Write-Host "FAIL"; exit 1 } else { Write-Host "PASS" }
