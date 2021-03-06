<#
.SYNOPSIS
  This is a summary of what the script is.
.DESCRIPTION
  This is a detailed description of what the script does and how it is used.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER vcenter
  VMware vCenter server hostname. Default is localhost. You can specify several hostnames by separating entries with commas.
.EXAMPLE
  Connect to a vCenter server of your choice:
  PS> .\template.ps1 -vcenter myvcenter.local
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: June 19th 2015
#>

#region parameters
######################################
##   parameters and initial setup   ##
######################################
#let's start with some command line parsing
Param
(
    #[parameter(valuefrompipeline = $true, mandatory = $true)] [PSObject]$myParam1,
    [parameter(mandatory = $false)] [switch]$help,
    [parameter(mandatory = $false)] [switch]$history,
    [parameter(mandatory = $false)] [switch]$log,
    [parameter(mandatory = $false)] [switch]$debugme,
    [parameter(mandatory = $false)] [string]$vcenter
)
#endregion

#region functions
########################
##   main functions   ##
########################
function Write-LogOutput
{
<#
.SYNOPSIS
Outputs color coded messages to the screen and/or log file based on the category.

.DESCRIPTION
This function is used to produce screen and log output which is categorized, time stamped and color coded.

.PARAMETER Category
This the category of message being outputed. If you want color coding, use either "INFO", "WARNING", "ERROR" or "SUM".

.PARAMETER Message
This is the actual message you want to display.

.PARAMETER LogFile
If you want to log output to a file as well, use logfile to pass the log file full path name.

.NOTES
Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)

.EXAMPLE
.\Write-LogOutput -category "ERROR" -message "You must be kidding!"
Displays an error message.

.LINK
https://github.com/sbourdeaud
#>
    [CmdletBinding(DefaultParameterSetName = 'None')] #make this function advanced

	param
	(
		[Parameter(Mandatory)]
        [ValidateSet('INFO','WARNING','ERROR','SUM','SUCCESS')]
        [string]
        $Category,

        [string]
		$Message,

        [string]
        $LogFile
	)

    process
    {
        $Date = get-date #getting the date so we can timestamp the output entry
	    $FgColor = "Gray" #resetting the foreground/text color
	    switch ($Category) #we'll change the text color depending on the selected category
	    {
		    "INFO" {$FgColor = "Green"}
		    "WARNING" {$FgColor = "Yellow"}
		    "ERROR" {$FgColor = "Red"}
            "SUM" {$FgColor = "Magenta"}
            "SUCCESS" {$FgColor = "Cyan"}
	    }

	    Write-Host -ForegroundColor $FgColor "$Date [$category] $Message" #write the entry on the screen
	    if ($LogFile) #add the entry to the log file if -LogFile has been specified
        {
            Add-Content -Path $LogFile -Value "$Date [$Category] $Message"
            Write-Verbose -Message "Wrote entry to log file $LogFile" #specifying that we have written to the log file if -verbose has been specified
        }
    }

}#end function Write-LogOutput

#endregion

#region prepwork
# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}
if ($debugme) {$VerbosePreference = "Continue"}

#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 06/19/2015 sb   Initial release.
################################################################################
'@
$myvarScriptName = ".\template.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}

#check PoSH version
if ($PSVersionTable.PSVersion.Major -lt 5) {throw "$(get-date) [ERROR] Please upgrade to Powershell v5 or above (https://www.microsoft.com/en-us/download/details.aspx?id=50395)"}

#check if we have all the required PoSH modules
Write-LogOutput -Category "INFO" -LogFile $myvarOutputLogFile -Message "Checking for required Powershell modules..."

