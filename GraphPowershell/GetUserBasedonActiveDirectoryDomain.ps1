$Date = (Get-Date).AddDays(0).AddHours(-2).AddMinutes(-(Get-Date).Minute).AddSeconds(-(Get-Date).Second).AddMilliseconds(-(Get-Date).Milliseconds)

Write-Host
Write-Host "Downloading data... Start time:" $(Get-Date -Format "hh:mm:ss")
$output = @()
$data = @()

$organization = "votorantimindustrial.onmicrosoft.com"
Connect-ExchangeOnline -ManagedIdentity -Organization $organization
Get-AcceptedDomain | Format-Table -AutoSize

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

#Extract the access token from the AzAccount authentication context and use it to connect to Microsoft Graph
$token = (Get-AzAccessToken -ResourceTypeName MSGraph).token
Connect-MgGraph -AccessToken $token
gET-MGCONTEXT | SELECT -EXPANDPROPERTY scoPES   

  
  $users1 = Get-MgUser -Filter "onPremisesDomainName eq 'auren.votorantim.grupo'" -Property "accountEnabled, assignedLicenses, companyName, createdDateTime, department, displayName, employeeId, givenName, id, jobTitle, mail, officeLocation, onPremisesDistinguishedName, onPremisesDomainName, onPremisesExtensionAttributes, onPremisesSamAccountName, onPremisesSecurityIdentifier, onPremisesUserPrincipalName, postalCode, state, streetAddress, surname, usageLocation, userPrincipalName, userType, city, extensionAttribute12, manager"
  









18181a46-0d4e-45cd-891e-60aabd171b4e

GET https://graph.microsoft.com/v1.0/users?$select=id,mail,assignedLicenses&$filter=assignedLicenses/any(u:u/skuId eq 18181a46-0d4e-45cd-891e-60aabd171b4e)