 
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
$ContainerName  = ''

Measure-Command {
#Devices
$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"

$fulldata = @()
$data = Invoke-MgGraphRequest -Method GET -Uri $uri | ConvertTO-Json | ConvertFrom-Json 
$fulldata += $data.value

if ($data.'@odata.nextlink') {
Do{
	$data = Invoke-MgGraphRequest -Method GET -Uri $data.'@odata.nextlink' | ConvertTO-Json | ConvertFrom-Json 
	$fulldata += $data.value
}
until (
!$data.'@odata.nextlink'
)
}
}


$Reportname = $uri.split("/")[-1]

$reportname 
$fulldata | export-csv c:\temp\$reportname.csv -NoTypeInformation

$devices = $fulldata



Measure-Command {
# Get all devices (compliant + non-compliant)
$devices = Get-MgDeviceManagementManagedDevice -All

# Initialize result array
$allResults = @()

foreach ($device in $devices) {
    $deviceId   = $device.Id
    $deviceName = $device.DeviceName
    $UPN        = $device.UserPrincipalName
    $UserID     = $device.UserId
    $os         = $device.OperatingSystem

    Write-Host "Checking "$deviceName "of " $devices.Count

    # Get compliance policy states for the device
    $policyStates = Get-MgDeviceManagementManagedDeviceCompliancePolicyState -ManagedDeviceId $deviceId

    foreach ($policy in $policyStates) {
        $policyId   = $policy.Id
        $policyName = $policy.DisplayName

        # Get setting-level states using raw Graph beta endpoint
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/deviceCompliancePolicyStates/$policyId/settingStates"
        $settingResponse = Invoke-MgGraphRequest -Method GET -Uri $uri
        $settingStates = $settingResponse.value

        foreach ($setting in $settingStates) {
            $allResults += [PSCustomObject]@{
                DeviceName    = $deviceName
                DeviceID      = $deviceId
                UserUPN        = $UPN
                UserID         = $UserID
                OS            = $os
                PolicyName    = $policyName
                SettingName   = $setting.setting
                SettingStatus = $setting.state
                ErrorCode     = $setting.errorCode
            }
        }
    }
}
}

 #Export to Storage Account
$excelfilename = "$Env:temp/DevicesComplianceStateandsettings.csv"
$allResults| export-csv "$Env:temp/DevicesComplianceStateandsettings.csv" -NoTypeInformation
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force



