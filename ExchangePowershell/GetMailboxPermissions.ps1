###Script intended for use on Azure Automation but also usable for Powershell Desktop
###This Script can take a really long time to run depending on the environment size
##Connection to Exchange Online
#Input the tenant domain
$organization = ""
Connect-ExchangeOnline -ManagedIdentity -Organization $organization


#Storage Account Variables (to save the file on a Storage)
$StorageAccountName = ""
$StorageAccountKey = ""
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = 'PermissionsMailbox.csv'
$ContainerName  = ''

#Case 1: Get all permissions for all mailboxes
$mbxes = Get-Mailbox -ResultSize unlimited
$users = $mbxes

#Run once
$permissions = @()
foreach($user in $users){
foreach($mbx in $mbxes){
$mbxname = $mbx.displayname
Write-host "Searching $mbxname for $user"
$Permissions += $mbx | get-mailboxpermission -user $user}
}
$permissions | Export-Csv $Env:temp/PermissionsMailbox.csv -notypeinformation
#Salva no Storage Account

$FileName = 'PermissionsMailbox.csv'

Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File "$Env:temp/PermissionsMailbox.csv" -Blob $FileName -Force
