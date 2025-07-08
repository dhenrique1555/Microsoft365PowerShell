$SiteURL = ""
$ListName = "Permanentes Dokumentarchiv"
  
#Connect to PnP Online
Connect-PnPOnline -Url $SiteURL -Interactive
 
#Delete all files from the library
Get-PnPList -Identity $ListName | Get-PnPListItem -PageSize 100 -ScriptBlock {
    Param($items) Invoke-PnPQuery } | ForEach-Object { $_.Recycle() | Out-Null
}

$deleteitems = Get-PnPRecycleBinItem | where-object {$_.deletedbyemail -eq "adm_danilo.pinheiro@kscsglobal.onmicrosoft.com"}
$deleteitems | Clear-PnpRecycleBinItem -force
