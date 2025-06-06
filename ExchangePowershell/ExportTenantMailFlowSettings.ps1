
#-----------------------------Authentication------------------------------------#
$AppId = ""
$CertificateThumbprint = ""
$Organization = ""
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $CertificateThumbprint -Organization $Organization -ShowBanner:$false
Write-Output $env:COMPUTERNAME": Connected to Exchange Online"

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext



#Required Modules
#ImportExcel
#ExchangeonlineManagement

#Set Excel Filename for all outputs
$excelfilename = "c:\temp\MailFlowSettings.xlsx"

#StorageAccountProperties to Save File

$StorageAccountName = ''
$StorageAccountKey = ""
#$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = ""
$ContainerName  = ''

Measure-Command {

#Save Mail Flow Settings to Variables
$orgconfig = Get-OrganizationConfig
$trules = Get-TransportRule
$outspam = Get-HostedOutboundSpamFilterPolicy
$phish = Get-AntiPhishPolicy
$malware = Get-MalwareFilterPolicy
$ipfilter = Get-HostedConnectionFilterPolicy
$spoofedsender = Get-TenantAllowBlockListSpoofItems

$allowsender = Get-TenantAllowBlockListItems -listtype sender -allow 
$allowurl = Get-TenantAllowBlockListItems -listtype url -allow 
$allowIP = Get-TenantAllowBlockListItems -listtype IP -allow
$blocksender = Get-TenantAllowBlockListItems -listtype sender -block
$blockurl = Get-TenantAllowBlockListItems -listtype url -block 
$blockIP = Get-TenantAllowBlockListItems -listtype IP -block
$spam = Get-HostedContentFilterPolicy
$inconnector = Get-InboundConnector
$outconnector = Get-OutboundConnector
$retentionpolicies = Get-RetentionCompliancePolicy
$accepteddomains = Get-AcceptedDomain

$orgconfig  | Export-excel $excelfilename -worksheetname "OrgConfigExchange"
$trules  | Export-excel $excelfilename -worksheetname "TransportRules"
$outspam| Export-excel $excelfilename -worksheetname "OutboundSpamPolicy"
$phish| Export-excel $excelfilename -worksheetname "InboundPhishingPolicy"
$malware | Export-excel $excelfilename -worksheetname "InboundMalwarePolicy"
$ipfilter| Export-excel $excelfilename -worksheetname "InboundIPFilteringPolicy"
$spoofedsender| Export-excel $excelfilename -worksheetname "InboundSpoofedSenders"
$AllowblockFileHash | Export-excel $excelfilename -worksheetname "InboundAllowBlockListFileHash"
$allowblocksender| Export-excel $excelfilename -worksheetname "InboundAllowBlockListSender"
$allowblockurl| Export-excel $excelfilename -worksheetname "InboundAllowBlockListURL"
$allowblockIP| Export-excel $excelfilename -worksheetname "InboundAllowBlockListIPAddress"
$spam| Export-excel $excelfilename -worksheetname "InboundSpamPolicy"
$inconnector| Export-excel $excelfilename -worksheetname "InboundConnectors"
$outconnector| Export-excel $excelfilename -worksheetname "OutBoundConnectors"
$retentionpolicies| Export-excel $excelfilename -worksheetname "RetentionPolicies"
$accepteddomains| Export-excel $excelfilename -worksheetname "AcceptedDomains"

}

#Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename -Blob $FileName -Force

}
