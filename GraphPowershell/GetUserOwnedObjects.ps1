# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Directory.Read.All", "User.Read.All", "Application.Read.All"

# Prompt for UPN
$userPrincipalName = Read-Host "Enter the User Principal Name (UPN) of the user"

# Get user object
$user = Get-MgUser -UserId $userPrincipalName

# Get all objects the user owns
$ownedObjects = Get-MgUserOwnedObject -UserId $user.Id -All

# Prepare progress bar
$total = $ownedObjects.Count
$counter = 0
$detailsList = @()

# Loop through each object and get full details
foreach ($obj in $ownedObjects) {
    $counter++
    Write-Progress -Activity "Retrieving owned object details" -Status "Processing $counter of $total" -PercentComplete (($counter / $total) * 100)

    try {
        # Determine the type of object
        $type = $obj.AdditionalProperties.'@odata.type'

        switch ($type) {
            "#microsoft.graph.group" {
                $details = Get-MgGroup -GroupId $obj.Id -Property "Id,DisplayName,Description,GroupTypes,SecurityEnabled,Visibility,CreatedDateTime,RenewedDateTime"
                $details | Add-Member -NotePropertyName "ObjectType" -NotePropertyValue "Group"
            }
            "#microsoft.graph.team" {
                $details = Get-MgTeam -TeamId $obj.Id
                $details | Add-Member -NotePropertyName "ObjectType" -NotePropertyValue "Team"
            }
            "#microsoft.graph.application" {
                $details = Get-MgApplication -ApplicationId $obj.Id -Property "Id,DisplayName,AppId,SignInAudience,CreatedDateTime"
                $details | Add-Member -NotePropertyName "ObjectType" -NotePropertyValue "Application"
            }
            "#microsoft.graph.servicePrincipal" {
                $details = Get-MgServicePrincipal -ServicePrincipalId $obj.Id -Property "Id,DisplayName,AppId,AppOwnerOrganizationId,ServicePrincipalType,CreatedDateTime"
                $details | Add-Member -NotePropertyName "ObjectType" -NotePropertyValue "ServicePrincipal"
            }
            "#microsoft.graph.plannerGroup" {
                $details = Get-MgPlannerGroup -PlannerGroupId $obj.Id
                $details | Add-Member -NotePropertyName "ObjectType" -NotePropertyValue "PlannerGroup"
            }
            "#microsoft.graph.drive" {
                $details = Get-MgDrive -DriveId $obj.Id
                $details | Add-Member -NotePropertyName "ObjectType" -NotePropertyValue "Drive"
            }
            default {
                $details = [PSCustomObject]@{
                    Id = $obj.Id
                    ObjectType = $type
                }
            }
        }

        $detailsList += $details
    }
    catch {
        Write-Warning "Skipping object $($obj.Id) - Reason: $($_.Exception.Message)"
    }
}

# Export results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "OwnedObjects_$($userPrincipalName)_$timestamp.csv"
$detailsList | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Export completed: $outputFile"
