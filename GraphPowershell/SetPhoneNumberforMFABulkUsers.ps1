#Permissions needed: "User.Read.All","UserAuthenticationMethod.ReadWrite.All"

$Body = @{    
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    client_Id     = $ApplicationID
    Client_Secret = $AccessSecret
}



$ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenatDomainName/oauth2/v2.0/token" -Method POST -Body $Body
$token = $ConnectGraph.access_token



Connect-mggraph -accesstoken $token

##First Create a CSV file with the UPN and PhoneNumber Columns. The separation of values needs to be done with a "," between columns
$inputfile = read-host "Insert path for CSV File with Users and their MFA SMS numbers"
$Outfile = read-host "Insert Path for Log file"


$data=Import-Csv -Path $inputfile
foreach ($user in $data)
{
$upn=$user.upn
$phone="+"+$user.phonenumber

 if (Get-MgUser -userid $upn)
 {
if (!(get-MgUserAuthenticationPhoneMethod -UserId $upn).phonenumber) 
{
 #"User $upn do not have any phone number" | Out-File -FilePath $Outfile -Append

try
{
New-MgUserAuthenticationPhoneMethod -UserId $upn  -phoneType "mobile" -phoneNumber $phone
"User $upn phone number set to $phone" | Out-File -FilePath $Outfile -Append
}
catch
{
"Failed to set $upn Phone number to $phone" | Out-File -FilePath $Outfile -Append
}
}
else
{
$Already=(get-MgUserAuthenticationPhoneMethod -UserId $upn).phonenumber 
"User $upn already registered phone number to $Already " | Out-File -FilePath $Outfile -Append
}
}

else
{
"User $upn doesnt exist, please check" | Out-File -FilePath $Outfile -Append
}
}

$date2 = (Get-Date -f dd-MM-yyyy-hhmmss)

"----------------Script ended at $date2------------------" | Out-File $Outfile -Append
