$RequiredScopes = @("Directory.AccessAsUser.All"
"Directory.ReadWrite.All"
"AuditLog.Read.All"
"email"
"openid"
"Organization.Read.All"
"Policy.Read.All"
"profile"
"User.Read"
"User.Read.All"
"User.ReadWrite.All"
"AdministrativeUnit.ReadWrite.All"

)
Connect-MgGraph -Scopes $RequiredScopes
 Import-Module Microsoft.Graph.Identity.DirectoryManagement

$members = Get-MgGroupMember -Groupid 91262dd9-c4ce-4ef9-adf4-6b7e9360585a

foreach($user in $members.id){

	  

$params = @{
	"@odata.id" = "https://graph.microsoft.com/v1.0/users/$USER"
}

New-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $Id -BodyParameter $params

