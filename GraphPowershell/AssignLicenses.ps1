#Connect Graph Scope
Connect-Graph -Scopes User.ReadWrite.All, Organization.Read.All -contextscope process

#Check available licenses 

Get-MgSubscribedSku -all | select skupartnumber,@{n="Availableunits";e={$_.prepaidunits.enabled}},consumedunits | sort-object availableunits -descending

#Get License SKU
$o365 = Get-MgSubscribedSku -All | Where SkuPartNumber -eq 'EnterprisePack'
$m5365 = Get-MgSubscribedSku -All | Where SkuPartNumber -eq 'SPE_E5'
$idp2 = Get-MgSubscribedSku -All | Where SkuPartNumber -eq 'AAD_PREMIUM_P2'
$userid = read-host "Enter user UPN"

#Assign license for one user
$addLicenses = @(
@{SkuId = $EMSE3.SkuId
})
Set-MgUserLicense -UserId $userid -AddLicenses $addLicenses -RemoveLicenses @()

#Assign and remove simultaneously license for bulk users
$addLicenses = @(
@{SkuId = $m3365.SkuId
})
$file = read-host "Insert TXT Path"
foreach($user in get-content $file){
Set-MgUserLicense -UserId $user -AddLicenses @{skuid = $idp2.skuid} -RemoveLicenses  @($m5365.SkuId)
}

#Remove license for bulk users
$addLicenses = @(
@{SkuId = $m3365.SkuId
})
$file = read-host "Insert TXT Path"
foreach($user in get-content $file){
Set-MgUserLicense -UserId $user -AddLicenses @{} -RemoveLicenses  @($m5365.SkuId)
}

#Reprocess Bulk users License
$file = read-host "Insert TXT Path"
foreach($user in get-content $file){
Invoke-MgLicenseUser -UserId $user
}
