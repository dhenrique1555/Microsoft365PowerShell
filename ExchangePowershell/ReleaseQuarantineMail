$start = get-date
$messages = @()
[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
for($i = 0; $i -le 150; $i++){

$messages += Get-QuarantineMessage -PageSize 1000 -Page $i -ReleaseStatus notreleased  

}
[System.Windows.Forms.MessageBox]::Show('Search Ended','WARNING')
#$filterdomain = $messages | where-object {$_.SenderAddress -like "**"}

$filterdomainandquantity = $messages | where-object {$_.SenderAddress -like "*"} | select-object -first 10000
$messagestobereleased = $filterdomainandquantity | Release-QuarantineMessage -ReleaseToAll
[System.Windows.Forms.MessageBox]::Show('Release Ended','WARNING')

$GetNewStatus = $filterdomainandquantity | Get-QuarantineMessage
