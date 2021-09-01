class Config {
    [string] $ConfigPath
    [object] $Json
    [string] $FROM = "From"
    [string] $REPORT_EM_DEST = "Report_Email_Destination"
    [string] $ACTIONABLE_EM_DEST = "Actionable_Email_Destination"
    [string] $EMPTY_EM_DEST = "Empty_Email_Destination"
    [string] $ERROR_EM_DEST = "Error_Email_Destination"
    [string] $SMTP_SERVER_NAME = "Smtp_Server_Name"
    [string] $SMTP_PORT = "Smtp_Port"
    [string] $DB_NAME = "Database_Server_Name"
    [string] $SUBJECT = "Subject"
    [string] $BODY = "Body"
    [string] $CLIENT_NAME = "Client Name"
    [string] $MIN_SPACE_UNDER_TB = "Min_Space_for_disk_less_than_1_terabite"
    [string] $MIN_SPACE_OVER_TB = "Min_Space_for_disk_greater_than_1_terabite"
    [string] $CSV_EXPORT_PATH = "Csv_Export_Path"
    [string] $VARONIS_HOSTS_CSV = "Varonis_Hosts_Csv"
    [string] $SERVICE_LIST_CSV= "Service_List_Csv"
    [string] $SERVER_LIST_CSV= "Server_List_Csv"

    Config(){
        $this.ConfigPath = ".\config.json"
        $this.Json = Get-Content $this.ConfigPath | Out-String | ConvertFrom-Json
    }
    

    Config([string] $ConfigPath){
        $this.ConfigPath = $ConfigPath
        $this.Json = Get-Content $this.ConfigPath | Out-String | ConvertFrom-Json
    }

    
    [object] GetSetting($SettingName){
        return $this.Json.$SettingName
    }
}

