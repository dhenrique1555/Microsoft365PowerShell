
$Date = (Get-Date).AddDays(-30).AddHours(0).AddMinutes(-(Get-Date).Minute).AddSeconds(-(Get-Date).Second).AddMilliseconds(-(Get-Date).Milliseconds)



Write-Host
Write-Host "Downloading data... Start time:" $(Get-Date -Format "hh:mm:ss")
$output = @()
$data = @()



$arquivo = get-content C:\Temp\users.txt



foreach ($user in $arquivo) {
  
  $users1 = Get-MgUser -UserId $user -Property "accountEnabled, assignedLicenses, companyName, createdDateTime, department, displayName, employeeId, givenName, id, jobTitle, mail, officeLocation, onPremisesDistinguishedName, onPremisesDomainName, onPremisesExtensionAttributes, onPremisesSamAccountName, onPremisesSecurityIdentifier, onPremisesUserPrincipalName, postalCode, state, streetAddress, surname, usageLocation, userPrincipalName, userType, city, extensionAttribute10, manager"
  
  $data = New-Object -TypeName psobject
  $data | Add-Member -MemberType NoteProperty -Name onpremisesdomainname -Value $users1.onpremisesdomainname
  $data | Add-Member -MemberType NoteProperty -Name UserUPN -Value $users1.UserPrincipalName
  $data | Add-Member -MemberType NoteProperty -Name UserType -Value $users1.UserType
  
  $output += $data



}







$SignInReport = @()
$SignInReport += "UserDisplayName;UserPrincipalName;CreatedDateTime;AppDisplayName;ID;LocationCity;LocationState;LocationCountry;IpAddress;DeviceHostname;AppliedConditionalAccessPolicies;conditionalaccessstatus;Status"



foreach($user in $Domain.UserUPN){
    
#  $customPsObject = New-Object -TypeName PsObject



  $signinsUser = Get-MgAuditLogSignIn -Filter "Userprincipalname  eq '$user' and CreatedDateTime gt $($Date.ToString("yyyy-MM-ddTHH:mm:ssZ"))" | select userDisplayname,Userprincipalname,createddatetime,appdisplayname,clientappused,@{n="status";e={if($_.status.errorcode -eq "0"){"SuccessfulLogin"} else {$_.status.errorcode} }},Location,ipaddress,conditionalaccessstatus,appliedconditionalaccesspolicies



  foreach ($u in $signinsUser){

  $data1 = New-Object -TypeName psobject
   $data1  | Add-Member -MemberType NoteProperty -Name CAPolicies -Value $u.AppliedConditionalAccessPolicies

 $data2 = $data1.capolicies
$data3 = $data2 | where-object {$_.result -eq "failure"-or $_.result -eq "success"}

       $e = $u.UserDisplayName + ";" + $u.UserPrincipalName + ";" + $u.CreatedDateTime + ";" + $u.AppDisplayName + ";" + $u.ID  + ";" + $u.Location.City  + ";" + $u.Location.State + ";" + $u.Location.CountryOrRegion + ";" + $u.IPAddress + ";" + $u.DeviceDetail.DisplayName + ";" + $data3.DisplayName + ";" + $u.conditionalaccessstatus + ";" + $u.status 
        $SignInReport += $e
        $e = ""
   }
}



$SignInReport

Write-Host "Downloading data... Stop time:" $(Get-Date -Format "hh:mm:ss")
