 
  #Connect to Microsoft Graph
# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

#Extract the access token from the AzAccount authentication context and use it to connect to Microsoft Graph
$token = (Get-AzAccessToken -ResourceTypeName MSGraph).token

$securetoken = ConvertTo-SecureString -String $token -ASPLAINTEXT -force
Connect-MgGraph -AccessToken $token
Get-mgcontext | Select -expandproperty Scopes 

 #StorageAccountVariables
$StorageAccountName = ''
$StorageAccountKey = ""
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = 'IntuneReports.xlsx'
$ContainerName  = ''
 

 $excelfilename = "$Env:temp/IntuneReports.xlsx"

Import-module IntuneStuff
 Measure-Command {
   $MaximumFunctionCount = "32768"
 #IntuneStuff Module
 
 #Get Summary of Configuration Policies Deployment - No Need for Custom Output
 $ConfPolicySummary = Get-IntuneConfPolicyAssignmentSummaryReport
 $ConfPolicySummary.count
 $ConfPolicySummary | export-excel $excelfilename -worksheetname "ConfigurationPoliciesSummary"
 
 
 #Get if the Bitlocker Recovery Key was uploaded to EntraID - No Need for Custom Output
 $CheckRecoveryKeyBackup = Get-BitlockerEscrowStatusForAzureADDevices 
 $CheckRecoveryKeyBackup.count
 $CheckRecoveryKeyBackup | export-excel $excelfilename -worksheetname "BitlockerDeviceRKeyBackup"


 #Get Summary of Deployment for All Apps - No Need for Custom Output
 $AppsSummary  = Get-IntuneAppInstallSummaryReport
 $AppsSummary.count
 $AppsSummary  | export-excel $excelfilename -worksheetname "AppsSummary"
 #Get Intune Audit Logs - Needs Custom Output
$Auditlogs =  Get-IntuneAuditEvent
 $Auditlogs.count


$auditlogsoutput = @()
 foreach($auditlog in $auditlogs){
 
 $auditlogsoutput += New-Object PSObject -property $([ordered]@{ 
DatetimeUTC = $auditlog.DatetimeUTC
ResourceName = $auditlog.ResourceName -join ","
Operation = $auditlog.OperationType
Result = $auditlog.Result
ActivityType = $auditlog.Type
ActorUPN = $auditlog.ActorUPN
ActorId = $auditlog.ActorId
ActorApplication = $auditlog.ActorApplication
Category = $auditlog.Category
 
})
 }

$auditlogsoutput | export-excel $excelfilename -worksheetname "IntuneAuditLogs"

  #Get Hardware Device Information - No Need for Custom Output
 $HardwareDeviceInfo =  Get-IntuneDeviceHardware
  $HardwareDeviceInfo.count

$HardwareDeviceInfo | export-excel $excelfilename -worksheetname "HardwareDeviceInfo"
  #Get All Discovered Apps on all Devices - Needs Custom Output
   #Get All Discovered Apps on all Devices - Needs Custom Output
Measure-Command { 
 $DiscoveredApps = Get-IntuneDiscoveredApp
  $DiscoveredApps.count
   $DiscoveredAppsOutput = @()
  foreach($device in $discoveredapps){
  $apps = $device.detectedapps
  foreach($app in $apps){
  $DiscoveredAppsOutput += New-Object PSObject -property $([ordered]@{ 
DeviceName = $device.devicename
Appname = $app.DisplayName
AppVersion = $app.version
Publisher = $app.Publisher
}
)
}
}
}

  $DiscoveredAppsOutput | export-excel $excelfilename -worksheetname "DiscoveredApps"
  #Get All DetectedApps
  $DetectedApps = Get-MgDeviceManagementDetectedApp -All
$DetectedApps | export-excel $excelfilename -worksheetname "DetectedApps"
 }

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force
