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


# Credentials
$User = (Get-WmiObject win32_computersystem).Domain + "\" + $env:UserName
$Creds = Get-Credential -Message "Enter Credentials for scheduling reboot" -User $User
$CimSession = New-CimSession -Credential $Creds

# VS Installs
$VSInstallUri = "https://s3.amazonaws.com/tauri-it/cdn/vs_community__957475882.1551791274.exe"
$VSExeOutput = "$PSScriptRoot\vs2017Community.exe"
$VsInstallPath = "C:\Program Files (x86)\Microsoft Visual Studio"

# Checks
$NugetPath = "C:\Program Files\PackageManagement\ProviderAssemblies\nuget"
$ChocoExe = "C:\ProgramData\chocolatey\choco.exe"
$HyperVChk = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V"
$LinSubChk = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux"
$VsPathChk = Test-Path "$VsInstallPath\2017\Community" 
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

# Install Chocolatey
if (!(Test-Path $ChocoExe)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
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

    cd "$PSScriptRoot"
    .\vs2017Community.exe --add Microsoft.VisualStudio.Workload.ManagedDesktop --includeRecommended `
        --add Microsoft.VisualStudio.Workload.NetCoreTools --add Microsoft.VisualStudio.Workload.NetWeb --quiet
    Schedule-TaskReboot
}

# Install special tools I like to use
choco install "$PSScriptRoot\ChocoFreshStart.config" -y
Schedule-TaskReboot

######
# Do a clone here for slack dark theme if using slack
######

Stop-Transcript