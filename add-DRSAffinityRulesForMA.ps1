<#
.SYNOPSIS
  This script is used to create DRS affinity groups and rules based on the Nutanix Metro Availability setup of a vSphere cluster.
.DESCRIPTION
  The script will look at the Metro Availability setup for a pair of given Nutanix clusters and will create DRS affinity groups and rules so that VMs will run on hosts which hold the active copy of a given replicated datastore. This is to avoid I/O going over two sites in normal conditions.  If DRS groups and rules already exist that match the naming convention used in this script, then it will update those groups and rules (unless you use the -noruleupdate switch in which case only groups will be updated).  This script requires having both the Nutanix cmdlets and PowerCLI installed.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER ntnx_cluster1
  First Nutanix cluster fully qualified domain name or IP address.
.PARAMETER ntnx_cluster2
  Second Nutanix cluster fully qualified domain name or IP address.
.PARAMETER username
  Username used to connect to the Nutanix clusters.
.PARAMETER password
  Password used to connect to the Nutanix clusters.
.PARAMETER vcenter
  Hostname or IP address of the vCenter Server.
.PARAMETER noruleupdate
  Use this switch if you do NOT want to update DRS rules. Only groups will be updated. This can be useful when using the script within the context of a failback.
.PARAMETER prismCreds
  Specifies a custom credentials file name (will look for %USERPROFILE\Documents\WindowsPowerShell\CustomCredentials\$prismCreds.txt). These credentials can be created using the Powershell command 'Set-CustomCredentials -credname <credentials name>'. See https://blog.kloud.com.au/2016/04/21/using-saved-credentials-securely-in-powershell-scripts/ for more details.
.EXAMPLE
  Create DRS affinity groups and rules for ntnxc1 and ntnxc2 on vcenter1:
  PS> .\add-DRSAffinityRulesForMA.ps1 -ntnx_cluster1 ntnxc1.local -ntnx_cluster2 ntnxc2.local -username admin -password nutanix/4u -vcenter vcenter1.local
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: July 18th 2018
#>

#region A - parameters
Param
(
    #[parameter(valuefrompipeline = $true, mandatory = $true)] [PSObject]$myParam1,
    [parameter(mandatory = $false)] [switch]$help,
    [parameter(mandatory = $false)] [switch]$history,
    [parameter(mandatory = $false)] [switch]$log,
    [parameter(mandatory = $false)] [switch]$debugme,
    [parameter(mandatory = $false)] [string]$ntnx_cluster1,
	[parameter(mandatory = $false)] [string]$ntnx_cluster2,
    [parameter(mandatory = $false)] [string]$username,
    [parameter(mandatory = $false)] [string]$password,
    [parameter(mandatory = $false)] [string]$vcenter,
    [parameter(mandatory = $false)] $prismCreds,
    [parameter(mandatory = $false)] [switch]$noruleupdate
)
#endregion

#region B - functions
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
	    if ($log) {Write-Output "$myvarDate [$category] $message" >>$myvarOutputLogFile}
    }

    end
    {
        Remove-variable category
        Remove-variable message
        Remove-variable myvarDate
        Remove-variable myvarFgColor
    }
}#end function OutputLogData

#this function is used to create a DRS host group
Function New-DrsHostGroup
{
<#
.SYNOPSIS
  Creates a new DRS host group
.DESCRIPTION
  This function creates a new DRS host group in the DRS Group Manager
.NOTES
  Author: Arnim van Lieshout
.PARAMETER VMHost
  The hosts to add to the group. Supports objects from the pipeline.
.PARAMETER Cluster
  The cluster to create the new group on.
.PARAMETER Name
  The name for the new group.
.EXAMPLE
  PS> Get-VMHost ESX001,ESX002 | New-DrsHostGroup -Name "HostGroup01" -Cluster CL01
.EXAMPLE
  PS> New-DrsHostGroup -Host ESX001,ESX002 -Name "HostGroup01" -Cluster (Get-CLuster CL01)
#>

    Param(
        [parameter(valuefrompipeline = $true, mandatory = $true,
        HelpMessage = "Enter a host entity")]
            [PSObject]$VMHost,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a cluster entity")]
            [PSObject]$Cluster,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a name for the group")]
            [String]$Name)

    begin {
        switch ($Cluster.gettype().name) {
            "String" {$cluster = Get-Cluster $cluster | Get-View}
            "ClusterImpl" {$cluster = $cluster | Get-View}
            "Cluster" {}
            default {throw "No valid type for parameter -Cluster specified"}
        }
        $spec = New-Object VMware.Vim.ClusterConfigSpecEx
        $group = New-Object VMware.Vim.ClusterGroupSpec
        $group.operation = "add"
        $group.Info = New-Object VMware.Vim.ClusterHostGroup
        $group.Info.Name = $Name
    }

    Process {
        switch ($VMHost.gettype().name) {
            "String[]" {Get-VMHost -Name $VMHost | ForEach-Object {$group.Info.Host += $_.Extensiondata.MoRef}}
            "String" {Get-VMHost -Name $VMHost | ForEach-Object {$group.Info.Host += $_.Extensiondata.MoRef}}
            "VMHostImpl" {$group.Info.Host += $VMHost.Extensiondata.MoRef}
            "HostSystem" {$group.Info.Host += $VMHost.MoRef}
            default {throw "No valid type for parameter -VMHost specified"}
        }
    }

    End {
        if ($group.Info.Host) {
            $spec.GroupSpec += $group
            $cluster.ReconfigureComputeResource_Task($spec,$true) | Out-Null
        }
        else {
            throw "No valid hosts specified"
        }
    }
}

