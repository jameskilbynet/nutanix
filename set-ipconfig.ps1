<#
.SYNOPSIS
  This script is used to deal with IP changes in DR scenarios.  It saves static IP configuration (ipconfig.csv and previous_ipconfig.csv), allows for alternative DR IP configuration (dr_ipconfig.csv) and reconfigures an active interface accordingly. The script only works if there is a single active network interface and supports only IPv4 and 2 DNS servers (no suffix or search list).
.DESCRIPTION
  This script is meant to be run at startup of a Windows machine, at which point it will list all active network interfaces (meaning they are connected).  If it finds more than one active interface, it will display an error and exit, otherwise it will continue.  If the active interface is using DHCP, it will see if there is a previously saved configuration and what was the last previous state (if any).  If there is a config file and the previous IP state is the same, if there is a DR config, it will apply it, otherwise it will reapply the static config. If the IP is static and there is no previously saved config, it will save the configuration.  It records the status every time it runs so that it can detect regular static to DR changes.  A change is triggered everytime the interface is in DHCP, and there is a saved config.  If the active interface is already using a static IP address and there is a dr_ipconfig.csv file, the script will try to ping the default gateway and apply the dr ipconfig if it does NOT ping. If the gateway still does not ping, it will revert back to the standard ipconfig.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER path
  Specify the path where you want config files and last state to be saved.  By default, this is in c:\
.EXAMPLE
  Simply run the script and save to c:\windows:
  PS> .\set-ipconfig.ps1 -path c:\windows\
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: August 24th 2016
#>

#region Parameters
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
    [parameter(mandatory = $false)] [string]$path,
	[parameter(mandatory = $false)] [switch]$saveall,
	[parameter(mandatory = $false)] [switch]$saveas,
	[parameter(mandatory = $false)] [switch]$setall,
	[parameter(mandatory = $false)] [switch]$setprod,
	[parameter(mandatory = $false)] [switch]$setdr,
	[parameter(mandatory = $false)] [switch]$set,
	[parameter(mandatory = $false)] [string]$nic
)
#endregion

#region Prep-work
# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}

#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 08/24/2016 sb   Initial release.
################################################################################
'@
$myvarScriptName = ".\set-ipconfig.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}

#initialize variables
#misc variables
$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
$myvarvCenterServers = @() #used to store the list of all the vCenter servers we must connect to
$myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
$myvarOutputLogFile += "OutputLog.log"
#endregion

#region Functions
########################
##   main functions   ##
########################

#this function is used to output log data
Function OutputLogData 
{
	#input: log category, log message
	#output: text to standard output
<#
.SYNOPSIS
  Outputs messages to the screen and/or log file.
.DESCRIPTION
  This function is used to produce screen and log output which is categorized, time stamped and color coded.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER myCategory
  This the category of message being outputed. If you want color coding, use either "INFO", "WARNING", "ERROR" or "SUM".
.PARAMETER myMessage
  This is the actual message you want to display.
.EXAMPLE
  PS> OutputLogData -mycategory "ERROR" -mymessage "You must specify a cluster name!"
#>
	param
	(
		[string] $category,
		[string] $message
	)

    begin
    {
	    $myvarDate = get-date
	    $myvarFgColor = "Gray"
	    switch ($category)
	    {
		    "INFO" {$myvarFgColor = "Green"}
		    "WARNING" {$myvarFgColor = "Yellow"}
		    "ERROR" {$myvarFgColor = "Red"}
		    "SUM" {$myvarFgColor = "Magenta"}
	    }
    }

    process
    {
	    Write-Host -ForegroundColor $myvarFgColor "$myvarDate [$category] $message"
	    if ($log) {Write-Output "$myvarDate [$category] $message" >>("$path$myvarOutputLogFile")}
    }

    end
    {
        Remove-variable category
        Remove-variable message
        Remove-variable myvarDate
        Remove-variable myvarFgColor
    }
}#end function OutputLogData
#endregion

