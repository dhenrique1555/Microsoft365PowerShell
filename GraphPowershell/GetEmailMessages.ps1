#Get all mesages from a specific user
$User = read-host "Enter username"

Get-MgUserMessage -All -UserId "$User" -Filter "IsRead eq true" |
Select-Object Subject, InternetMessageId, ReceivedDateTime,
@{Name = "Sender"; Expression = { $_.Sender.EmailAddress.Address } }, 
@{Name = "Recipients"; Expression = { $_.ToRecipients.EmailAddress.Address -join ', ' } },isread,hasattachments,bodypreview |
Out-GridView
