$StartDate = get-date
###Script intended for use on Azure Automation but also usable for Powershell Desktop with some minor changes
#Connect Exchange Online
$organization = ""
Connect-ExchangeOnline -ManagedIdentity -Organization $organization

#StorageAccountVariables
$StorageAccountName = ''
$StorageAccountKey = ""
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = 'MailboxArchive.csv'
$ContainerName  = ''


$Result=@() 
#Get all user mailboxes for a specific domain(remove the filter if not necessary)
$mailboxes =  Get-Mailbox -ResultSize unlimited -Filter {EmailAddresses -like "*domain.com"}
$totalmbx = $mailboxes.Count
$i = 0 
$mailboxes | ForEach-Object {
$i++
$mbx = $_
$size = $null
 
Write-Progress -activity "Processing $mbx" -status "$i out of $totalmbx completed"
 
if ($mbx.ArchiveStatus -eq "Active"){
#Get archive mailbox statistics
$mbs = Get-MailboxStatistics $mbx.UserPrincipalName -Archive
 
if ($mbs.TotalItemSize -ne $null){
$size = [math]::Round(($mbs.TotalItemSize.ToString().Split('(')[1].Split(' ')[0].Replace(',','')/1MB),2)
}else{
$size = 0 }
}
 
$Result += New-Object -TypeName PSObject -Property $([ordered]@{ 
UserName = $mbx.DisplayName
UserPrincipalName = $mbx.UserPrincipalName
RecipientType = $mbx.RecipientTypeDetails
ArchiveStatus =$mbx.ArchiveStatus
ArchiveName =$mbx.ArchiveName
ArchiveState =$mbx.ArchiveState
ArchiveMailboxSizeInMB = $size
ArchiveWarningQuota=if ($mbx.ArchiveStatus -eq "Active") {$mbx.ArchiveWarningQuota} Else { $null} 
ArchiveQuota = if ($mbx.ArchiveStatus -eq "Active") {$mbx.ArchiveQuota} Else { $null} 
AutoExpandingArchiveEnabled=$mbx.AutoExpandingArchiveEnabled
})
}
$Result | Export-CSV "$Env:temp/MailboxArchive.csv" -NoTypeInformation -Encoding UTF8

Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File "$Env:temp/MailboxArchive.csv" -Blob $FileName -Force

$Enddate = get-date 

#Send Report Email
$credObject = Get-AutomationPSCredential -Name "O365"

$attachment = Get-AzStorageBlobContent -Container $ContainerName -Blob $FileName -Context $StorageContext
$emailattachment = $anexo.name

Send-MailMessage -Credential $credObject -From "" -To "" -Subject "Status Archive" -Body "Start Time: $Inicio `n `n Report generated! `n `n TERMINO: $Enddate" -SmtpServer "outlook.office365.com" -UseSSL -Attachments $emailattachment -Encoding UTF8
