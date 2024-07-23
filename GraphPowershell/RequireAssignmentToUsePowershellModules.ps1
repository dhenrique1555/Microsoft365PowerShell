#Appid for Exchange Online Powershell
#$appId = "fb78d390-0c51-40cd-8e17-fdbfab77341b"  
#AppID for AzureAD/Msol Powershell
$$Appid = "1b730954-1685-4b74-9bfd-dac224a7b894"
#AppID for Teams Powershell
#$Appid = "12128f48-ec9e-42f0-b203-ea49fb6af367"


$sp = Get-MgServicePrincipal -Filter "appid eq '$appid'"
if (-not $sp) {  
    $sp = New-MgServicePrincipal -AppId $appId  
}  
Update-MgServicePrincipal -ServicePrincipalId $sp.id -AppRoleAssignmentRequired 

