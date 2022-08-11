#Add One User
$adminurl = read-host "Insert AdminURL of Sharepoint"
$credential = read-host "Insert Sharepoint Admin Credential"
#Connect to SharePoint Online
Connect-SPOService -url $AdminURL -credential $Credential
$site = read-host "Enter Sharepoint Site"
$username = read-host "Enter User"
#Grant Sharepoint Admin administrative rights on Site
Set-SPOUser -Site $site -LoginName $credential -IsSiteCollectionAdmin $true
#Get Site Groups 
Get-SPOSiteGroup -Site $site | ft
$group = read-host "Enter Permission Group Name"
#Add member in sharepoint site
Add-SPOUser -Site $site -LoginName $username  -Group $group
#Get Permission group members
Get-spouser -site $site -group $group | ft displayname,usertype, @{n="PermissionType";e={"$group"}}
#Remove Admin on Group
Set-SPOUser -Site $site -LoginName $credential -IsSiteCollectionAdmin $false
 
#Bulk Add Users

#Credentials
$adminurl = read-host "Insert AdminURL of Sharepoint"
$credential = read-host "Insert Sharepoint Admin Credential"
Connect-SPOService -url $AdminURL -credential $Credential
#Grant Sharepoint Admin administrative rights on Site
Set-SPOUser -Site $site -LoginName $credential -IsSiteCollectionAdmin $true
#Get Site Groups 
Get-SPOSiteGroup -Site $site | ft
#Group to Add Users
$groupname = read-host "Enter Group Name"
#Site to add users
$site = read-host "Enter Site Link"
#Path of TXT file with user list
$file = read-host "Insert TXT file wish user list path"
$users = Get-Content $file
#Add users
foreach ( $upn in $users ) {
Add-SPOUser -Site $site -LoginName $upn  -Group $groupname}
#Get Updated Site Group members
Get-spouser -site $site -group $group | ft displayname,usertype, @{n="PermissionType";e={"$group"}}
#Remove Admin on Group
Set-SPOUser -Site $site -LoginName $credential -IsSiteCollectionAdmin $false
