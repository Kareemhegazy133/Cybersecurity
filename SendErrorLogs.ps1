using Module ".\config.psm1"
<#
    .SYNOPSIS
        This script sends error logs from the client's remote computers
#>
function Create-ZipFile{
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $WantedLogsName,
        [string] $FinalLogDirectory,
         $LiteralPaths
    )
    <#
        .SYNOPSIS
            Zips the exported logs and removes the exported logs after zipping them
    #>
    Compress-Archive -LiteralPath $LiteralPaths -DestinationPath "$FinalLogDirectory\$WantedLogsName Logs.zip" -Force
    Write-Log -Severity "Information" -Message "Zipping the $WantedLogsName logs"
    Remove-Item -LiteralPath $LiteralPaths
    Write-Log -Severity "Information" -Message "Deleted the log files after zipping them at $FinalLogDirectory"
}

function Send-Email{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Config] $Config,
        [string] $WantedLogsName,
        [string] $FinalLogDirectory,
        [int] $MaxWantedLogsLevel
    )
    <#
        .SYNOPSIS
            Sends an email of the logs fetched on a remote computer
        .PARAMETER  Config
            Object that contains all configuration options
    #>
    $Client = $Config.GetSetting($Config.CLIENT_NAME)
    $To = $Config.GetSetting($Config.ACTIONABLE_EM_DEST)
    $From = $Config.GetSetting($Config.FROM)
    $Subject = $Client + ": Warning/Error/Critical Logs"
    $Body = "Attached are the logs that were level $MaxWantedLogsLevel and lower."
    $SmtpServerName = $Config.GetSetting($Config.SMTP_SERVER_NAME)
    $Port = $Config.GetSetting($Config.SMTP_PORT)
    $Attachement = "$FinalLogDirectory\$WantedLogsName Logs.zip"

    Send-MailMessage -To $To -From $From  -Subject $Subject -Body $Body -SmtpServer $SmtpServerName -Port $Port -Attachments $Attachement
    Write-Log -Severity "Information" -Message "Emailing the zip that contains the $WantedLogsName logs"
}

function Send-EmailAlert{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Config] $Config,
        [string] $Computername,
        [string] $Message
    )
    <#
        .SYNOPSIS
            Sends an email of the logs fetched on a remote computer
        .PARAMETER  Config
            Object that contains all configuration options
    #>
    $To = $Config.GetSetting($Config.ACTIONABLE_EM_DEST)
    $From = $Config.GetSetting($Config.FROM)
    $Subject = "Error Alert in the log of machine $ComputerName"

    $SmtpServerName = $Config.GetSetting($Config.SMTP_SERVER_NAME)
    $Port = $Config.GetSetting($Config.SMTP_PORT)
    

    Send-MailMessage -To $To -From $From  -Subject $Subject -Body $Message -SmtpServer $SmtpServerName -Port $Port
    Write-Log -Severity "Information" -Message "Emailing the error on handling the remote machine: $ComputerName"
}
function Get-ErrorLogs {
    [CmdletBinding()]
    param (
        [Parameter()]
        [Config] $Config,
        [string] $WantedLogsName,
        [string] $ExportLogDirectory,
        [string] $FinalLogDirectory,
        [int] $MaxWantedLogsLevel
    )
    <#
        .SYNOPSIS
            Gets the logs fetched on a remote computer
        .PARAMETER  Config
            Object that contains all configuration options
    #>

    $VaronisHostsCsv = $Config.GetSetting($Config.VARONIS_HOSTS_CSV)
    $VaronisHosts = Import-Csv $VaronisHostsCsv
    $LiteralPaths = @()
    $HostName = hostname

    foreach ($VaronisHost in $VaronisHosts){
        $ComputerName = $VaronisHost.Hosts
        $RemotePath = "$ExportLogDirectory $ComputerName - $WantedLogsName.evtx"
        #Export the logs into an evtx file and then gets it and stores it into localhost
         try{
            & wevtutil epl "$WantedLogsName" $RemotePath /q:"*[System[(Level <= $MaxWantedLogsLevel)]]" /r:$ComputerName /ow:true 2>&1
            Write-Log -Severity "Information" -Message "Exporting the $WantedLogsName log from machine: $ComputerName"
            $LiteralPaths += "$FinalLogDirectory\$ComputerName - $WantedLogsName.evtx"
            $Session = New-PSSession -ComputerName $ComputerName
            Copy-Item -Path $RemotePath -Destination "$FinalLogDirectory\$ComputerName - $WantedLogsName.evtx" -FromSession $Session
            Write-Log -Severity "Information" -Message "Copying the exported log from $ComputerName to the local machine: $HostName at ($FinalLogDirectory)"       
         }
         catch{
             "A connection to the remote matchine $ComputerName could not be established!"
             Write-Log -Severity "Error" -Message "Could not connect to $ComputerName while attempting to export the $WantedLogsName logs from machine: $ComputerName"
         }
         
    }
    Create-ZipFile -WantedLogsName $WantedLogsName -FinalLogDirectory $FinalLogDirectory -LiteralPath $LiteralPaths
}

function Write-Log {
    <#
        .SYNOPSIS
            Writes an inout to a log file with severity. Emails the log if the severity is high enough
        .PARAMETER Message
            The log message to write
        .PARAMETER Severity
            Criticality of the log message
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("Information","Warning","Error")]
        [string]$Severity = "Information"
    )

    $OutputPath = "$PSScriptRoot\log\log.txt"
    $MessageObj = [pscustomobject]@{
        Time = (Get-Date -f g)
        Severity = $Severity
        Message = $Message
    }

    #Create logging directory and file if it doesn't exist.
    if(!(Test-Path -Path $OutputPath)){
        New-Item $OutputPath -Force
        #Recursion protection
        if(Test-Path -Path $OutputPath){
            Write-Log -Severity "Warning" -Message "Log directory not found. Creating log directory at $OutputPath"
        }
    }

    Export-Csv -InputObject $MessageObj -Path $OutputPath -Append -NoTypeInformation

     #Send alert if the severity is high enough
     if($Severity -eq "Error"){
        $MessageString = $MessageObj.Time +", " + $MessageObj.Severity + ", " + $MessageObj.Message
        Send-EmailAlert -Config $Config -ComputerName $ComputerName -Message $MessageString
    }
}

Write-Log -Severity "Information" -Message "Program Started"
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$Config = New-Object -TypeName Config
#Determines the name of the log you need exported
$WantedLogsName = 'Varonis'
#Determines the "up to and including level" of logs you need exported
$MaxWantedLogsLevel = 3
#Determines the directory on the remote machines where the logs are exported from event viewer
$ExportLogDirectory  = "C:\Windows\Temp"
#Determines the directory on the local machine of where the logs are copied to and the where the zip is created
$FinalLogDirectory = (Split-Path $PSScriptRoot) + "\Reports"

Get-ErrorLogs -Config $Config -WantedLogsName $WantedLogsName -ExportLogDirectory $ExportLogDirectory -Finallogdirectory $FinalLogDirectory -MaxWantedLogsLevel $MaxWantedLogsLevel
Send-Email -Config $Config -WantedLogsName $WantedLogsName -FinalLogDirectory $FinalLogDirectory -MaxWantedLogsLevel $MaxWantedLogsLevel
Write-Log -Severity "Information" -Message "Program Ended"