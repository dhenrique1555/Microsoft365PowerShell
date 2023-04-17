$output = @()

$users = Get-AzureADUser -All $true

foreach ($user in $users) {
    $manager = Get-AzureADUserManager -ObjectId $user.ObjectId

    $data = New-Object -TypeName psobject

    $data | Add-Member -MemberType NoteProperty -Name UsersObjectId -Value $user.ObjectId
    $data | Add-Member -MemberType NoteProperty -Name UserUPN -Value $user.UserPrincipalName
    $data | Add-Member -MemberType NoteProperty -Name UserType -Value $user.UserType
    $data | Add-Member -MemberType NoteProperty -Name ManagersObjectId -Value $manager.ObjectId
    $data | Add-Member -MemberType NoteProperty -Name ManagerUPN -Value $manager.UserPrincipalName
    $data | Add-Member -MemberType NoteProperty -Name ManagerUserType -Value $manager.UserType
    $data | Add-Member -MemberType NoteProperty -Name ManagerDisplayName -Value $manager.DisplayName
    $output += $data

}

$output
