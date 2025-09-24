# Requires Microsoft.Graph PowerShell SDK
# Install if needed:
# Install-Module Microsoft.Graph -Scope CurrentUser

Import-Module Microsoft.Graph

# Connect with required permissions
Connect-MgGraph -Scopes "Device.ReadWrite.All","Directory.ReadWrite.All","DeviceManagementManagedDevices.Read.All"

# Define stale threshold (in days)
$StaleDays = 90
$CutoffDate = (Get-Date).AddDays(-$StaleDays)

Write-Host "Checking for stale Android/iOS devices not active since before $CutoffDate..."

# Get Entra ID devices
$AADDevices = Get-MgDevice -All

# Get Intune managed devices
$IntuneDevices = Get-MgDeviceManagementManagedDevice -All

# Build lookup table for Intune last check-in
$IntuneLookup = @{}
foreach ($dev in $IntuneDevices) {
    if ($dev.AzureADDeviceId) {
        # Choose best available check-in field
        $CheckIn = $null
        if ($dev.LastSyncDateTime) {
            $CheckIn = $dev.LastSyncDateTime
        } elseif ($dev.LastContactedDateTime) {
            $CheckIn = $dev.LastContactedDateTime
        } elseif ($dev.EnrolledDateTime) {
            $CheckIn = $dev.EnrolledDateTime
        }

        $IntuneLookup[$dev.AzureADDeviceId] = @{
            CheckIn = $CheckIn
            Source  = if ($dev.LastSyncDateTime) { "LastSyncDateTime" }
                      elseif ($dev.LastContactedDateTime) { "LastContactedDateTime" }
                      elseif ($dev.EnrolledDateTime) { "EnrolledDateTime" }
                      else { "None" }
        }
    }
}

# Analyze Entra devices
$StaleDevices = @()

foreach ($AAD in $AADDevices) {
    if ($AAD.OperatingSystem -notmatch "Android|iOS") { continue }

    $LastSignIn = $AAD.ApproximateLastSignInDateTime
    $LastCheckIn = $null
    $CheckInSource = "None"

    if ($IntuneLookup.ContainsKey($AAD.Id)) {
        $LastCheckIn   = $IntuneLookup[$AAD.Id].CheckIn
        $CheckInSource = $IntuneLookup[$AAD.Id].Source
    }

    # Pick the most recent timestamp
    $MostRecent = $LastSignIn
    if ($LastCheckIn -and (!$MostRecent -or $LastCheckIn -gt $MostRecent)) {
        $MostRecent = $LastCheckIn
    }

    # If no timestamps exist or the most recent is too old, mark as stale
    if (-not $MostRecent -or $MostRecent -lt $CutoffDate) {
        # Get owner(s)
        $Owners = Get-MgDeviceRegisteredOwner -DeviceId $AAD.Id -All -ErrorAction SilentlyContinue
        $OwnerNames = @()
        foreach ($Owner in $Owners) {
            if ($Owner.AdditionalProperties.userPrincipalName) {
                $OwnerNames += $Owner.AdditionalProperties.userPrincipalName
            } elseif ($Owner.AdditionalProperties.displayName) {
                $OwnerNames += $Owner.AdditionalProperties.displayName
            }
        }
        $OwnerList = if ($OwnerNames.Count -gt 0) { ($OwnerNames -join "; ") } else { "No owner" }

        $obj = [PSCustomObject]@{
            DisplayName     = $AAD.DisplayName
            Id              = $AAD.Id
            OperatingSystem = $AAD.OperatingSystem
            LastSignIn      = $LastSignIn
            LastCheckIn     = $LastCheckIn
            CheckInSource   = $CheckInSource
            MostRecent      = $MostRecent
            Owner           = $OwnerList
        }

        $StaleDevices += $obj
    }
}

if ($StaleDevices.Count -eq 0) {
    Write-Host "No stale Android/iOS devices found."
} else {
    Write-Host "Found $($StaleDevices.Count) stale Android/iOS devices older than $StaleDays days."

    foreach ($Device in $StaleDevices) {
        Write-Host "Deleting stale AAD device: $($Device.DisplayName) - Owner: $($Device.Owner) - Last Activity: $($Device.MostRecent)"
        # Remove-MgDevice -DeviceId $Device.Id -Confirm:$false
    }

    # Export report
    $StaleDevices | Export-Csv -Path ".\StaleDevicesReport.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "Exported stale devices report to StaleDevicesReport.csv"
}
