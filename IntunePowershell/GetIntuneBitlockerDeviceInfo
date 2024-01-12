Measure-Command{


#Get Intune Device Information
$intunemanaged = Get-MgBetaDeviceManagementManagedDevice -filter "Operatingsystem eq 'Windows'" -all

$outputIntuneDeviceInfo = @()
foreach($device in $intunemanaged){
$outputIntuneDeviceInfo += New-Object PSObject -property $([ordered]@{ 
InfoSource1 = "IntuneManagement"
DeviceNameIntune = $device.DeviceName
DeviceOS = $Device.OperatingSystem
DeviceSku = $device.SkuFamily
DeviceSkuNumber = $device.SkuNumber
OsVersion = $device.OsVersion
DeviceOwner = $device.OwnerType
JoinType = $device.JoinType
AadRegistered = $device.AadRegistered
AutoPilotEnrolled = $device.AutoPilotEnrolled
DeviceEnrollmentType = $device.DeviceEnrollmentType
EnrollmentDateTime = $device.EnrolledDateTime
isEncrypted = $device.isEncrypted
ManagementAgent = $device.ManagementAgent
ManagementState = $device.ManagementState
SerialNumber = $device.SerialNumber
TotalStorageinBytes = $device.TotalStorageSpaceinBytes
FreeStorageinBytes = $device.FreeStorageSpaceinBytes
Compliant = $device.ComplianceState
AzureADDeviceId = $device.AzureADDeviceId
OwnerUserDisplayName = $device.UserDisplayName
OwnerUserPrincipalName = $device.userprincipalname
OwnerUserID = $device.UserId
UsersLoggedOnId = $device.Usersloggedon.UserId -join ","
UsersLoggedonLastLogin = $device.Usersloggedon.LastLogonDateTime -join ","
})
}

#Get Intune Bitlocker Device Information
$intunedevicesbitlockerinfo = Get-MgBetaDeviceManagementManagedDeviceEncryptionState -all
$outputintunedevicesbitlockerinfo = @()
  foreach($device in $intunedevicesbitlockerinfo){
$outputintunedevicesbitlockerinfo += New-Object PSObject -property $([ordered]@{ 
InfoSource2 = "BitlockerIntune"
 DevicePrimaryUserPrincipalName = $device.userprincipalname
   DeviceNameBitlocker = $device.DeviceName
   DeviceType = $device.DeviceType
   DeviceOSVersion = $device.osversion
   TPMVersion = $device.TPMSpecificationVersion
   EncryptionReady = $device.encryptionReadinessState
   EncryptionState = $device.encryptionState
   advancedBitLockerStates = $device.advancedBitLockerStates
   PolicyDetails = $device.Policydetails.PolicyName -join ","
  })
  }
 
 #Get Azure AD Device Information
  $AzureADDevicesInfo = get-mgbetadevice -all
  
 $outputAzureADdevicesbitlockerinfo = @()
 foreach($device in $AzureADDevicesInfo){
 
 	   $signindate = $signin.ApproximateLastSignInDateTime
     if($signindate -ne $null){
     $unformatteddate = [datetime]$signindate
 $formatteddate = $unformatteddate.tostring("dd'/'MM'/'yyyy HH:mm")
 } Else {$formatteddate = $null}
 
 $outputAzureADdevicesbitlockerinfo += New-Object PSObject -property $([ordered]@{ 
 InfoSource3 = "AzureAD"
 DeviceNameAzureAD = $device.DisplayName
 AzureADId = $device.ID
 DeviceEnabled = $device.AccountEnabled
 DeviceLastSignIn = $formatteddate
 DeviceOwnership = $device.DeviceOwnership 
 TrustType = $device.TrustType
 OSType = $device.OperatingSystem
 OsVersionAzureAD = $device.OperatingSystemVersion
 Manufacturer = $device.Manufacturer
 Model = $device.Model
 OnPremisesSyncEnabled = $device.OnPremisesSyncEnabled
 OnPremisesLastSyncDateTime = $device.OnPremisesLastSyncDateTime
 IsManaged = $device.IsManaged
 Hostnames = $device.Hostnames -join ","
 ManagementType = $device.ManagementType
 EnrollmentType = $device.EnrollmentType
 ProfileType = $device.ProfileType 
   })
  }
}

$joinintunebitlocker = join-object -Left $outputIntuneDeviceInfo -Right $outputintunedevicesbitlockerinfo -LeftJoinProperty devicenameintune -RightJoinProperty devicenamebitlocker -KeepRightJoinProperty -RightMultiMode DuplicateLines
$joinfinal = Join-Object -left $joinintunebitlocker -Right $outputAzureADdevicesbitlockerinfo -LeftJoinProperty devicenameintune -RightJoinProperty devicenameazuread -keeprightjoinproperty -rightmultimode duplicatelines

