######### Self Powershell Elevation #########
if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
     $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
     Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
     Exit
  }
}

$Date = Get-Date -uformat "%Y%m%d-%H%M"
$MyTz = "Eastern Standard Time"
Start-Transcript -Path "$PSScriptRoot\FreshStart_$Date.txt" -Verbose

# VS Installs
$VSInstallUri = "https://tauri-it.s3.amazonaws.com/cdn/vs_community__385086483.1552849408.exe"
$VSExeOutput = "$PSScriptRoot\vs2019Community.exe"
$VsInstallPath = "C:\Program Files (x86)\Microsoft Visual Studio"

# Checks
$NugetPath = "C:\Program Files\PackageManagement\ProviderAssemblies\nuget"
$HyperVChk = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V"
$LinSubChk = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux"
$VsPathChk = Test-Path "$VsInstallPath\2019\Community" 
$TZChk = Get-TimeZone
$BitsChk = Get-Module -Name bitstransfer

# Set my timezone
if ($TZChk.StandardName -ne $MyTz) {
    Set-TimeZone $MyTz
}

# Function for checking if reboot is required 
function Test-PendingReboot {
    if (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction Ignore) { 
        return $true 
    }
    if (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction Ignore) { 
        return $true
    }
    if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction Ignore) { 
        return $true 
    }
    try { 
        $util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
        $status = $util.DetermineIfRebootPending()
        if(($status -ne $null) -and $status.RebootPending) {
            return $true
        }
} catch {}
 
return $false

}

# Pending reboot checks and scheduling the task
function Schedule-TaskReboot {
    # Credentials
    $User = (Get-WmiObject win32_computersystem).Domain + "\" + $env:UserName
    $Creds = Get-Credential -Message "Enter Credentials for scheduling reboot" -User $User
    $CimSession = New-CimSession -Credential $Creds

    # Task
    $ReRunFreshStartTask = Get-ScheduledTask -TaskName "ReRunFreshStart" -ErrorAction SilentlyContinue
    $ReRunFreshStartAction = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "$PSScriptRoot\FreshStart.ps1"
    $ReRunFreshStartTrigger = New-ScheduledTaskTrigger -AtLogOn

    if (!($ReRunFreshStartTask)) {
        Register-ScheduledTask -Action $ReRunFreshStartAction -Trigger $ReRunFreshStartTrigger -RunLevel Highest `
            -TaskName "ReRunFreshStart" -Description "Re-Runs FreshStart Script" -CimSession $CimSession
    }
    if (((Test-PendingReboot) -eq ($true)) -and ($ReRunFreshStartTask)) {
        Restart-Computer -Force
    }
    if (((Test-PendingReboot) -eq ($false)) -and ($ReRunFreshStartTask)) {
        Unregister-ScheduledTask -TaskName "ReRunFreshStart" -Confirm:$false
    }
}

# Install Nuget
if(!(Test-Path $NugetPath)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

# Install bitstransfer cmdlet
if (!($BitsChk)) {
    Import-Module -Name BitsTransfer
}

# Enable Hyper-V and Linux subsystem
if ($HyperVChk.State -ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
}
if ($LinSubChk.State -ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
}

# Download and install VS
if (!($VsPathChk)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Start-BitsTransfer -Source $VSInstallUri -Destination $VSExeOutput

    & $VSExeOutput --add Microsoft.VisualStudio.Workload.ManagedDesktop --includeRecommended `
        --add Microsoft.VisualStudio.Workload.NetCoreTools --add Microsoft.VisualStudio.Workload.NetWeb --quiet
    Schedule-TaskReboot
}

Schedule-TaskReboot

Stop-Transcript