#this function is used to output log data
Function get-ipv4 
{
	#input: interface
	#output: ipv4 configuration
<#
.SYNOPSIS
  Retrieves the IPv4 configuration of a given Windows interface.
.DESCRIPTION
  Retrieves the IPv4 configuration of a given Windows interface.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER interface
  A Windows network interface.
.EXAMPLE
  PS> get-ipv4 -interface Ethernet
#>
	param
	(
		[string] $interface
	)

    begin
    {
	    $myvarIPv4Configuration = Select-Object -Property InterfaceIndex,InterfaceAlias,IPv4Address,PrefixLength,PrefixOrigin,IPv4DefaultGateway,DNSServer
    }

    process
    {
		OutputLogData -category "INFO" -message "Getting IPv4 information for the active network interface $interface ..."
		$myvarActiveNetAdapterIP = Get-NetIPAddress -InterfaceAlias $interface | where {$_.AddressFamily -eq "IPv4"}
		$myvarActiveIPConfiguration = Get-NetIPConfiguration -InterfaceAlias $interface
		
		$myvarIPv4Configuration.InterfaceIndex = $myvarActiveNetAdapterIP.InterfaceIndex
		$myvarIPv4Configuration.InterfaceAlias = $myvarActiveNetAdapterIP.InterfaceAlias
		$myvarIPv4Configuration.IPv4Address = $myvarActiveIPConfiguration.IPv4Address
		$myvarIPv4Configuration.PrefixLength = $myvarActiveNetAdapterIP.PrefixLength
		$myvarIPv4Configuration.PrefixOrigin = $myvarActiveNetAdapterIP.PrefixOrigin
		$myvarIPv4Configuration.IPv4DefaultGateway = $myvarActiveIPConfiguration.IPv4DefaultGateway
		$myvarIPv4Configuration.DNSServer = $myvarActiveIPConfiguration.DNSServer
    }

    end
    {
       return $myvarIPv4Configuration
    }
}#end function OutputLogData
#endregion

#region Main Processing
#########################
##   main processing   ##
#########################

