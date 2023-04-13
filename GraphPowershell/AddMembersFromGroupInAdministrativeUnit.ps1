$RequiredScopes = @(
"GroupMember.Read.All"
"AdministrativeUnit.ReadWrite.All"

)

$groupid = read-host "Insert Group Object ID"
$AdministrativeUnitID = read-host "Insert Administrative Unit ID"
Connect-MgGraph -Scopes $RequiredScopes
 Import-Module Microsoft.Graph.Identity.DirectoryManagement

$members = Get-MgGroupMember -Groupid $groupid

foreach($user in $members.id){

	  

$params = @{
	"@odata.id" = "https://graph.microsoft.com/v1.0/users/$USER"
}

New-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $AdministrativeUnitID -BodyParameter $params

