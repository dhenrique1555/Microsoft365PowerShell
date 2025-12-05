 
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
 

#App Health Device Model Performance
$uri =  "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsAppHealthDeviceModelPerformance" | ConvertTo-Json | Convertfrom-json
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


$Reportname = $uri.split("/")[-1]

$reportname 
#Export To Environment
$excelfilename = "$Env:temp/$reportname.csv"
$fulldata | export-csv "$Env:temp/$reportname.csv" -NoTypeInformation

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force

#App Health Device Performance
$uri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsAppHealthDevicePerformance"
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


$Reportname = $uri.split("/")[-1]
#Export To Environment
$excelfilename = "$Env:temp/$reportname.csv"
$fulldata | export-csv "$Env:temp/$reportname.csv" -NoTypeInformation

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force

#OSVersion App Health Performance 
$uri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsAppHealthOSVersionPerformance"
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


$Reportname = $uri.split("/")[-1]

#Export To Environment
$excelfilename = "$Env:temp/$reportname.csv"
$fulldata | export-csv "$Env:temp/$reportname.csv" -NoTypeInformation

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force

#App Health Application Performance
$uri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsAppHealthApplicationPerformance"
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


$Reportname = $uri.split("/")[-1]

#Export To Environment
$excelfilename = "$Env:temp/$reportname.csv"
$fulldata | export-csv "$Env:temp/$reportname.csv" -NoTypeInformation

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force


#App Score Per Device Model
$uri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsModelScores"
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


$Reportname = $uri.split("/")[-1]

#Export To Environment
$excelfilename = "$Env:temp/$reportname.csv"
$fulldata | export-csv "$Env:temp/$reportname.csv" -NoTypeInformation

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force


# Scores Per Device 

$uri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsDeviceScores"
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

$Reportname = $uri.split("/")[-1]

#Export To Environment
$excelfilename = "$Env:temp/$reportname.csv"
$fulldata | export-csv "$Env:temp/$reportname.csv" -NoTypeInformation

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force

#Device Performance 
$uri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsDevicePerformance"
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

$Reportname = $uri.split("/")[-1]

#Export To Environment
$excelfilename = "$Env:temp/$reportname.csv"
$fulldata | export-csv "$Env:temp/$reportname.csv" -NoTypeInformation

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force

#Device Startup Process Performance
$uri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsDeviceStartupProcessPerformance"
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


$Reportname = $uri.split("/")[-1]

#Export To Environment
$excelfilename = "$Env:temp/$reportname.csv"
$fulldata | export-csv "$Env:temp/$reportname.csv" -NoTypeInformation

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force

#https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsCategories('restart')?dtFilter=all&$select=id,overallScore,metricValues,insights,state&$expand=metricValues

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


$Reportname = $uri.split("/")[-1]

$reportname 
$fulldata | export-csv c:\temp\$reportname.csv -NoTypeInformation

$devices = $fulldata


#Startup history
$fulldata = @()
foreach($Device in $Devices){
$deviceid = $device.id
$devicename = $device.devicename
Write-host "Getting Startup History for $devicename"
$uri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsDeviceStartupHistory?" + '$filter=deviceId%20eq%20%27' + "$DeviceID%27"	

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
}
$Reportname = $uri.split("/")[-1]

$reportname 


#Export To Environment
$excelfilename = "$Env:temp/StartUpHistory.csv"
$fulldatajoined = join-object -Left $fulldata -right $devices -rightproperties devicename,userprincipalname,compliancestate,operatingsystem,osversion,model,manufacturer -Type AllInLeft -LeftJoinProperty deviceid -RightJoinProperty id
$fulldatajoined | export-csv "$Env:temp/StartUpHistory.csv"  -NoTypeInformation
 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force