############################################################################
# command line arguments initialization
############################################################################	
#let's initialize parameters if they haven't been specified
if (!$path) {$path = "c:\"}
if (!$path.EndsWith("\")) {$path += "\"}

################################
##  Main execution here       ##
################################

#region Get Interfaces
#get the network interface which is connected
OutputLogData -category "INFO" -message "Retrieving the active network interface..."
$myvarActiveNetAdapter = Get-NetAdapter | where {$_.status -eq "up"} | Sort-Object -Property ifIndex #we use ifIndex to determine the order of the interfaces
#also do something if none of the interfaces are up
if (!$myvarActiveNetAdapter) {
    OutputLogData -category "ERROR" -message "There is no active network interface: cannot continue!"
    break
}#endif no active network adapter
#endregion

#region Look at IPv4 Configuration
#get the basic IPv4 information
$myvarNetAdapterIPv4Configs = @() #we'll keep all configs in this array
ForEach ($myvarNetAdapter in $myvarActiveNetAdapter) {
	$myvarNetAdapterIPv4Configs += get-ipv4 -interface $myvarNetAdpater.Name
}#end foreach NetAdapter

#endregion

#region dhcp nic
#determine if the IP configuration is obtained from DHCP or not
OutputLogData -category "INFO" -message "Checking if the active network interface has DHCP enabled..."
$myvarDHCPAdapter = Get-NetIPInterface -InterfaceAlias $myvarActiveNetAdapter.Name -AddressFamily IPv4 -Dhcp Enabled
if ($myvarDHCPAdapter) {#the active interface is configured with dhcp
    OutputLogData -category "INFO" -message "Determined the active network interface has DHCP enabled!"
    #do we have a DR configuration?
    OutputLogData -category "INFO" -message "Checking for the presence of a dr_ipconfig.csv file in $path..."
    if (Test-Path -path ($path+"dr_ipconfig.csv")) {#we have a dr_ipconfig.csv file
        OutputLogData -category "INFO" -message "Determined we have a dr_ipconfig.csv file in $path!"
        #do we have a previous state?
        OutputLogData -category "INFO" -message "Checking if we have a previous_ipconfig.csv file in $path..."
        if (Test-Path -path ($path+"previous_ipconfig.csv")) {#we do have a previous state
            OutputLogData -category "INFO" -message "Determined we have a previous_ipconfig.csv file in $path!"
            
            if (Test-Path -path ($path+"ipconfig.csv")) {#we have a ipconfig.csv file
                #compare the actual ip with the previous ip
                OutputLogData -category "INFO" -message "Comparing current state with previous state..."
            
                #reading ipconfig.csv
                $myvarNormalIPConfig = Import-Csv -path ($path+"ipconfig.csv")
                #reading previous state
                $myvarPreviousState = Import-Csv -path ($path+"previous_ipconfig.csv")
                #reading dr ipconfig
                $myvarDrIPConfig = Import-Csv -path ($path+"dr_ipconfig.csv")

                #option 1: previous state was normal, so we use DR
                if ($myvarPreviousState.IPAddress -eq $myvarNormalIPConfig.IPAddress) {
                    OutputLogData -category "INFO" -message "Previous state was normal/production, so applying DR configuration..."
                    #apply DR
                    New-NetIPAddress -InterfaceAlias $myvarActiveNetAdapter.Name -AddressFamily IPv4 -IPAddress $myvarDrIPConfig.IPAddress -PrefixLength $myvarDrIPConfig.PrefixLength -DefaultGateway $myvarDrIPConfig.IPv4DefaultGateway
                    Set-DnsClientServerAddress -InterfaceAlias $myvarActiveNetAdapter.Name -ServerAddresses ($myvarDrIPConfig.PrimaryDNSServer, $myvarDrIPConfig.SecondaryDNSServer)
                }#endif previous was normal
                #option 2: previous state was DR, so we use normal
                ElseIf ($myvarPreviousState.IPAddress -eq $myvarDrIPConfig.IPAddress) {
                    OutputLogData -category "INFO" -message "Previous state was DR, so applying normal/production configuration..."
                    #apply Normal
                    New-NetIPAddress -InterfaceAlias $myvarActiveNetAdapter.Name -AddressFamily IPv4 -IPAddress $myvarNormalIPConfig.IPAddress -PrefixLength $myvarNormalIPConfig.PrefixLength -DefaultGateway $myvarNormalIPConfig.IPv4DefaultGateway
                    Set-DnsClientServerAddress -InterfaceAlias $myvarActiveNetAdapter.Name -ServerAddresses ($myvarNormalIPConfig.PrimaryDNSServer, $myvarNormalIPConfig.SecondaryDNSServer)
                }#endElseIf previous was dr
                Else {#previous state is unknown
                    OutputLogData -category "ERROR" -message "Previous state does not match normal/production or DR and is therfore unknown: cannot continue!"
                    break
                }#endelse (previous state is unknown)

            }#endif ipconfig.csv?
            else {
                OutputLogData -category "ERROR" -message "The active network interface is using DHCP, we have a dr_config.csv and a previous_ipconfig.csv file but we don't have an ipconfig.csv file in $path. Cannot continue!"
                break
            }#endelse we have dhcp, dr config, previous state and NO ipconfig.csv

        }#endif do we have a previous state?
    }#endif dr_ipconfig.csv
    else {#we don't have a dr_ipconfig.csv file
        #do we have a saved config?
        OutputLogData -category "INFO" -message "There is no dr_ipconfig.csv file in $path. Checking now if we have an ipconfig.csv file in $path..."
        if (Test-Path -path ($path+"ipconfig.csv")) {#we have a ipconfig.csv file
            #apply the saved config
            OutputLogData -category "INFO" -message "Applying the static IP configuration from ipconfig.csv in $path..."
            #read ipconfig.csv
            $myvarSavedIPConfig = Import-Csv ($path+"ipconfig.csv")
            #apply ipconfig.csv
            New-NetIPAddress -InterfaceAlias $myvarActiveNetAdapter.Name -AddressFamily IPv4 -IPAddress $myvarSavedIPConfig.IPAddress -PrefixLength $myvarSavedIPConfig.PrefixLength -DefaultGateway $myvarSavedIPConfig.IPv4DefaultGateway
            Set-DnsClientServerAddress -InterfaceAlias $myvarActiveNetAdapter.Name -ServerAddresses ($myvarSavedIPConfig.PrimaryDNSServer, $myvarSavedIPConfig.SecondaryDNSServer)
        }#endif ipconfig.csv?
        else {
            OutputLogData -category "ERROR" -message "The active network interface is using DHCP but we don't have an ipconfig.csv file in $path. Cannot continue!"
            break
        }#endelse we have dhcp and NO ipconfig.csv
    }#endelse we don't have a dr_ipconfig.csv file
}#endif active dhcp interface
#endregion

#region NOT dhcp
else {
    #do we have a saved config?
    OutputLogData -category "INFO" -message "Active network interface already has a static IP.  Checking if we already have an ipconfig.csv file in $path..."
    if (Test-Path -path ($path+"ipconfig.csv")) {#we have a saved config
        OutputLogData -category "INFO" -message "Determined we already have an ipconfig.csv file in $path!"
        
        #reading previous state
        $myvarSavedIPConfig = Import-Csv -path ($path+"ipconfig.csv")
        
        #is it the same as current config? Also we must not have a dr file.
        OutputLogData -category "INFO" -message "Has the static IP address changed?"
        
        if (($myvarActiveNetAdapterIP.IPAddress -ne $myvarSavedIPConfig.IPAddress) -and !(Test-Path -path ($path+"dr_ipconfig.csv"))) {
            OutputLogData -category "INFO" -message "Static IP address has changed.  Updating the ipconfig.csv file in $path..."
            $myvarDNSServers = (Get-DnsClientServerAddress -AddressFamily IPv4 -InterfaceAlias $myvarActiveNetAdapter.Name).ServerAddresses
            $myvarPrimaryDNS = $myvarDNSServers[0]
            $myvarSecondaryDNS = $myvarDNSServers[1]
            $myvarIPConfig = [psCustomObject][Ordered] @{   IPAddress = $myvarActiveNetAdapterIP.IPAddress;
                                                            PrefixLength = $myvarActiveNetAdapterIP.PrefixLength;
                                                            IPv4DefaultGateway = ($myvarActiveIPConfiguration.IPv4DefaultGateway).NextHop;
                                                            PrimaryDNSServer = $myvarPrimaryDNS;
                                                            SecondaryDNSServer = $myvarSecondaryDNS
                                                        }
            $myvarIPConfig | Export-Csv -NoTypeInformation ($path+"ipconfig.csv")
        }
        

    }#endif do we have a saved config?
    else {#we don't have a saved config
        #saving the ipconfig
        OutputLogData -category "INFO" -message "Active network interface has a static IP and we don't have an ipconfig.csv file in $path! Saving to ipconfig.csv..."
        $myvarDNSServers = (Get-DnsClientServerAddress -AddressFamily IPv4 -InterfaceAlias $myvarActiveNetAdapter.Name).ServerAddresses
        $myvarPrimaryDNS = $myvarDNSServers[0]
        $myvarSecondaryDNS = $myvarDNSServers[1]
        $myvarIPConfig = [psCustomObject][Ordered] @{   IPAddress = $myvarActiveNetAdapterIP.IPAddress;
                                                        PrefixLength = $myvarActiveNetAdapterIP.PrefixLength;
                                                        IPv4DefaultGateway = ($myvarActiveIPConfiguration.IPv4DefaultGateway).NextHop;
                                                        PrimaryDNSServer = $myvarPrimaryDNS;
                                                        SecondaryDNSServer = $myvarSecondaryDNS
                                                    }
        $myvarIPConfig | Export-Csv -NoTypeInformation ($path+"ipconfig.csv")
    }
}#end else (active interface has static config)
#endregion

#region Save config
#save the current state to previous
OutputLogData -category "INFO" -message "Saving current configuration to previous state (previous_ipconfig.csv in $path)..."
$myvarActiveNetAdapterIP = Get-NetIPAddress -InterfaceAlias $myvarActiveNetAdapter.Name | where {$_.AddressFamily -eq "IPv4"}
$myvarActiveIPConfiguration = Get-NetIPConfiguration -InterfaceAlias $myvarActiveNetAdapter.Name
$myvarDNSServers = (Get-DnsClientServerAddress -AddressFamily IPv4 -InterfaceAlias $myvarActiveNetAdapter.Name).ServerAddresses
$myvarPrimaryDNS = $myvarDNSServers[0]
$myvarSecondaryDNS = $myvarDNSServers[1]
$myvarIPConfig = [psCustomObject][Ordered] @{   IPAddress = $myvarActiveNetAdapterIP.IPAddress;
                                                PrefixLength = $myvarActiveNetAdapterIP.PrefixLength;
                                                IPv4DefaultGateway = ($myvarActiveIPConfiguration.IPv4DefaultGateway).NextHop;
                                                PrimaryDNSServer = $myvarPrimaryDNS;
                                                SecondaryDNSServer = $myvarSecondaryDNS
                                            }
$myvarIPConfig | Export-Csv -NoTypeInformation ($path+"previous_ipconfig.csv")
#endregion

OutputLogData -category "INFO" -message "We're done!"
#endregion

#region Cleanup
#########################
##       cleanup       ##
#########################

#let's figure out how much time this all took
OutputLogData -category "SUM" -message "total processing time: $($myvarElapsedTime.Elapsed.ToString())"

#cleanup after ourselves and delete all custom variables
Remove-Variable myvar* -ErrorAction SilentlyContinue
Remove-Variable ErrorActionPreference -ErrorAction SilentlyContinue
Remove-Variable help -ErrorAction SilentlyContinue
Remove-Variable history -ErrorAction SilentlyContinue
Remove-Variable log -ErrorAction SilentlyContinue
Remove-Variable path -ErrorAction SilentlyContinue
Remove-Variable debugme -ErrorAction SilentlyContinue
Remove-Variable * -ErrorAction SilentlyContinue
#endregion