#region module sbourdeaud is used
    if (!(Get-Module -Name sbourdeaud)) 
    {#module is not loaded
        Write-LogOutput -Category "INFO" -LogFile $myvarOutputLogFile -Message "Importing module 'sbourdeaud'..."
        try
        {#try loading the module
            Import-Module -Name sbourdeaud -ErrorAction Stop
            Write-LogOutput -Category "SUCCESS" -LogFile $myvarOutputLogFile -Message "Imported module 'sbourdeaud'!"
        }
        catch 
        {#we couldn't import the module, so let's install it
            Write-LogOutput -Category "INFO" -LogFile $myvarOutputLogFile -Message "Installing module 'sbourdeaud' from the Powershell Gallery..."
            try 
            {#install
                Install-Module -Name sbourdeaud -Scope CurrentUser -ErrorAction Stop
            }
            catch 
            {#couldn't install
                Write-LogOutput -Category "ERROR" -LogFile $myvarOutputLogFile -Message "Could not install module 'sbourdeaud': $($_.Exception.Message)"
                Exit
            }

            try
            {#import
                Import-Module -Name sbourdeaud -ErrorAction Stop
                Write-LogOutput -Category "SUCCESS" -LogFile $myvarOutputLogFile -Message "Imported module 'sbourdeaud'!"
            }
            catch 
            {#we couldn't import the module
                Write-LogOutput -Category "ERROR" -LogFile $myvarOutputLogFile -Message "Unable to import the module sbourdeaud.psm1 : $($_.Exception.Message)"
                Write-LogOutput -Category "WARNING" -LogFile $myvarOutputLogFile -Message "Please download and install from https://www.powershellgallery.com/packages/sbourdeaud/1.1"
                Exit
            }
        }
    }#endif module sbourdeaud
    if (((Get-Module -Name sbourdeaud).Version.Major -le 2) -and ((Get-Module -Name sbourdeaud).Version.Minor -le 2)) 
    {
        Write-LogOutput -Category "INFO" -LogFile $myvarOutputLogFile -Message "Updating module 'sbourdeaud'..."
        try 
        {#update the module
            Update-Module -Name sbourdeaud -ErrorAction Stop
        }
        catch 
        {#couldn't update
            Write-LogOutput -Category "ERROR" -LogFile $myvarOutputLogFile -Message "Could not update module 'sbourdeaud': $($_.Exception.Message)"
            Exit
        }
    }
#endregion

#region module BetterTls
    $result = Set-PoshTls
#endregion

#region Load/Install VMware.PowerCLI
    $result = Get-PowerCLIModule
#endregion

#endregion

#region variables
#misc variables
$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
$myvarvCenterServers = @() #used to store the list of all the vCenter servers we must connect to
#endregion

#region parameters validation
############################################################################
# command line arguments initialization
############################################################################	
#let's initialize parameters if they haven't been specified
if (!$vcenter) {$vcenter = read-host "Enter vCenter server name or IP address"}#prompt for vcenter server name
$myvarvCenterServers = $vcenter.Split(",") #make sure we parse the argument in case it contains several entries
#endregion

#region processing
	################################
	##  foreach vCenter loop      ##
	################################
	foreach ($myvarvCenter in $myvarvCenterServers)	
	{
        try {
            Write-Host "$(get-date) [INFO] Connecting to vCenter server $myvarvCenter..." -ForegroundColor Green
            $myvarvCenterObject = Connect-VIServer $myvarvCenter -ErrorAction Stop
            Write-Host "$(get-date) [SUCCESS] Connected to vCenter server $myvarvCenter" -ForegroundColor Cyan
        }
        catch {throw "$(get-date) [ERROR] Could not connect to vCenter server $myvarvCenter : $($_.Exception.Message)"}

        Write-Host "$(get-date) [INFO] Disconnecting from vCenter server $vcenter..." -ForegroundColor Green
		Disconnect-viserver * -Confirm:$False #cleanup after ourselves and disconnect from vcenter
	}#end foreach vCenter
#endregion

#region cleanup
#########################
##       cleanup       ##
#########################

	#let's figure out how much time this all took
	Write-Host "$(get-date) [SUM] total processing time: $($myvarElapsedTime.Elapsed.ToString())" -ForegroundColor Magenta
	
	#cleanup after ourselves and delete all custom variables
	Remove-Variable myvar* -ErrorAction SilentlyContinue
	Remove-Variable ErrorActionPreference -ErrorAction SilentlyContinue
	Remove-Variable help -ErrorAction SilentlyContinue
    Remove-Variable history -ErrorAction SilentlyContinue
	Remove-Variable log -ErrorAction SilentlyContinue
	Remove-Variable vcenter -ErrorAction SilentlyContinue
    Remove-Variable debugme -ErrorAction SilentlyContinue
#endregion