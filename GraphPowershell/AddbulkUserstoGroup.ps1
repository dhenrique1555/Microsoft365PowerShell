Import-Module Microsoft.Graph.Groups
$users = get-content c:\temp\users.txt

foreach($user in $users){
$userinfo = get-mguser -userid $user
$id = $userinfo.id

$params = @{
	"@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$id"
}

New-MgGroupMemberByRef -GroupId e2121bd1-82ef-407e-8bf3-bcfd0144780b -BodyParameter $params
