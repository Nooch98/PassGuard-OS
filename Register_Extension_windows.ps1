param (
    [Parameter(Mandatory=$true, HelpMessage="Drag and drop your .json file here or paste the path")]
    [string]$JsonPath
)

$JsonPath = $JsonPath.Trim('"')

if (!(Test-Path $JsonPath)) {
    Write-Host "Error: File not found at $JsonPath" -ForegroundColor Red
    pause
    exit
}

try {
    $JsonContent = Get-Content $JsonPath -Raw | ConvertFrom-Json
    $HostName = $JsonContent.name
} catch {
    Write-Host "Error: Failed to parse JSON." -ForegroundColor Red
    pause
    exit
}

Clear-Host
Write-Host "--- Native Messaging Host Manager: $HostName ---" -ForegroundColor Cyan
Write-Host "1) Register Host"
Write-Host "2) Remove (Unregister) Host"
Write-Host "3) Exit"
$action = Read-Host "Select action (1-3)"

if ($action -eq "3") { exit }

Write-Host "`nSelect the browser:"
Write-Host "1) Google Chrome"
Write-Host "2) Mozilla Firefox"
Write-Host "3) Brave Browser"
Write-Host "4) Opera GX"
Write-Host "5) ALL OF THE ABOVE"
$browserOption = Read-Host "Choose an option (1-5)"

$paths = @{
    "1" = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HostName"
    "2" = "HKCU:\Software\Mozilla\NativeMessagingHosts\$HostName"
    "3" = "HKCU:\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\$HostName"
    "4" = "HKCU:\Software\Software\Opera Software\Opera GX Stable\NativeMessagingHosts\$HostName"
}

function Register-Host($regPath) {
    if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "(Default)" -Value $JsonPath
    Write-Host "Registered in: $regPath" -ForegroundColor Green
}

function Unregister-Host($regPath) {
    if (Test-Path $regPath) {
        Remove-Item -Path $regPath -Recurse -Force
        Write-Host "Removed from: $regPath" -ForegroundColor Yellow
    } else {
        Write-Host "Host not found in: $regPath" -ForegroundColor Gray
    }
}

$targetPaths = if ($browserOption -eq "5") { $paths.Values } else { @($paths[$browserOption]) }

foreach ($path in $targetPaths) {
    if ($action -eq "1") { Register-Host $path }
    elseif ($action -eq "2") { Unregister-Host $path }
}

Write-Host "`nOperation completed. Please restart your browser." -ForegroundColor Cyan
pause
