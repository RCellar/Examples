### General Configuration
$TaskName = "USB_Block_Alert"
$TaskPath = "\AdminControls\"

###Fail out if unable to source content
try {$ActionScript = Get-Content "PathToMonitoringScript" -Encoding UTF8 -ErrorAction Stop} #For consistency and compatibility
catch {$_;return}

###Convert to Base64 to avoid lingering flat file
$ActionScript = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($ActionScript)")) #Convert to Base64
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -EncodedCommand `"$($ActionScript)`""

###Validation logic, checks content of argument for match or existence of task, allows for dynamic task adjustment
$Validation = [Bool]($Action.Arguments -eq ((Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue).Actions).Arguments)

if (-not $Validation) {

    $LogName = "Microsoft-Windows-DeviceSetupManager/Admin" #Chosen for example, there may be other logs that have better detail data
    $EventSource = "Microsoft-Windows-DeviceSetupManager"
    $EventID = 20003 # The specific ID to trigger on

### Xpath query for Scheduled Task.  One of the only use cases where you ever really have to use Xpath.
### Herestring requires left alignment
$Subscription = @"
<QueryList>
    <Query Id="0" Path="$LogName">
    <Select Path="$LogName">
        *[System[Provider[@Name='$EventSource'] and EventID=$EventID]]
    </Select>
    </Query>
</QueryList>
"@

    ### Trigger object via New-CimInstance, since Microsoft doesn't provide cmdlet handling for this type of task trigger
    $TriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler:MSFT_TaskEventTrigger
    $Trigger = New-CimInstance -CimClass $TriggerClass -ClientOnly -Property @{Subscription=$Subscription;Enabled=$true}

    ### Encoded script action, modifications may need to be made to consider user space or system
    ### based on desired outcome (eg. user visibility or not)
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -EncodedCommand `"$($ActionScript)`""

    ### Discuss with your friendly local Cyber crew first about switches like -Hidden.  Still recommended to minimize 
    ### user confusion or interference
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden

    ### Create Scheduled Task, overwrite if not exist or fail validation
    $TaskSplat= @{TaskName=$TaskName;TaskPath=$TaskPath;Action=$Action;Trigger=$Trigger;Settings=$Settings}
    Register-ScheduledTask @TaskSplat -Description "Runs a script when a USB device is blocked by policy (Event 20003)." -Force
} else {Write-Output "Already exists"}
