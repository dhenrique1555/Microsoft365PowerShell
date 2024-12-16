Start-transcript
#Measure-Command{
$searchname = read-host "Enter Compliance Search Name"
$purgename = $searchname + "_Purge"
$user = read-host "Enter Mailbox UserName"
Do {
     “Starting Loop for Compliance Search Deletion”
New-ComplianceSearchAction -SearchName $searchname -Purge -PurgeType HardDelete -Confirm:$false


DO
{

 “Starting Loop for Compliance Search Status”
 Start-sleep -seconds 15
$actionstatus = get-ComplianceSearchAction -identity $purgename

$actionstatus.status



} Until ($actionstatus.Status -eq "Completed")
 “Starting Loop for Compliance Search Action Deletion”
Remove-ComplianceSearchAction $purgename -confirm:$false
 “Starting Loop for Folder Stats”
$folderrecoverablestatistics = Get-MailboxFolderStatistics $user -FolderScope RecoverableItems | select Name,FolderAndSubfolderSize,ItemsInFolderAndSubfolders
$folderstatistics = Get-MailboxFolderStatistics $user | select Name,FolderAndSubfolderSize,ItemsInFolderAndSubfolders
$purgesstats= $folderrecoverableStatistics | where-object {$_.Name -eq "Purges"}
$purgesstats | ft
$excludeditemsstats = $folderStatistics | where-object {$_.Name -eq "Itens Excluídos"}
$excludeditemsstats | ft
$junkfolderstats = $folderStatistics | where-object {$_.Name -eq "Lixo Eletrônico"}
$junkfolderstats |ft
} Until($purgesstats.ItemsInFolderAndSubfolders -le "10000")
#}
Stop-Transcript