#this function is used to create a DRS VM group
Function New-DrsVmGroup
{
<#
.SYNOPSIS
  Creates a new DRS VM group
.DESCRIPTION
  This function creates a new DRS VM group in the DRS Group Manager
.NOTES
  Author: Arnim van Lieshout
.PARAMETER VM
  The VMs to add to the group. Supports objects from the pipeline.
.PARAMETER Cluster
  The cluster to create the new group on.
.PARAMETER Name
  The name for the new group.
.EXAMPLE
  PS> Get-VM VM001,VM002 | New-DrsVmGroup -Name "VmGroup01" -Cluster CL01
.EXAMPLE
  PS> New-DrsVmGroup -VM VM001,VM002 -Name "VmGroup01" -Cluster (Get-CLuster CL01)
#>

    Param(
        [parameter(valuefrompipeline = $true, mandatory = $true,
        HelpMessage = "Enter a vm entity")]
            [PSObject]$VM,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a cluster entity")]
            [PSObject]$Cluster,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a name for the group")]
            [String]$Name)

    begin {
        switch ($Cluster.gettype().name) {
            "String" {$cluster = Get-Cluster $cluster | Get-View}
            "ClusterImpl" {$cluster = $cluster | Get-View}
            "Cluster" {}
            default {throw "No valid type for parameter -Cluster specified"}
        }
        $spec = New-Object VMware.Vim.ClusterConfigSpecEx
        $group = New-Object VMware.Vim.ClusterGroupSpec
        $group.operation = "add"
        $group.Info = New-Object VMware.Vim.ClusterVmGroup
        $group.Info.Name = $Name
    }

    Process {
        switch ($VM.gettype().name) {
            "String[]" {Get-VM -Name $VM | ForEach-Object {$group.Info.VM += $_.Extensiondata.MoRef}}
            "String" {Get-VM -Name $VM | ForEach-Object {$group.Info.VM += $_.Extensiondata.MoRef}}
            "VirtualMachineImpl" {$group.Info.VM += $VM.Extensiondata.MoRef}
            "VirtualMachine" {$group.Info.VM += $VM.MoRef}
            default {throw "No valid type for parameter -VM specified"}
        }
    }

    End {
        if ($group.Info.VM) {
            $spec.GroupSpec += $group
            $cluster.ReconfigureComputeResource_Task($spec,$true) | Out-Null
        }
        else {
            throw "No valid VMs specified"
        }
    }
}

#this function is used to create a VM to host DRS rule
Function New-DRSVMToHostRule
{
<#
.SYNOPSIS
  Creates a new DRS VM to host rule
.DESCRIPTION
  This function creates a new DRS vm to host rule
.NOTES
  Author: Arnim van Lieshout
.PARAMETER VMGroup
  The VMGroup name to include in the rule.
.PARAMETER HostGroup
  The VMHostGroup name to include in the rule.
.PARAMETER Cluster
  The cluster to create the new rule on.
.PARAMETER Name
  The name for the new rule.
.PARAMETER AntiAffine
  Switch to make the rule an AntiAffine rule. Default rule type is Affine.
.PARAMETER Mandatory
  Switch to make the rule mandatory (Must run rule). Default rule is not mandatory (Should run rule)
.EXAMPLE
  PS> New-DrsVMToHostRule -VMGroup "VMGroup01" -HostGroup "HostGroup01" -Name "VMToHostRule01" -Cluster CL01 -AntiAffine -Mandatory
#>

    Param(
        [parameter(mandatory = $true,
        HelpMessage = "Enter a VM DRS group name")]
            [String]$VMGroup,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a host DRS group name")]
            [String]$HostGroup,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a cluster entity")]
            [PSObject]$Cluster,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a name for the group")]
            [String]$Name,
            [Switch]$AntiAffine,
            [Switch]$Mandatory)

    switch ($Cluster.gettype().name) {
        "String" {$cluster = Get-Cluster $cluster | Get-View}
        "ClusterImpl" {$cluster = $cluster | Get-View}
        "Cluster" {}
        default {throw "No valid type for parameter -Cluster specified"}
    }

    $spec = New-Object VMware.Vim.ClusterConfigSpecEx
    $rule = New-Object VMware.Vim.ClusterRuleSpec
    $rule.operation = "add"
    $rule.info = New-Object VMware.Vim.ClusterVmHostRuleInfo
    $rule.info.enabled = $true
    $rule.info.name = $Name
    $rule.info.mandatory = $Mandatory
    $rule.info.vmGroupName = $VMGroup
    if ($AntiAffine) {
        $rule.info.antiAffineHostGroupName = $HostGroup
    }
    else {
        $rule.info.affineHostGroupName = $HostGroup
    }
    $spec.RulesSpec += $rule
    $cluster.ReconfigureComputeResource_Task($spec,$true) | Out-Null
}

