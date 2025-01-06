
#Sharepoint Module loop - Powershell 5 - Add own admin account as site admin
$ADMUPN = “danilo.pinheiro@0bpf4.onmicrosoft.com”
$sites = get-content c:\temp\users.txt
foreach($siteurl in $sites){
Set-SPOUser -Site $siteurl -LoginName $admupn -IsSiteCollectionAdmin $true
}

#Pnp module loop - Powershell 7 - Add Security Group as Admin
connect-mggraph -ContextScope process
$Testgraphcall = get-mguser -top 1
$sites = get-content c:\temp\users.txt
$securityGroupName = "LAB-ITD-M365-Sharepoint-Admins"
foreach($siteurl in $sites ){
Connect-PnPOnline -URl $siteurl -UseWebLogin
set-pnptenantsite -Identity $siteurl -PrimarySiteCollectionAdmin $securityGroupName
Get-PnPSiteCollectionAdmin
}

#Sharepoint Module loop - Powershell 5 - Remove own admin account as site admin
$ADMUPN = “danilo.pinheiro@0bpf4.onmicrosoft.com”
$sites = get-content c:\temp\users.txt
foreach($siteurl in $sites){
Set-SPOUser -Site $siteurl -LoginName $admupn -IsSiteCollectionAdmin $false
}
