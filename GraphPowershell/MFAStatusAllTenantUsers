
# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

#Extract the access token from the AzAccount authentication context and use it to connect to Microsoft Graph
$token = (Get-AzAccessToken -ResourceTypeName MSGraph).token

$RequiredScopes = @(
"Directory.ReadWrite.All"
"AuditLog.Read.All"
"Organization.Read.All"
"User.Read.All"
"UserAuthenticationMethod.ReadWrite.All"
)
Connect-MgGraph -AccessToken $token
Get-mgcontext | Select -expandproperty Scopes 


#Save to Storage Account
$StorageAccountName = ''
$StorageAccountKey = ""
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = ''
$ContainerName  = ''

 Measure-command{
  $users = Get-MgUser -all -Property "accountEnabled,onPremisesDistinguishedName, onPremisesDomainName,displayName, userPrincipalName,UserType,Id,jobtitle,EmployeeId,OfficeLocation,Mail,Department,onPremisesSamAccountName,CreatedDatetime,LastPasswordChangeDateTime,signInActivity"
 }
  $output = @()
$data = @()
Measure-Command{
  foreach($user in $users){
	  
	   $lastlogon = $user.signInActivity.lastSignInDateTime
     if($lastlogon -ne $null){
     $unformatteddate = [datetime]$lastlogon
 $formatteddate = $unformatteddate.tostring("dd'/'MM'/'yyyy HH:mm")
 } Else {$formatteddate = $null}
 
  $data = New-Object -TypeName psobject
  $data | Add-Member -MemberType NoteProperty -Name onpremisesdomainname -Value $user.onpremisesdomainname
  $data | Add-Member -MemberType NoteProperty -Name DisplayName -Value $user.DisplayName
  $data | Add-Member -MemberType NoteProperty -Name UserUPN -Value $user.UserPrincipalName
  $data | Add-Member -MemberType NoteProperty -Name UserID -Value $user.Id
  $data | Add-Member -MemberType NoteProperty -Name JobTitle -Value $user.JobTitle
  $data | Add-Member -MemberType NoteProperty -Name EmployeeId -Value $user.EmployeeId
  $data | Add-Member -MemberType NoteProperty -Name OfficeLocation -Value $user.OfficeLocation
  $data | Add-Member -MemberType NoteProperty -Name Mail -Value $user.Mail
  $data | Add-Member -MemberType NoteProperty -Name Department -Value $user.Department
  $data | Add-Member -MemberType NoteProperty -Name UserType -Value $user.UserType
   $data | Add-Member -MemberType NoteProperty -Name OnpremisesdistinguishedName -Value $user.onPremisesDistinguishedName
   $data | Add-Member -MemberType NoteProperty -Name SamAccountName -Value $user.onPremisesSamAccountName
  $data | Add-Member -MemberType NoteProperty -Name AccountEnabled -Value $user.AccountEnabled
  $data | Add-Member -MemberType NoteProperty -Name CreatedDatetime -Value $user.CreatedDatetime
  $data | Add-Member -MemberType NoteProperty -Name LastPasswordChangeDateTime -Value $user.LastPasswordChangeDateTime
  $data | Add-Member -MemberType NoteProperty -Name LastAzureADLogon -Value $formatteddate
 $output += $data
}}

