# A Fresh Start, Starts Here

**Pre-Requisites**: Internet access, admin rights, and set execution policy to bypass    
**How to use**: Right click ```FreshStart.ps1``` and select `Run with PowerShell`  

### Details:
Uses chocolatey as a package manager for several packages located in ```ChocoFreshStart.config```  
Enables Hyper-V  
Enables Linux subsystem  
Downloads and Installs Visual Studio 2017 Community in the background (if not already installed)  

***NOTE***: There will be a couple reboots while this script runs, you will need to log in to  
resume installations. (My personal preference)  

----------------------------------------------------------
### Update to run in background after initial reboot
Update the scheduled task:  
```
$ReRunFreshStartTrigger = New-ScheduledTaskTrigger -AtStartup

Register-ScheduledTask -Action $ReRunFreshStartAction -Trigger $ReRunFreshStartTrigger -RunLevel Highest `
    -User $User -Password $Password -TaskName "ReRunFreshStart" -Description "Re-Runs FreshStart Script"
```

**Please note** you will need to add:  
```
$User = $env:UserName
$Password = "YourPassword"
```
