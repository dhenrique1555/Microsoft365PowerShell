# Grant policy for Bulk Users
$objectids1 = @()
$file = read-host "Insert User list file path"
foreach ( $upn in Get-content $file) {
$Objectids1 += (Get-msoluser -userprincipalname $upn | select Objectid).objectid
}

$policy = read-host "Insert PolicyName"
foreach ( $objectid in $objectids) {
grant-csapplicationaccesspolicy -policyname $Policy -identity $objectids1
}

#Grant Policy for Single User
$user = read-host "Insert User UPN"
$objectid = @()
$Objectid += (Get-msoluser -userprincipalname $user | select Objectid).objectid
$policy = read-host "Insert PolicyName"
grant-csapplicationaccesspolicy -policyname $Policy -identity $objectid



