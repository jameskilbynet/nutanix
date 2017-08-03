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
.PARAMETER cluster
  Nutanix cluster fully qualified domain name or IP address.
.PARAMETER username
  Username used to connect to the Nutanix cluster.
.PARAMETER password
  Password used to connect to the Nutanix cluster.
.EXAMPLE
  Connect to a Nutanix cluster of your choice:
  PS> .\template.ps1 -cluster ntnxc1.local -username admin -password admin
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: July 22nd 2015
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
    [parameter(mandatory = $true)] [string]$cluster,
    [parameter(mandatory = $true)] [string]$username,
    [parameter(mandatory = $true)] [string]$password,
    [parameter(mandatory = $true)] [string]$vm,
    [parameter(mandatory = $true)] [string]$proxy,
    [parameter(mandatory = $true)] [string]$backupPath,
    [parameter(mandatory = $false)] [switch]$deleteAll
)
#endregion

#region functions
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

#this function is used to connect to Prism REST API
Function PrismRESTCall
{
	#input: username, password, url, method, body
	#output: REST response
<#
.SYNOPSIS
  Connects to Nutanix Prism REST API.
.DESCRIPTION
  This function is used to connect to Prism REST API.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER username
  Specifies the Prism username.
.PARAMETER password
  Specifies the Prism password.
.PARAMETER url
  Specifies the Prism url.
.EXAMPLE
  PS> PrismRESTCall -username admin -password admin -url https://10.10.10.10:9440/PrismGateway/services/rest/v1/ 
#>
	param
	(
        [string] $username,
        [string] $password,
        [string] $url,
        [string] $method,
        $body
	)

    begin
    {
	    #Setup authentication header for REST call
        $myvarHeader = @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+$password ))} 
    }

    process
    {
        if ($body) {
            try {
                $myvarHeader += @{"Accept"="application/json"}
		        $myvarHeader += @{"Content-Type"="application/json"}
			    $myvarRESTOutput = Invoke-RestMethod -Method $method -Uri $url -Headers $myvarHeader -Body $body -Credential $credential -ErrorAction Stop
		    }
		    catch {
			    OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
			    Exit
		    }
        } else {
            try {
			    $myvarRESTOutput = Invoke-RestMethod -Method $method -Uri $url -Headers $myvarHeader -ErrorAction Stop
		    }
		    catch {
			    OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
			    Exit
		    }
        }
    }

    end
    {
        return $myvarRESTOutput
        Remove-variable username
        Remove-variable password
        Remove-variable url
        Remove-variable myvarHeader
    }
}#end function PrismRESTCall

#endregion

#region prepwork
# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}
#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 06/19/2015 sb   Initial release.
################################################################################
'@
$myvarScriptName = ".\template_prism_rest.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}


#let's get ready to use the Nutanix REST API
#Accept self signed certs
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
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

#endregion

#region variables
#initialize variables
	#misc variables
	$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
	$myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
	$myvarOutputLogFile += "OutputLog.log"
#endregion

#region parameters validation
	############################################################################
	# command line arguments initialization
	############################################################################	
    if (!(Test-Path $backupPath)) {
        OutputLogData -category "ERROR" -message "$backupPath cannot be accessed!"
        Exit
    }
	#let's initialize parameters if they haven't been specified
    
#endregion

