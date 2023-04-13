#Remove all licenses from bulk users

$path = read-host "Insert TXT file path with user list"
$file = get-content $path
foreach ( $upn in $file) {
(get-MsolUser -UserPrincipalName $upn).licenses.AccountSkuId |
foreach{
   Set-MsolUserLicense -UserPrincipalName $upn -RemoveLicenses $_
}
}
#-----------------------------------------------------------------------------------

#Remove all licenses from one user
$upn = read-host "Enter UPN"
(get-MsolUser -UserPrincipalName $upn).licenses.AccountSkuId |
foreach{
Set-MsolUserLicense -UserPrincipalName $upn -RemoveLicenses 
}

#-----------------------------------------------------------------------------------

#Get licenses for bulk users
$arquivo = get-content c:\temp\users.txt
foreach ( $upn in $arquivo) {

   get-MsolUser -UserPrincipalName  $upn| fl Userprincipalname,Islicensed,@{n="Licenses";e={$_.Licenses.AccountSKUid}}
  
}

#---------------------------------------------------------------------------------------------------------------