#this function is used to edit an existing DRS rule
Function Update-DrsVMGroup
{
<#
.SYNOPSIS
Update DRS VM group with a new collection of VM´s

.DESCRIPTION
Use this function to update the ClusterVMgroup with VMs that are sent in by parameters

.PARAMETER  xyz

.NOTES
Author: Niklas Akerlund / RTS (most of the code came from http://communities.vmware.com/message/1667279 @LucD22 and GotMoo)
Date: 2012-06-28
#>
	param
    (
	    $cluster,
	    $VMs,
	    $groupVMName
    )

    $cluster = Get-Cluster $cluster
    $spec = New-Object VMware.Vim.ClusterConfigSpecEx
    $groupVM = New-Object VMware.Vim.ClusterGroupSpec
    #Operation edit will replace the contents of the GroupVMName with the new contents seleced below.
    $groupVM.operation = "edit"

    $groupVM.Info = New-Object VMware.Vim.ClusterVmGroup
    $groupVM.Info.Name = $groupVMName

    Get-VM $VMs | ForEach-Object {$groupVM.Info.VM += $_.Extensiondata.MoRef}
    $spec.GroupSpec += $groupVM

    #Apply the settings to the cluster
    $cluster.ExtensionData.ReconfigureComputeResource($spec,$true)
}

#this function is used to edit an existing DRS rule
Function Update-DrsHostGroup
{
<#
.SYNOPSIS
Update DRS Host group with a new collection of Hosts

.DESCRIPTION
Use this function to update the ClusterHostgroup with Hosts that are sent in by parameters

.PARAMETER  xyz

.NOTES
Author: Niklas Akerlund / RTS (most of the code came from http://communities.vmware.com/message/1667279 @LucD22 and GotMoo)
Date: 2012-06-28
#>
	param
    (
	    $cluster,
	    $Hosts,
	    $groupHostName
    )

    $cluster = Get-Cluster $cluster
    $spec = New-Object VMware.Vim.ClusterConfigSpecEx
    $groupHost = New-Object VMware.Vim.ClusterGroupSpec
    #Operation edit will replace the contents of the GroupVMName with the new contents seleced below.
    $groupHost.operation = "edit"

    $groupHost.Info = New-Object VMware.Vim.ClusterHostGroup
    $groupHost.Info.Name = $groupHostName

    Get-VMHost $Hosts | ForEach-Object {$groupHost.Info.Host += $_.Extensiondata.MoRef}
    $spec.GroupSpec += $groupHost

    #Apply the settings to the cluster
    $cluster.ExtensionData.ReconfigureComputeResource($spec,$true)
}

#this function is used to create a VM to host DRS rule
Function Update-DRSVMToHostRule
{
<#
.SYNOPSIS
  Creates a new DRS VM to host rule
.DESCRIPTION
  This function creates a new DRS vm to host rule
.NOTES
  Author: Arnim van Lieshout
.PARAMETER VMGroup
  The VMGroup name to include in the rule.
.PARAMETER HostGroup
  The VMHostGroup name to include in the rule.
.PARAMETER Cluster
  The cluster to create the new rule on.
.PARAMETER Name
  The name for the new rule.
.PARAMETER AntiAffine
  Switch to make the rule an AntiAffine rule. Default rule type is Affine.
.PARAMETER Mandatory
  Switch to make the rule mandatory (Must run rule). Default rule is not mandatory (Should run rule)
.EXAMPLE
  PS> New-DrsVMToHostRule -VMGroup "VMGroup01" -HostGroup "HostGroup01" -Name "VMToHostRule01" -Cluster CL01 -AntiAffine -Mandatory
#>

    Param(
        [parameter(mandatory = $true,
        HelpMessage = "Enter a VM DRS group name")]
            [String]$VMGroup,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a DRS rule key")]
            [String]$RuleKey,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a DRS rule uuid")]
            [String]$RuleUuid,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a host DRS group name")]
            [String]$HostGroup,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a cluster entity")]
            [PSObject]$Cluster,
        [parameter(mandatory = $true,
        HelpMessage = "Enter a name for the group")]
            [String]$Name,
            [Switch]$AntiAffine,
            [Switch]$Mandatory)

    switch ($Cluster.gettype().name) {
        "String" {$cluster = Get-Cluster $cluster | Get-View}
        "ClusterImpl" {$cluster = $cluster | Get-View}
        "Cluster" {}
        default {throw "No valid type for parameter -Cluster specified"}
    }

    $spec = New-Object VMware.Vim.ClusterConfigSpecEx
    $rule = New-Object VMware.Vim.ClusterRuleSpec
    $rule.operation = "edit"
    $rule.info = New-Object VMware.Vim.ClusterVmHostRuleInfo
    $rule.info.enabled = $true
    $rule.info.name = $Name
    $rule.info.mandatory = $Mandatory
    $rule.info.vmGroupName = $VMGroup
    $rule.info.Key = $RuleKey
    $rule.info.RuleUuid = $RuleUuid
    if ($AntiAffine) {
        $rule.info.antiAffineHostGroupName = $HostGroup
    }
    else {
        $rule.info.affineHostGroupName = $HostGroup
    }
    $spec.RulesSpec += $rule
    $cluster.ReconfigureComputeResource_Task($spec,$true) | Out-Null
}
#endregion

#region C - prepwork
    #region C1 - misc preparation
        # get rid of annoying error messages
        #if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}
#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 10/06/2015 sb   Initial release.
 06/21/2016 sb   Updated code to support refresh of existing rules as well as
                 partial groups and rules creation.  Changed default groups and
                 rule naming to simplify them.  Added the -noruleupdate switch.
 09/15/2016 sb   Changed password input to secure string
 06/05/2018 sb   Updated script to use REST API instead of NTNX cmdlets
 06/27/2018 sb   Added BetterTls module for Tls 1.2
 07/17/2018 sb   Added check for PoSH version and removed silentlycontinue as
                 default for erroractionpreference
 10/26/2018 sb   Added additional error control.
################################################################################
'@
        $myvarScriptName = ".\add-DRSAffinityRulesForMA.ps1"

        if ($help) 
        {
            get-help $myvarScriptName
            exit
        }
        if ($History) {
        $HistoryText
        exit
    }

    
        if ($PSVersionTable.PSVersion.Major -lt 5) 
        {#check PoSH version
            throw "$(get-date) [ERROR] Please upgrade to Powershell v5 or above (https://www.microsoft.com/en-us/download/details.aspx?id=50395)"
        }
    #endregion

    #check if we have all the required PoSH modules
    Write-Host "$(get-date) [INFO] Checking for required Powershell modules..." -ForegroundColor Green

    #region C2 - module BetterTls
        if (!(Get-Module -Name BetterTls)) {
            Write-Host "$(get-date) [INFO] Importing module 'BetterTls'..." -ForegroundColor Green
            try
            {
                Import-Module -Name BetterTls -ErrorAction Stop
                Write-Host "$(get-date) [SUCCESS] Imported module 'BetterTls'!" -ForegroundColor Cyan
            }#end try
            catch #we couldn't import the module, so let's install it
            {
                Write-Host "$(get-date) [INFO] Installing module 'BetterTls' from the Powershell Gallery..." -ForegroundColor Green
                try {Install-Module -Name BetterTls -Scope CurrentUser -ErrorAction Stop}
                catch {throw "$(get-date) [ERROR] Could not install module 'BetterTls': $($_.Exception.Message)"}

                try
                {
                    Import-Module -Name BetterTls -ErrorAction Stop
                    Write-Host "$(get-date) [SUCCESS] Imported module 'BetterTls'!" -ForegroundColor Cyan
                }#end try
                catch #we couldn't import the module
                {
                    Write-Host "$(get-date) [ERROR] Unable to import the module BetterTls : $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "$(get-date) [WARNING] Please download and install from https://www.powershellgallery.com/packages/BetterTls/0.1.0.0" -ForegroundColor Yellow
                    Exit
                }#end catch
            }#end catch
        }
        Write-Host "$(get-date) [INFO] Disabling Tls..." -ForegroundColor Green
        try {Disable-Tls -Tls -Confirm:$false -ErrorAction Stop} catch {throw "$(get-date) [ERROR] Could not disable Tls : $($_.Exception.Message)"}
        Write-Host "$(get-date) [INFO] Enabling Tls 1.2..." -ForegroundColor Green
        try {Enable-Tls -Tls12 -Confirm:$false -ErrorAction Stop} catch {throw "$(get-date) [ERROR] Could not enable Tls 1.2 : $($_.Exception.Message)"}
    #endregion

    #region C3 - module sbourdeaud is used for facilitating Prism REST calls
        if (!(Get-Module -Name sbourdeaud)) 
        {#module sbourdeaud is not loaded...
            Write-Host "$(get-date) [INFO] Importing module 'sbourdeaud'..." -ForegroundColor Green
            try
            {#importing module sbourdeaud
                Import-Module -Name sbourdeaud -ErrorAction Stop
                Write-Host "$(get-date) [SUCCESS] Imported module 'sbourdeaud'!" -ForegroundColor Cyan
            }#end try
            catch 
            {#we couldn't import the module, so let's install it
                Write-Host "$(get-date) [INFO] Installing module 'sbourdeaud' from the Powershell Gallery..." -ForegroundColor Green
                try 
                {#installing module sbourdeaud for the current user
                    Install-Module -Name sbourdeaud -Scope CurrentUser -ErrorAction Stop
                }
                catch 
                {#couldn't install module sbourdeaud
                    throw "$(get-date) [ERROR] Could not install module 'sbourdeaud': $($_.Exception.Message)"
                }

                try
                {#trying again to import module sbourdeaud
                    Import-Module -Name sbourdeaud -ErrorAction Stop
                    Write-Host "$(get-date) [SUCCESS] Imported module 'sbourdeaud'!" -ForegroundColor Cyan
                }#end try
                catch 
                {#we couldn't import the module
                    Write-Host "$(get-date) [ERROR] Unable to import the module sbourdeaud.psm1 : $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "$(get-date) [WARNING] Please download and install from https://www.powershellgallery.com/packages/sbourdeaud" -ForegroundColor Yellow
                    Exit
                }#end catch
            }#end catch
        }#endif module sbourdeaud
        if (((Get-Module -Name sbourdeaud).Version.Major -le 1) -and ((Get-Module -Name sbourdeaud).Version.Minor -le 1)) 
        {#check the version of module sbourdeaud
            Write-Host "$(get-date) [INFO] Updating module 'sbourdeaud'..." -ForegroundColor Green
            try 
            {#updating module sbourdeaud
                Update-Module -Name sbourdeaud -Scope CurrentUser -ErrorAction Stop
            }
            catch 
            {#we couldn't update module sbourdeaud
                throw "$(get-date) [ERROR] Could not update module 'sbourdeaud': $($_.Exception.Message)"
            }
        }
    #endregion

    #region C4 - Load/Install VMware.PowerCLI
        if (!(Get-Module VMware.PowerCLI)) 
        {#module VMware.PowerCLI is not loaded
            try 
            {#load module VMware.PowerCLI
                Write-Host "$(get-date) [INFO] Loading VMware.PowerCLI module..." -ForegroundColor Green
                Import-Module VMware.PowerCLI -ErrorAction Stop
                Write-Host "$(get-date) [SUCCESS] Loaded VMware.PowerCLI module" -ForegroundColor Cyan
            }
            catch 
            {#couldn't load module VMware.PowerCLI
                Write-Host "$(get-date) [WARNING] Could not load VMware.PowerCLI module!" -ForegroundColor Yellow
                try 
                {#install module VMware.PowerCLI
                    Write-Host "$(get-date) [INFO] Installing VMware.PowerCLI module..." -ForegroundColor Green
                    Install-Module -Name VMware.PowerCLI -Scope CurrentUser -ErrorAction Stop
                    Write-Host "$(get-date) [SUCCESS] Installed VMware.PowerCLI module" -ForegroundColor Cyan
                    try 
                    {#loading module VMware.PowerCLI
                        Write-Host "$(get-date) [INFO] Loading VMware.PowerCLI module..." -ForegroundColor Green
                        Import-Module VMware.VimAutomation.Core -ErrorAction Stop
                        Write-Host "$(get-date) [SUCCESS] Loaded VMware.PowerCLI module" -ForegroundColor Cyan
                    }
                    catch 
                    {#couldn't load module VMware.PowerCLI
                        throw "$(get-date) [ERROR] Could not load the VMware.PowerCLI module : $($_.Exception.Message)"
                    }
                }
                catch 
                {#couldn't install module VMware.PowerCLI
                    throw "$(get-date) [ERROR] Could not install the VMware.PowerCLI module. Install it manually from https://www.powershellgallery.com/items?q=powercli&x=0&y=0 : $($_.Exception.Message)"
                }
            }
        }
        
        if ((Get-Module -Name VMware.VimAutomation.Core).Version.Major -lt 10) 
        {#check PowerCLI version
            try 
            {#update module VMware.PowerCLI
                Update-Module -Name VMware.PowerCLI -ErrorAction Stop
            } 
            catch 
            {#couldn't update module VMware.PowerCLI
                throw "$(get-date) [ERROR] Could not update the VMware.PowerCLI module : $($_.Exception.Message)"
            }
        }
    #endregion

    #region C5 - get ready to use the Nutanix REST API
#Accept self signed certs
if (!$IsLinux) {
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
#we also need to use the proper encryption protocols
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol =  [System.Security.Authentication.SslProtocols] "tls12"
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}
    #endregion

    #region C6 - set some runtime variables
        $myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
        $myvarvCenterServers = @() #used to store the list of all the vCenter servers we must connect to
        $myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
        $myvarOutputLogFile += "OutputLog.log"

        #* CUSTOMIZATION: if you want to edit the object names, check out the section below
        $myvarNutanixCluster_1_HostGroupName = "DRS_HG_MA_" + $ntnx_cluster1
        $myvarNutanixCluster_2_HostGroupName = "DRS_HG_MA_" + $ntnx_cluster2
        #! for vm group names, search for multiple instances of $myvarDRSVMGroupName =
        #! for DRS rule names, search for multiple instances of $myvarDRSRuleName =
    #endregion

#endregion

#region D - parameters validation	
    if (!$vcenter) 
    {#prompt for vcenter server name
        $vcenter = read-host "Enter vCenter server name or IP address"
    }
	$myvarvCenterServers = $vcenter.Split(",") #make sure we parse the argument in case it contains several entries
    
    if (!$ntnx_cluster1) 
    {#prompt for the first Nutanix cluster name
        $ntnx_cluster1 = read-host "Enter the hostname or IP address of the first Nutanix cluster"
    }
    if (!$ntnx_cluster2) 
    {#prompt for the second Nutanix cluster name
        $ntnx_cluster2 = read-host "Enter the hostname or IP address of the second Nutanix cluster"
    }
    
    if (!$prismCreds) 
    {#we are not using custom credentials, so let's ask for a username and password if they have not already been specified
        if (!$username) 
        {#if Prism username has not been specified ask for it
            $username = Read-Host "Enter the Prism username"
        } 

        if (!$password) 
        {#if password was not passed as an argument, let's prompt for it
            $PrismSecurePassword = Read-Host "Enter the Prism user $username password" -AsSecureString
        }
        else 
        {#if password was passed as an argument, let's convert the string to a secure string and flush the memory
            $PrismSecurePassword = ConvertTo-SecureString $password –asplaintext –force
            Remove-Variable password
        }
    } 
    else 
    { #we are using custom credentials, so let's grab the username and password from that
        $prismCredentials = Get-CustomCredentials -credname $prismCreds
        $username = $prismCredentials.UserName
        $PrismSecurePassword = $prismCredentials.Password
    }
#endregion

#region E - processing
	#building a variable containing the Nutanix cluster names
	$myvarNutanixClusters = @($ntnx_cluster1,$ntnx_cluster2)
	#initialize variables we'll need to store information about the Nutanix clusters
	$myvarNtnxC1_hosts, $myvarNtnxC2_hosts, $myvarNtnxC1_MaActiveCtrs, $myvarNtnxC2_MaActiveCtrs = @()
	$myvarCounter = 1 #we use this to store results differently for cluster 1 and 2
	
	foreach ($myvarNutanixCluster in $myvarNutanixClusters)
	{#connect to each Nutanix cluster to figure out the info we need
		if ($myvarCounter -eq 1) 
		{#we're processing data from cluster 1
            
            Write-Host "$(get-date) [INFO] Retrieving hosts information from Nutanix cluster $myvarNutanixCluster ..." -ForegroundColor Green
            $url = "https://$($myvarNutanixCluster):9440/PrismGateway/services/rest/v2.0/hosts/"
            $method = "GET"
            $NTNXHosts = Invoke-PrismRESTCall -method $method -url $url -username $username -password ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))
            Write-Host "$(get-date) [SUCCESS] Successfully retrieved hosts information from Nutanix cluster $myvarNutanixCluster" -ForegroundColor Cyan
            $myvarNtnxC1_hosts = ($NTNXHosts.entities).hypervisor_address

            Write-Host "$(get-date) [INFO] Retrieving protection domains from Nutanix cluster $myvarNutanixCluster ..." -ForegroundColor Green
            $url = "https://$($myvarNutanixCluster):9440/PrismGateway/services/rest/v2.0/protection_domains/"
            $method = "GET"
            $myvarMaActivePDs = Invoke-PrismRESTCall -method $method -url $url -username $username -password ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))
            $myvarNtnxC1_MaActiveCtrs = ($myvarMaActivePDs.entities | Where-Object {($_.active -eq $true) -and ($_.metro_avail.role -eq "Active")}).metro_avail.storage_container
            Write-Host "$(get-date) [SUCCESS] Successfully retrieved protection domains from Nutanix cluster $myvarNutanixCluster" -ForegroundColor Cyan
		}
		if ($myvarCounter -eq 2) 
		{#we're processing data from cluster 2

            Write-Host "$(get-date) [INFO] Retrieving hosts information from Nutanix cluster $myvarNutanixCluster ..." -ForegroundColor Green
            $url = "https://$($myvarNutanixCluster):9440/PrismGateway/services/rest/v2.0/hosts/"
            $method = "GET"
            $NTNXHosts = Invoke-PrismRESTCall -method $method -url $url -username $username -password ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))
            Write-Host "$(get-date) [SUCCESS] Successfully retrieved hosts information from Nutanix cluster $myvarNutanixCluster" -ForegroundColor Cyan
            $myvarNtnxC2_hosts = ($NTNXHosts.entities).hypervisor_address

            Write-Host "$(get-date) [INFO] Retrieving protection domains from Nutanix cluster $myvarNutanixCluster ..." -ForegroundColor Green
            $url = "https://$($myvarNutanixCluster):9440/PrismGateway/services/rest/v2.0/protection_domains/"
            $method = "GET"
            $myvarMaActivePDs = Invoke-PrismRESTCall -method $method -url $url -username $username -password ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismSecurePassword)))
            $myvarNtnxC2_MaActiveCtrs = ($myvarMaActivePDs.entities | Where-Object {($_.active -eq $true) -and ($_.metro_avail.role -eq "Active")}).metro_avail.storage_container
            Write-Host "$(get-date) [SUCCESS] Successfully retrieved protection domains from Nutanix cluster $myvarNutanixCluster" -ForegroundColor Cyan
        }

		#increment the counter
		++$myvarCounter
	}#end foreach Nutanix cluster loop

    $result = Disconnect-viserver * -Confirm:$False -ErrorAction SilentlyContinue #making sure we are not already connected to a vCenter server
    
	foreach ($myvarvCenter in $myvarvCenterServers)
	{#connect to vcenter now
		OutputLogData -category "INFO" -message "Connecting to vCenter server $myvarvCenter..."
		if (!($myvarvCenterObject = Connect-VIServer $myvarvCenter))
		{#make sure we can connect to the vCenter server
			$myvarerror = $error[0].Exception.Message
			OutputLogData -category "ERROR" -message "$myvarerror"
			return
		}
		else 
		{#...otherwise show the error message
			OutputLogData -category "INFO" -message "Connected to vCenter server $myvarvCenter."
		}#endelse

		if ($myvarvCenterObject)
		{#process vcenter

            #region process hosts
                #let's match host IP addresses we got from the Nutanix clusters to VMHost objects in vCenter
                $myvarNtnxC1_vmhosts = @() #this is where we will save the hostnames of the hosts which make up the first Nutanix cluster
                $myvarNtnxC2_vmhosts = @() #this is where we will save the hostnames of the hosts which make up the second Nutanix cluster
                Write-Host "$(get-date) [INFO] Getting hosts registered in vCenter server $myvarvCenter..." -ForegroundColor Green
                try 
                {#get all the vmhosts registered in vCenter
                    $myvarVMHosts = Get-VMHost -ErrorAction Stop 
                    Write-Host "$(get-date) [SUCCESS] Successfully retrieved vmhosts from vCenter server $myvarvCenter" -ForegroundColor Cyan
                }
                catch
                {#couldn't get all the vmhosts registered in vCenter
                    throw "$(get-date) [ERROR] Could not retrieve vmhosts from vCenter server $myvarvCenter : $($_.Exception.Message)"
                }
                foreach ($myvarVMHost in $myvarVMHosts) 
                {#let's look at each host and determine which is which
                    Write-Host "$(get-date) [INFO] Retrieving vmk interfaces for host $myvarVMHost..." -ForegroundColor Green
                    try 
                    {#retrieve all vmk NICs for that host
                        $myvarHostVmks = $myvarVMHost | Get-VMHostNetworkAdapter -ErrorAction Stop | Where-Object {$_.DeviceName -like "vmk*"} 
                        Write-Host "$(get-date) [SUCCESS] Successfully retrieved vmk interfaces for host $myvarVMHost" -ForegroundColor Cyan
                    }
                    catch
                    {#couldn't retrieve all vmk NICs for that host
                        throw "$(get-date) [ERROR] Could not retrieve vmk interfaces for host $myvarVMHost : $($_.Exception.Message)"
                    }
                    foreach ($myvarHostVmk in $myvarHostVmks) 
                    {#examine all VMKs
                        foreach ($myvarHostIP in $myvarNtnxC1_hosts) 
                        {#compare to the host IP addresses we got from the Nutanix cluster 1
                            if ($myvarHostVmk.IP -eq $myvarHostIP)
                            {#if we get a match, that vcenter host is in cluster 1
                                Write-Host "$(get-date) [INFO] $($myvarVMHost.Name) is a host in Nutanix cluster $ntnx_cluster1..." -ForegroundColor Green
                                $myvarNtnxC1_vmhosts += $myvarVMHost
                            }
                        }#end foreach IP C1 loop
                        foreach ($myvarHostIP in $myvarNtnxC2_hosts) 
                        {#compare to the host IP addresses we got from the Nutanix cluster 2
                            if ($myvarHostVmk.IP -eq $myvarHostIP)
                            {#if we get a match, that vcenter host is in cluster 2
                                Write-Host "$(get-date) [INFO] $($myvarVMHost.Name) is a host in Nutanix cluster $ntnx_cluster2..." -ForegroundColor Green
                                $myvarNtnxC2_vmhosts += $myvarVMHost 
                            }
                        }#end foreacch IP C2 loop
                    }#end foreach VMK loop
                }#end foreach VMhost loop

                if (!$myvarNtnxC1_vmhosts) 
                {#couldn't find hosts in cluster1
                    throw "$(get-date) [ERROR] No vmhosts were found for Nutanix cluster $ntnx_cluster1 in vCenter server $myvarvCenter"
                }
                if (!$myvarNtnxC2_vmhosts) 
                {#couldn't find hosts in cluster2
                    throw "$(get-date) [ERROR] No vmhosts were found for Nutanix cluster $ntnx_cluster2 in vCenter server $myvarvCenter"
                }

                #check all vmhosts are part of the same vSphere cluster
                OutputLogData -category "INFO" -message "Checking that all hosts are part of the same compute cluster..."
                try 
                {#we look at which cluster the first vmhost in cluster 1 belongs to.
                    $myvarvSphereCluster = $myvarNtnxC1_vmhosts[0] | Get-Cluster -ErrorAction Stop 
                }
                catch 
                {
                    throw "$(get-date) [ERROR] Could not retrieve vSphere cluster for host $($myvarNtnxC1_vmhosts[0].Name) : $($_.Exception.Message)"
                }
                
                $myvarvSphereClusterName = $myvarvSphereCluster.Name
                $myvarvSphereClusterVMHosts = $myvarNtnxC1_vmhosts + $myvarNtnxC2_vmhosts #let's create an array with all vmhosts that should be in the compute cluster

                
                try 
                {#get existing DRS groups
                    $myvarClusterObject = get-cluster $myvarvSphereClusterName -ErrorAction Stop
                    $myvarDRSGroups = $myvarClusterObject.ExtensionData.ConfigurationEx.group
                }
                catch 
                {#couldn't get existing DRS groups
                    throw "$(get-date) [ERROR] Could not retrieve vSphere object for cluster $myvarvSphereClusterName : $($_.Exception.Message)"
                }
                

                #get existing DRS rules
                try 
                {
                    $myvarClusterComputeResourceView = Get-View -ErrorAction Stop -ViewType ClusterComputeResource -Property Name, ConfigurationEx | where-object {$_.Name -eq $myvarvSphereClusterName}
                    $myvarClusterDRSRules = $myvarClusterComputeResourceView.ConfigurationEx.Rule
                }
                catch 
                {
                    throw "$(get-date) [ERROR] Could not retrieve existing DRS rules for cluster $myvarvSphereClusterName : $($_.Exception.Message)"
                }
                

                foreach ($myvarvSphereClusterVMHost in $myvarvSphereClusterVMHosts) 
                {#let's now look at each vmhost and which cluster they belong to
                    try 
                    {#which cluster does this host belong to?
                        $myvarVMHostCluster = $myvarvSphereClusterVMHost | Get-Cluster -ErrorAction Stop 
                    }
                    catch 
                    {
                        throw "$(get-date) [ERROR] Could not retrieve vSphere cluster object for vmhost $myvarvSphereClusterVMHost : $($_.Exception.Message)"
                    }
                    
                    if ($myvarVMHostCluster -ne $myvarvSphereCluster) 
                    {#let's check if it's the same cluster as our first host
                        $myvarVMHostName = $myvarvSphereClusterVMHost.Name
                        $myvarVMHostClusterName = $myvarVMHostCluster.Name
                        OutputLogData -category "ERROR" -message "$myvarVMHostName belongs to vSphere cluster $myvarVMHostClusterName when it should be in $myvarvSphereClusterName..."
                        break #we'l stop right here since at least one vmhost is not in the right compute cluster
                    }
                }#end foreach cluster vmhost loop

                #check that vSphere cluster has HA and DRS enabled
                OutputLogData -category "INFO" -message "Checking HA is enabled on vSphere cluster $myvarvSphereClusterName..."
                if ($myvarvSphereCluster.HaEnabled -ne $true) {OutputLogData -category "WARN" -message "HA is not enabled on vSphere cluster $myvarvSphereClusterName!"}
                OutputLogData -category "INFO" -message "Checking DRS is enabled on vSphere cluster $myvarvSphereClusterName..."
                if ($myvarvSphereCluster.DrsEnabled -ne $true)
                {
                    OutputLogData -category "ERROR" -message "DRS is not enabled on vSphere cluster $myvarvSphereClusterName!"
                    break #exit since DRS is not enabled
                }

                #check to see if the host group already exists
                $myvarDRSHostGroups = $myvarDRSGroups | Where-Object {$_.host} #keep host groups

                #CREATE DRS affinity groups for hosts in each nutanix cluster
                $myvarNtnxC1_DRSHostGroupName = $myvarNutanixCluster_1_HostGroupName
                $myvarNtnxC2_DRSHostGroupName = $myvarNutanixCluster_2_HostGroupName

                #do we have an existing DRS host group for c1 already?
                if ($myvarDRSHostGroups | Where-Object {$_.Name -eq $myvarNtnxC1_DRSHostGroupName})
                { #yes, so let's update it
                    OutputLogData -category "INFO" -message "Updating DRS Host Group $myvarNtnxC1_DRSHostGroupName on cluster $myvarvSphereCluster"
                    Update-DrsHostGroup -cluster $myvarvSphereCluster -Hosts $myvarNtnxC1_vmhosts -groupHostName $myvarNtnxC1_DRSHostGroupName
                }
                else
                { #no, so let's create it
                    OutputLogData -category "INFO" -message "Creating DRS Host Group $myvarNtnxC1_DRSHostGroupName on cluster $myvarvSphereClusterName for $ntnx_cluster1..."
                    $myvarNtnxC1_vmhosts | New-DrsHostGroup -Name $myvarNtnxC1_DRSHostGroupName -Cluster $myvarvSphereCluster
                }

                #do we have an existing DRS host group for c2 already?
                if ($myvarDRSHostGroups | Where-Object {$_.Name -eq $myvarNtnxC2_DRSHostGroupName})
                { #yes, so let's update it
                    OutputLogData -category "INFO" -message "Updating DRS Host Group $myvarNtnxC2_DRSHostGroupName on cluster $myvarvSphereCluster"
                    Update-DrsHostGroup -cluster $myvarvSphereCluster -Hosts $myvarNtnxC2_vmhosts -groupHostName $myvarNtnxC2_DRSHostGroupName
                }
                else
                { #no, so let's create it
                    OutputLogData -category "INFO" -message "Creating DRS Host Group $myvarNtnxC2_DRSHostGroupName on cluster $myvarvSphereClusterName for $ntnx_cluster2..."
                    $myvarNtnxC2_vmhosts | New-DrsHostGroup -Name $myvarNtnxC2_DRSHostGroupName -Cluster $myvarvSphereCluster
                }
            #endregion

			#region vms and rules

                #check existing vm groups
                $myvarDRSVMGroups = $myvarDRSGroups |Where-Object {$_.vm} #keep vm groups

                #retrieve names of VMs in each active datastore
                $myvarNtnxC1_vms = @()
                $myvarNtnxC2_vms = @()

                #region process cluster 1
                    foreach ($myvarDatastore in $myvarNtnxC1_MaActiveCtrs)
                    {#process each datastore
                        OutputLogData -category "INFO" -message "Getting VMs in datastore $myvarDatastore..."
                        try 
                        { 
                            $vm_objects = Get-Datastore -Name $myvarDatastore -ErrorAction Stop | Get-VM -ErrorAction Stop
                            if (!$vm_objects)
                            {#no vms in the datastore...
                                OutputLogData -category "ERROR" -message "There are no VMs in datastore $myvarDatastore. Please put at least 1 VM in that datastore and run the script again."
                                Exit
                            }
                            $myvarNtnxC1_vms = [Array]$myvarNtnxC1_vms + $vm_objects
                        }
                        catch 
                        {
                            throw "$(get-date) [ERROR] Could not retrieve VMs in datastore $myvarDatastore : $($_.Exception.Message)"
                        }

                        $myvarDRSVMGroupName = "DRS_VM_MA_" + $myvarDatastore

                        if (!($myvarDRSVMGroups | Where-Object {$_.Name -eq $myvarDRSVMGroupName})) #the DRS VM Group does not exist, so let's create it
                        {#vm groups ain't there, create it
                            OutputLogData -category "INFO" -message "Creating DRS VM Group $myvarDRSVMGroupName on cluster $myvarvSphereClusterName for datastore $myvarDatastore which is active on $ntnx_cluster1..."
                            $myvarNtnxC1_vms | New-DrsVMGroup -Name $myvarDRSVMGroupName -Cluster $myvarvSphereCluster
                        }
                        else
                        {#vm group exists already, update it
                            OutputLogData -category "INFO" -message "Updating DRS VM Group $myvarDRSVMGroupName on cluster $myvarvSphereClusterName for datastore $myvarDatastore which is active on $ntnx_cluster1..."
                            Update-DrsVMGroup -cluster $myvarvSphereCluster -VMs $myvarNtnxC1_vms -groupVMName $myvarDRSVMGroupName
                        }

                        $myvarDRSRuleName = "DRS_Rule_MA_" + $myvarDatastore

                        if (!($myvarClusterDRSRules | Where-Object {$_.Name -eq $myvarDRSRuleName})) #the DRS VM Group does not exist, so let's create it
                        {#drs rule ain't there, create it
                            OutputLogData -category "INFO" -message "Creating DRS rule $myvarDRSRuleName on cluster $myvarvSphereCluster so that VMs in $myvarDRSVMGroupName should run on hosts in $myvarNtnxC1_DRSHostGroupName..."
                            New-DrsVMToHostRule -VMGroup $myvarDRSVMGroupName -HostGroup $myvarNtnxC1_DRSHostGroupName -Name $myvarDRSRuleName -Cluster $myvarvSphereCluster
                        }
                        else
                        {#drs rule is there, update it
                            if (!($noruleupdate))
                            {#check we didn't want to skip update
                                OutputLogData -category "INFO" -message "Updating DRS rule $myvarDRSRuleName on cluster $myvarvSphereCluster for $myvarDatastore..."
                                Update-DRSVMToHostRule -VMGroup $myvarDRSVMGroupName -HostGroup $myvarNtnxC1_DRSHostGroupName -Name $myvarDRSRuleName -Cluster $myvarvSphereCluster -RuleKey $(($myvarClusterDRSRules | Where-Object {$_.Name -eq $myvarDRSRuleName}).Key) -RuleUuid $(($myvarClusterDRSRules | Where-Object {$_.Name -eq $myvarDRSRuleName}).RuleUuid)
                            }
                    }
                    }#end foreach datastore in C1 loop
                #endregion

                #region process cluster 2
                    foreach ($myvarDatastore in $myvarNtnxC2_MaActiveCtrs)
                    {
                        OutputLogData -category "INFO" -message "Getting VMs in datastore $myvarDatastore..."
                        try 
                        {
                            $vm_objects = Get-Datastore -Name $myvarDatastore -ErrorAction Stop | Get-VM -ErrorAction Stop
                            if (!$vm_objects)
                            {#no vms in the datastore...
                                OutputLogData -category "ERROR" -message "There are no VMs in datastore $myvarDatastore. Please put at least 1 VM in that datastore and run the script again."
                                Exit
                            }
                            $myvarNtnxC2_vms = [Array]$myvarNtnxC2_vms + $vm_objects
                        }
                        catch 
                        {
                            throw "$(get-date) [ERROR] Could not retrieve VMs in datastore $myvarDatastore : $($_.Exception.Message)"
                        }
                        

                        $myvarDRSVMGroupName = "DRS_VM_MA_" + $myvarDatastore

                        if (!($myvarDRSVMGroups | Where-Object {$_.Name -eq $myvarDRSVMGroupName}))
                        {#drs vm group ain't there, create it
                            OutputLogData -category "INFO" -message "Creating DRS VM Group $myvarDRSVMGroupName on cluster $myvarvSphereClusterName for datastore $myvarDatastore which is active on $ntnx_cluster2..."
                            $myvarNtnxC2_vms | New-DrsVMGroup -Name $myvarDRSVMGroupName -Cluster $myvarvSphereCluster
                        }
                        else
                        {#drs vm group is there, update it
                            OutputLogData -category "INFO" -message "Updating DRS VM Group $myvarDRSVMGroupName on cluster $myvarvSphereClusterName for datastore $myvarDatastore which is active on $ntnx_cluster2..."
                            Update-DrsVMGroup -cluster $myvarvSphereCluster -VMs $myvarNtnxC2_vms -groupVMName $myvarDRSVMGroupName
                        }


                        $myvarDRSRuleName = "DRS_Rule_MA_" + $myvarDatastore
                    
                        if (!($myvarClusterDRSRules | Where-Object {$_.Name -eq $myvarDRSRuleName}))
                        {#drs rule ain't there, create it
                            OutputLogData -category "INFO" -message "Creating DRS rule $myvarDRSVMGroupName on cluster $myvarvSphereClusterName so that VMs in $myvarDRSVMGroupName should run on hosts in $myvarNtnxC2_DRSHostGroupName..."
                            New-DrsVMToHostRule -VMGroup $myvarDRSVMGroupName -HostGroup $myvarNtnxC2_DRSHostGroupName -Name $myvarDRSRuleName -Cluster $myvarvSphereCluster
                        }
                        else
                        {#drs rule is there, update it
                            if (!($noruleupdate))
                            {#check we didn't want to skip updating the rule
                                OutputLogData -category "INFO" -message "Updating DRS rule $myvarDRSVMGroupName on cluster $myvarvSphereClusterName for $myvarDatastore..."
                                Update-DRSVMToHostRule -VMGroup $myvarDRSVMGroupName -HostGroup $myvarNtnxC2_DRSHostGroupName -Name $myvarDRSRuleName -Cluster $myvarvSphereCluster -RuleKey $(($myvarClusterDRSRules | Where-Object {$_.Name -eq $myvarDRSRuleName}).Key) -RuleUuid $(($myvarClusterDRSRules | Where-Object {$_.Name -eq $myvarDRSRuleName}).RuleUuid)
                            }
                        }
                    }#end foreach datastore in C2 loop
                #endregion

            #endregion


		}#endif
        OutputLogData -category "INFO" -message "Disconnecting from vCenter server $vcenter..."
		Disconnect-viserver -Confirm:$False #cleanup after ourselves and disconnect from vcenter
	}#end foreach vCenter
#endregion

#region F - cleanup
	#let's figure out how much time this all took
	OutputLogData -category "SUM" -message "total processing time: $($myvarElapsedTime.Elapsed.ToString())"

	#cleanup after ourselves and delete all custom variables
	Remove-Variable myvar* -ErrorAction SilentlyContinue
	Remove-Variable ErrorActionPreference -ErrorAction SilentlyContinue
	Remove-Variable help -ErrorAction SilentlyContinue
    Remove-Variable history -ErrorAction SilentlyContinue
	Remove-Variable log -ErrorAction SilentlyContinue
	Remove-Variable ntnx_cluster1 -ErrorAction SilentlyContinue
	Remove-Variable ntnx_cluster2 -ErrorAction SilentlyContinue
	Remove-Variable username -ErrorAction SilentlyContinue
	Remove-Variable password -ErrorAction SilentlyContinue
	Remove-Variable vcenter -ErrorAction SilentlyContinue
    Remove-Variable debugme -ErrorAction SilentlyContinue
#endregion
