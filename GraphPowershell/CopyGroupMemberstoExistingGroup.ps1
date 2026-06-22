Import-Module Microsoft.Graph.Groups

# 1. Define the names of your Source and Target groups
$SourceGroupName = ""
$TargetGroupName = ""

# 2. Find the Source Group and its ID
$SourceGroup = Get-MgGroup -Filter "displayName eq '$SourceGroupName'"
if (-not $SourceGroup) {
    Write-Error "Could not find a source group named '$SourceGroupName'."
    exit
}

# 3. Find the Target Group and its ID
$TargetGroup = Get-MgGroup -Filter "displayName eq '$TargetGroupName'"
if (-not $TargetGroup) {
    Write-Error "Could not find a target group named '$TargetGroupName'."
    exit
}

# 4. Grab all members from the Source Group
# Note: The -All switch is critical here to bypass the default 100-item limit
$SourceMembers = Get-MgGroupMember -GroupId $SourceGroup.Id -All

# 5. Loop through the source members and add them to the Target Group
foreach ($Member in $SourceMembers) {
    $MemberId = $Member.Id

    $params = @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$MemberId"
    }

    # try/catch block is used here because Graph will throw an error if the user is already in the group
    try {
        New-MgGroupMemberByRef -GroupId $TargetGroup.Id -BodyParameter $params
        Write-Host "Successfully added member ID $MemberId to $TargetGroupName." -ForegroundColor Green
    }
    catch {
        Write-Host "Skipped member ID $MemberId. They might already be in the target group." -ForegroundColor Yellow
    }
}
