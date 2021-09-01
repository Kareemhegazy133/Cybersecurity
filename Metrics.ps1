using Module ".\config.psm1"
<#
    .SYNOPSIS
        This script outputs a CSV file ($CSVFilePath) with all the metrics it extracts out of a SQL Server along with their description. 
        As well as another CSV file ($MetricsCSVFilePath) with the same metrics and their values. It also uses the config file to send emails about the Metrics (Warnings/Errors).
#>

function Send-Email {
    [CmdletBinding()]
    param (
        [Parameter()]
        [Config] $Config
    )
    <#
        .SYNOPSIS
            Sends an email of the Metrics that will be extracted and their simple definition
        .PARAMETER  Config
            Object that contains all configuration options
    #>
    #$Client = $Config.GetSetting($Config.CLIENT_NAME)
    $To = $Config.GetSetting($Config.ACTIONABLE_EM_DEST)
    $From = $Config.GetSetting($Config.FROM)
    $Subject = "Metrics"
    $Body = "Attached are the metrics extracted."
    $SmtpServerName = $Config.GetSetting($Config.SMTP_SERVER_NAME)
    $Port = $Config.GetSetting($Config.SMTP_PORT)
    $Attachement = $MetricsCSVFilePath

    Send-MailMessage -To $To -From $From  -Subject $Subject -Body $Body -SmtpServer $SmtpServerName -Port $Port -Attachments $Attachement
    Write-Log -Severity "Information" -Message "Emailing the Metrics"
}

function Send-EmailAlert {
    [CmdletBinding()]
    param (
        [Parameter()]
        [Config] $Config,
        [string] $Message
    )
    <#
        .SYNOPSIS
            Sends an email alert of the metrics out of boundaries
        .PARAMETER  Config
            Object that contains all configuration options
    #>
    $To = $Config.GetSetting($Config.ACTIONABLE_EM_DEST)
    $From = $Config.GetSetting($Config.FROM)
    $Subject = "Alert in the metrics"

    $SmtpServerName = $Config.GetSetting($Config.SMTP_SERVER_NAME)
    $Port = $Config.GetSetting($Config.SMTP_PORT)

    Send-MailMessage -To $To -From $From  -Subject $Subject -Body $Message -SmtpServer $SmtpServerName -Port $Port
    Write-Log -Severity "Information" -Message "Emailing the error on handling the metrics"
}

function Write-Log {
    <#
        .SYNOPSIS
            Writes an input to a log file with severity. Emails the log if the severity is high enough
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
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Severity = "Information"
    )

    $OutputPath = "$PSScriptRoot\log\log.txt"
    $MessageObj = [pscustomobject]@{
        Time     = (Get-Date -f g)
        Severity = $Severity
        Message  = $Message
    }

    #Create logging directory and file if it doesn't exist.
    if (!(Test-Path -Path $OutputPath)) {
        New-Item $OutputPath -Force
        #Recursion protection
        if (Test-Path -Path $OutputPath) {
            Write-Log -Severity "Warning" -Message "Log directory not found. Creating log directory at $OutputPath"
        }
    }

    Export-Csv -InputObject $MessageObj -Path $OutputPath -Append -NoTypeInformation

    #Send alert if the severity is high enough
    if ($Severity -eq "Error") {
        $MessageString = $MessageObj.Time + ", " + $MessageObj.Severity + ", " + $MessageObj.Message
        Send-EmailAlert -Config $Config -ComputerName $ComputerName -Message $MessageString
    }
}

function Get-Metrics {
    <#
         .SYNOPSIS
             Gets the metrics (counters) of a SQL Server and stores them into a CSV
             .PARAMETER  Config
             Object that contains all configuration options
         .PARAMETER $CSVFilePath
             The Metrics' simple description csv file output path
         .PARAMETER $MetricsCSVFilePath
             Metrics values csv file output path
     #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [Config] $Config,
        [string] $CSVFilePath,
        [string] $MetricsCSVFilePath
    )

    #Gets these counters (metrics) and stores info on them in $CSVFilePath

    #If the server is remote you can add -ComputerName $String to get counter, FAQ on the command here: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-counter?view=powershell-7.1
    #More detailed Information about the counters (Metrics) here: https://www.sentryone.com/blog/allenwhite/sql-server-performance-counters-to-monitor
    Get-Counter -ListSet 'Processor', 'Memory', 'Paging File', 'PhysicalDisk', 'System', 'Network Interface', 'SQLServer:Access Methods', 'SQLServer:Buffer Manager', 'SQLServer:General Statistics', 'SQLServer:SQL Statistics', 'SQLServer:Memory Manager' -PipelineVariable CounterCategory | 
    Select-Object -ExpandProperty Counter -PipelineVariable CounterName |
    Where-Object { $CounterName -match '(% Processor Time|Available Mbytes|% Usage|Avg. Disk sec/Read|Avg. Disk sec/Write|Processor Queue Length|Bytes total/sec|Forwarded Records/sec|Page Splits/sec|Buffer Cache Hit Ratio|Page Life Expectancy|Processes Blocked|Batch Requests/sec|SQL Compilations/sec|SQL Re-Compilations/sec|Target Server|Total|Log Pool Memory)' } | 
    Select-Object   @{E = { $CounterCategory.CounterSetName }; N = "CounterSetName" },
    @{E = { $CounterCategory.Description }; N = "Description" },
    @{E = { $CounterName }; N = "Counter" } |
    Export-Csv $CSVFilePath -NoClobber -NoTypeInformation -Append

    Write-Log -Severity "Information" -Message "Successfully exported a CSV file with all the Metrics that will be exported along with a description"

    #Imports the counters from the $CSVFilePath and gets the values and stores them into $MetricsCSVFilePath
    $Counters = (Import-Csv $CSVFilePath).counter

    Get-Counter -Counter $Counters -MaxSamples 1 | ForEach {
        $_.CounterSamples | ForEach {
            [pscustomobject]@{
                TimeStamp = $_.TimeStamp
                Path      = $_.Path
                Value     = $_.CookedValue
            }
        }
    } | Export-Csv -Path $MetricsCSVFilePath -NoTypeInformation

    Write-Log -Severity "Information" -Message "Successfully exported a CSV file with all the Metrics and their values"

    Write-Log -Severity "Information" -Message "Checking for Errors/Warnings in the metrics"

    #All the metrics names in an array
    $Names = @()
    #All the metrics values in an array (same index as $Names array)
    $Values = @()

    Import-CSV -Path $MetricsCSVFilePath | ForEach-Object {
        $Names += $_.Path
        $Values += $_.Value
    }

    for ($i = 0; $i -le ($Names.length - 1); $i += 1) {

        #Add all boundaries to metrics here in if statements, For example:

        #if($Names[$i] -like '*System\Processor Queue Length*' -and $Values[$i] > 0){
        #Send an Email alert
        #}
    }
}

Write-Log -Severity "Information" -Message "Program Started"
$Config = New-Object -TypeName Config

$CSVFilePath = "C:\Users\Administrator\Desktop\Metrics.csv"
$MetricsCSVFilePath = "C:\Users\Administrator\Desktop\FinalMetrics.csv"

Get-Metrics -Config $Config -CSVFilePath $CSVFilePath -MetricsCSVFilePath $MetricsCSVFilePath
Write-Log -Severity "Information" -Message "Program Ended"

