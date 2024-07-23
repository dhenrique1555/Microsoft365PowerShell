 
#Get all Sites in Environment
$sites = get-sposite -limit all
#This Will run the versioning limit against all libraries in all sites
foreach($site in $sites){
#Set the Site for the organization number of versions (will apply only to new libraries)
set-sposite -identity $site.url-InheritVersionPolicyFromTenant
 
#Now the Script will go through each library and set the new Maximum Versions for New files inside it - THIS WILL NOT TRIM EXISTING VERSIONS
set-sposite -identity $site.url -ApplyToExistingDocumentLibraries -MajorVersionLimit 50 -EnableAutoExpirationVersionTrim $false -ExpireVersionsAfterDays 0 -MajorWithMinorVersionsLimit  0 -confirm:$false
 
 
}