#region processing	
	################################
	##  Main execution here       ##
	################################

    #region getting the information we need
	OutputLogData -category "INFO" -message "Retrieving list of VMs..."
    $vmList = PrismRestCall -method GET -url "https://$($cluster):9440/PrismGateway/services/rest/v2.0/vms/" -username $username -password $password
	$vmUuid = ($vmList.entities | where {$_.name -eq $vm}).uuid
    $proxyUuid = ($vmList.entities | where {$_.name -eq $proxy}).uuid
    
    OutputLogData -category "INFO" -message "Retrieving the configuration of $vm..."
    $vmConfig = PrismRestCall -method GET -url "https://$($cluster):9440/PrismGateway/services/rest/v2.0/vms/$($vmUuid)?include_vm_disk_config=true" -username $username -password $password
    OutputLogData -category "INFO" -message "Saving $vm configuration to $($backupPath)\$($vm).json..."
    $vmConfig | ConvertTo-Json | Out-File -FilePath "$($backupPath)\$($vm).json"
    
    #$deleteIdentifiers = PrismRESTCall -method DELETE -username $username -password $password -url "https://$($cluster):9440/api/nutanix/v3/idempotence_identifiers/$($env:COMPUTERNAME)"
    OutputLogData -category "INFO" -message "Asking for snapshot id allocation..."
    $content = @{
            client_identifier = "$env:COMPUTERNAME"
            count = 1
        }
    $body = (ConvertTo-Json $content)
    $snapshotAllocatedId = PrismRESTCall -method POST -username $username -password $password -url "https://$($cluster):9440/api/nutanix/v3/idempotence_identifiers" -body $body
    #endregion

    if ($deleteAll) {
        #region delete all backup snapshots
        $content =@{
            filter = "entity_uuid==$vmUuid"
            kind = "vm_snapshot"
        }
        $body = (ConvertTo-Json $content)
        $backupSnapshots = PrismRESTCall -method POST -username $username -password $password -url "https://$($cluster):9440/api/nutanix/v3/vm_snapshots/list" -body $body
        ForEach ($snapshot in $backupSnapshots.entities) {
            OutputLogData -category "INFO" -message "Deleting snapshot $($snapshot.metadata.uuid)"
            PrismRESTCall -method DELETE -username $username -password $password -url "https://$($cluster):9440/api/nutanix/v3/vm_snapshots/$($snapshot.metadata.uuid)"                
        }
        #endregion
    } else {

        #region creating a snapshot                                                                                                                                    #region creating the snapshot
        OutputLogData -category "INFO" -message "Creating a snapshot of $vm..."
        $snapshotName = "backup.snapshot.$(Get-Date -UFormat "%Y_%m_%d_%H_%M_")$vm"
        $content = @{
                spec = @{
                    resources = @{
                        entity_uuid = "$vmUuid"
                    }
                    snapshot_type = "CRASH_CONSISTENT"
                    name = $snapshotName
                }
                api_version = "3.0"
                metadata = @{
                    kind = "vm_snapshot"
                    uuid = $snapshotAllocatedId.uuid_list[0]
                }
            }
        $body = (ConvertTo-Json $content)
        $snapshotTask = PrismRESTCall -method POST -username $username -password $password -url "https://$($cluster):9440/api/nutanix/v3/vm_snapshots" -body $body
        OutputLogData -category "INFO" -message "Retrieving status of snapshot $snapshotName ..."
        Do {
            $snapshotStatus = PrismRESTCall -method GET -username $username -password $password -url "https://$($cluster):9440/api/nutanix/v3/vm_snapshots/$($snapshotAllocatedId.uuid_list[0])"
            if ($snapshotStatus.status.state -eq "kError") {
                OutputLogData -category "ERROR" -message "$($snapshotStatus.status.message_list.message)"
                Exit
            } elseIf ($snapshotStatus.status.state -eq "COMPLETE") {
                OutputLogData -category "INFO" -message "$snapshotName status is $($snapshotStatus.status.state)"
            } else {
                OutputLogData -category "WARNING" -message "$snapshotName status is $($snapshotStatus.status.state), waiting 5 seconds..."
                Start-Sleep -Seconds 5
            }
        } While ($snapshotStatus.status.state -ne "COMPLETE")
        #endregion

        #region mounting disks on the backup proxy vm
        OutputLogData -category "INFO" -message "Mounting the $vm snapshots on $proxy..."
        $snapshotFilePath = $snapshotStatus.status.snapshot_file_list.snapshot_file_path
                                                            $content = @{
            uuid = "$proxyUuid"
            vm_disks = @(foreach ($disk in $snapshotStatus.status.snapshot_file_list.snapshot_file_path) {
                        @{
                vm_disk_clone = @{
                    disk_address = @{
                        device_bus = "SCSI"
                        ndfs_filepath = "$disk"
                    }
                }
                        }
            }
            )
        }
        $body = (ConvertTo-Json $content -Depth 4)
        $diskAttachTaskUuid = PrismRESTCall -method POST -username $username -password $password -url "https://$($cluster):9440/PrismGateway/services/rest/v2.0/vms/$($proxyUuid)/disks/attach" -body $body

        OutputLogData -category "INFO" -message "Checking status of the disk attach task $($diskAttachTaskUuid.task_uuid)..."
        Do {
            $diskAttachTaskStatus = PrismRESTCall -method GET -username $username -password $password -url "https://$($cluster):9440/PrismGateway/services/rest/v2.0/tasks/$($diskAttachTaskUuid.task_uuid)"
            if ($diskAttachTaskStatus.progress_status -ne "Succeeded") {
                OutputLogData -category "WARNING" -message "Disk attach task status is $($diskAttachTaskStatus.progress_status), waiting 5 seconds..."
                Start-Sleep -Seconds 5
            }
        } While ($diskAttachTaskStatus.progress_status -ne "Succeeded")
        #endregion

        #region backing up data
        #OutputLogData -category "INFO" -message "Backing up data..."
        #endregion

        #region detaching disks from proxy vm
        #OutputLogData -category "INFO" -message "Removing disks from $proxy..."
        #endregion

        #region Deleting the snapshot
        OutputLogData -category "INFO" -message "Deleting snapshot $snapshotName..."
        $snapshotDeletionStatus = PrismRESTCall -method DELETE -username $username -password $password -url "https://$($cluster):9440/api/nutanix/v3/vm_snapshots/$($snapshotAllocatedId.uuid_list[0])"
        OutputLogData -category "INFO" -message "Deleting snapshot identifiers for $($env:COMPUTERNAME)..."
        $deleteIdentifiers = PrismRESTCall -method DELETE -username $username -password $password -url "https://$($cluster):9440/api/nutanix/v3/idempotence_identifiers/$($env:COMPUTERNAME)"
        #endregion
    }

#endregion

#region cleanup
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
    Remove-Variable debugme -ErrorAction SilentlyContinue
#endregion