Measure-Command{
$DomainUsers = $output 



$result = @()
foreach($user in $DomainUsers){

	$Counter++
		$percent = (($counter / $DomainUsers.count) * 100)
		Write-Progress -Activity "Extracao em andamento...$user" -status "$percent%"  -percentcomplete $percent
$mfamethods = @()
$sms = @()
$mfaphonenumber = @()
$mfaauthdevice = @()
$mfamethodregistered = @()
#$userinfo = get-mguser -userid $user -Property "accountEnabled, assignedLicenses, companyName, createdDateTime, department, displayName, employeeId, givenName, id, jobTitle, mail, officeLocation, onPremisesDistinguishedName, onPremisesDomainName, onPremisesExtensionAttributes, onPremisesSamAccountName, onPremisesSecurityIdentifier, onPremisesUserPrincipalName, postalCode, state, streetAddress, surname, usageLocation, userPrincipalName, userType, city, extensionAttribute10, manager,LastPasswordChangeDateTime"

 
$MFAINFO = get-mguserauthenticationmethod -userid $user.UserID -filter "Id ne '28c10230-6103-485e-b985-444c60001490'" 
$MFAMETHODS = $mfainfo.additionalproperties."@odata.type"

 $lastpassreset = $user.LastPasswordChangeDateTime
     if($lastpassreset -ne $null){
     $unformatteddatepass = [datetime]$lastpassreset
$formatteddatepass = $unformatteddatepass.tostring("dd'/'MM'/'yyyy HH:mm")
} Else {$formatteddatepass = $null}


if($mfamethods -like "*phoneAuthenticationMethod*")
{$sms = $True
$Mfaphonenumber = (@($mfainfo.additionalproperties.phoneNumber) -join ',')
}
else{$Sms = $false
$mfaphonenumber = $null}

 

If($mfamethods -like "*microsoftAuthenticatorAuthenticationMethod*"){
$MSAUTHAPP = $True
  $mfaauthdevice = (@($mfainfo.AdditionalProperties.displayName) -join ',')
}
else{$MSAUTHAPP = $false
$mfaauthdevice = $null
}

 

if($MFAMETHODS -like "*fido2AuthenticationMethod*"){
$fido2 = $true
}
else{$fido2 = $false
$fidodevice = $null}

 

if($MFAMETHODS -like "*softwareOathAuthenticationMethod*"){
    $TPAUTHAPP = $True
}
else{$tpauthapp = $false}

 

if(($sms -eq $true) -or ($msauthapp -eq $true) -or ($fido2 -eq $true) -or ($tpauthapp -eq $true))
{
$mfamethodregistered = $true
}
else
{
$mfamethodregistered = $false
}
#Export Results to Variable
$Result += New-Object PSObject -property $([ordered]@{ 
Domain = $user.onPremisesDomainName
DisplayName = $user.DisplayName
UserPrincipalName = $user.UserUPN
UserID = $user.Id
JobTitle = $user.jobTitle
EmployeeId = $user.employeeId
OfficeLocation = $user.OfficeLocation
Mail = $user.Mail
Department = $user.Department
UserType = $User.UserType
DN = $user.onPremisesDistinguishedName
SamAccountName = $user.onPremisesSamAccountName
AccountEnabled = $user.accountEnabled
CreatedDatetime = $user.createdDateTime
SMSENABLED = $sms
SMSPHONENUMBER = $mfaphonenumber
MSAUTHENTICATORAPPENABLED = $msauthapp
DEVICES = $mfaauthdevice
FIDO2ENABLED = $fido2
ThirdPartyAuthenticatorAppEnabled = $tpauthapp
UserEnabledMFA = $mfamethodregistered
LastPasswordChangeDateTime  = $formatteddatepass
LastAzureADLogon = $user.LastAzureADLogon

})
}}

$outputcsv = $result | where-object {$_.UserType -ne "Guest"}
$outputcsv | export-csv $Env:temp/'' -notypeinformation -encoding utf8


Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $Env:temp/'' -Blob $FileName -Force

$anexo = Get-AzStorageBlobContent -Container $ContainerName -Blob $FileName -Context $StorageContext
$anexoemail = $anexo.name

$credObject = Get-AutomationPSCredential -Name "O365"
Send-MailMessage -Credential $credObject -From "" -To "" -Subject " MFA Status All Users" -Body "INICIO: $Inicio `n `n Gerado relatorio de Status do MFA! `n `n TERMINO: $Termino" -SmtpServer "outlook.office365.com" -UseSSL -Attachments $anexoemail -Encoding UTF8
 
 
