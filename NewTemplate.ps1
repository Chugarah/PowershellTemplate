<#
.Synopsis
 This script will create a new template file (.ps1t) in the template repository ( defined in Preferences.ps1 ).
 Please keep it in this place when editing so it can be find by NewScriptFromTemplate function
.Description
 A template containing predefined placeholders will be created, the goal is to improve script consistency among your organisation scripters.
.Parameter name
 Name of the template to create 
.Parameter force
 Allow overwrite of existing template
.Example
 PS>NewTemplate.ps1 MyfirstTemplate
  Will create a MyFirstTemplate.ps1t file in the template repository
.Example
 PS>NewTemplate.ps1 MyfirstTemplate -force
 Will create a MyFirstTemplate.ps1t file in the template repository, overwriting previous version
.Link
 https://github.com/kayasax/PowershellTemplate
.Notes
#>

[CmdletBinding()] #make script react as cmdlet (-verbose etc..)
param(
    [Parameter(Position=0, Mandatory=$true,ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $name,
    [switch]$force
)

# ERROR HANDLING
$ErrorActionPreference="STOP" # make all errors terminating ones so they can be catch
$EmailAlert=$false # set to $true if you want to send fatal error by mail
$EventLogAlert=$false # set to $true if you want to log the fatal error in Application EventLog
$to="recipient@domain.tld" # email recipients  you can use several addresses like this "user1@dom.com","user2@dom.com"  
$description="Template generation script" #The description will be use in the mail subject if email alert is enable

# PRIVATE VARIABLES DON'T TOUCH
###################
$_ScriptFullName=$MyInvocation.myCommand.definition
$_ScriptName=Split-Path -Leaf $_ScriptFullName
$_ScriptPath=split-path -Parent   $_ScriptFullName
$_HostFQDN=[System.Net.Dns]::GetHostEntry([string]$Env:computername).HostName

try{
    $TemplateVersion="0.1"
    # Load preferences
    . "$_ScriptPath\preferences.ps1"

    $TemplatePath=join-path "$_TemplateRepository" -childpath "$name.ps1t"
    if( (test-path $TemplatePath) -and ($force -ne $true) ){
        Throw "Template $TemplatePath allready exists, please use -force parameter to overwrite it"
    } 

    $TemplateContent=@'
<# 
.Synopsis
    Brief description
.Description
    details of the script
.Parameter param1 
    describe param1
.Parameter param2
    describe param2
.Example
    Give sample usage of your script
.Link
    URI of usefull site 
.Notes
    You can add several informations here

'@

    $TemplateContent +=@"
    Changelog:
    * 
"@
    $TemplateContent+="$(get-date -format  'yyyy/MM/dd HH:mm') Template generated by $Env:USERNAME with NewTemplate.ps1 V $TemplateVersion`n"
    $TemplateContent+=@"
#>`n`n`n
"@
    
    $TemplateContent |Out-File $TemplatePath 
    $ParamBlock= # Give sample parameters to scripters
    @'
[CmdletBinding()] #make script react as cmdlet (-verbose etc..)
param(
    <# Sample parameters

    [Parameter(Position=0, Mandatory=$true,ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $service,

    [Parameter(Position=1)]
    [System.string]
    $computername='local'

    
    Validation  examples : 
    Param( 
        [ValidateSet('Tom','Dick','Jane')]  #choice list
        [String] 
        $Name , 
        [ValidateRange(21,65)] # range
        [Int] 
        $Age , 
        [ValidateScript({Test-Path $_ -PathType 'Container'})]  #validate an existing directory
        [string] 
        $Path 
    )
    #>
)
'@ 
    $ParamBlock |Out-File $TemplatePath -Append
    $ScriptBody=@"
# ERROR HANDLING
# Choose your environment : DEV while testing your code or PROD in production 
# This will permit to create custom repsonse to fatal errors 
$Env="DEV" 
$ErrorActionPreference='STOP' # make all errors terminating ones so they can be catch
$EmailAlert=$false # set it to $true if you want to send fatal error by email
$EventLogAlert=$false # set to $true if you want to log the fatal error in Application EventLog
$to='user@domain.tld' # email recipients  you can use several addresses like this 'user1@dom.com','user2@dom.com'  
$description='Describe the script main object' #The description will be use in the email subject if $EmailAlert is enable

if( $EventLogAlert){
    if($Env -eq 'PROD'){
        $EventSource=$_PRODSource
    }
    else{
        if ($Env -ne 'DEV'){
            log "Warning the environment $Env is unknow, failing back to DEV mode"
        }
        $EventSource = $_DEVSource
    }

    # Check if Source exists in event logs otherwise, add it
    # Ref: http://msdn.microsoft.com/en-us/library/system.diagnostics.eventlog.sourceexists(v=vs.110).aspx

    if (! ([System.Diagnostics.EventLog]::SourceExists($EventSource))){
        NewEventLog -LogName application -Source "$EventSource"
    }
}

# !!! PRIVATE VARIABLES DON'T TOUCH !!!
###################
$_ScriptFullName=$MyInvocation.myCommand.definition
$_ScriptName=Split-Path -Leaf $_ScriptFullName
$_ScriptPath=split-path -Parent   $_ScriptFullName
$_HostFQDN=[System.Net.Dns]::GetHostEntry([string]$Env:computername).HostName

# !!! PUT YOUR VARIABLES HERE !!!
###################


try{
    # You can include existing functions from the function repository (defined in Preferences.ps1) like this :
    # <include path/to/function.ps1> 
    # Example :  
    # the <include ...> line will be replaced by the function.ps1 content when script will be generate using the NewScriptFromTemplate script

    # !!! INCLUDE FUNCTIONS FROM REPOSITORY HERE !!! (log function is included by default) 
    <include logging/log.ps1>
    <include logging/New-ApplicationEvent.ps1>

    # !!! WRITE YOUR CODE HERE !!!
    log "`n******************************************`nInfo : script is starting`n******************************************"
    
}
catch{
    $_ # echo the exception
    $message="Error : $description ($_ScriptFullName)" # subject of mails 

    # MAIL
    if ($EmailAlert){
        
        $from="$_HostFQDN" # sender
        send-mailmessage -SmtpServer $_SMTPServer  -encoding $_enc -subject $message -bodyasHTML  "$($_.Exception.message )<br/><br/> $($_.ScriptStackTrace) " -to $to -from $from #-attachments $logdir\trace2.txt
    }
    
    # EVENTLOG
    if ($EventLogAlert){
       
        $msg=New message from $(whoami) invoked from $($MyInvocation.ScriptName) :`n"+$message+"`n"+$($_.Exception.Message)+"`n"+$($_.ScriptStackTrace |out-string)
        log $msg
 
        # Create event in application eventlog
        Write-EventLog application -EntryType error -Source $EventSource -eventID 1 -Message $msg
    }
    Log "Error, script did not terminate normaly"
    return 1
}

finally{
    log "Success script ended normally"
    if ($EventLogAlert){
        Write-EventLog application -EntryType Information -Source $EventSource -eventID 0 -Message "Success Script ended normally"
    }
    return 0
}

"@    

    $scriptBody |Out-File $TemplatePath -Append
    log "Template successfully created in $Templatepath"
    
}
catch{
    
    log $_
    # MAIL
    
    $message="Error : $description ($_ScriptFullName)" # subject of mails
    $from="$_HostFQDN" # sender
    if ($EmailAlert){
        send-mailmessage -SmtpServer $SMTPServer -encoding $_enc -subject $message -bodyasHTML  "$($_.Exception.message )<br/><br/> $($_.ScriptStackTrace) " -to $to -from $from #-attachments $logdir\trace2.txt
    }

    # Create event in application eventlog
    $msg=$message+"`n"+$($_.Exception.Message)+"`n"+$($_.ScriptStackTrace)

    if($Env -eq "PROD"){
        $EventSource='SPEIG_POWERSHELL'
    }
    else{
        if ($Env -ne "DEV"){
            log "Warning the environement $dev is unknow, failback to DEV mode"
        }
        $EventSource = 'SPEIG_DEV'
    }
    
    # Check if Source exists in event logs otherwise, add it
    # Ref: http://msdn.microsoft.com/en-us/library/system.diagnostics.eventlog.sourceexists(v=vs.110).aspx

    if (! ([System.Diagnostics.EventLog]::SourceExists($EventSource))){
        new-eventlog -LogName application -Source "$EventSource"
    }
    
    Write-EventLog application -EntryType error -Source $EventSource -eventID 2 -Message $msg
    Log "Error, script did not terminate normaly"
    return 1
}





