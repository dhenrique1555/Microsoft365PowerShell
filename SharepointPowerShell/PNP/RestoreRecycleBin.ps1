#Restores files deleted by the Sharepoint System account
$SiteURL= ""
Connect-PnPOnline -Url $SiteURL -Interactive
$DeletedItems = Get-PnPRecycleBinItem -RowLimit 500000
$deletedbysystemaccount =($Deleteditems | where-object {$_.deletedbyname -eq "systemkonto"})
$deletedbysystemaccount | Restore-PnpRecycleBinItem -force

