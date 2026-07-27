# Connect to Microsoft Graph using the Beta profile
Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All" -Profile Beta

Write-Host "Fetching sign-in logs using the Beta endpoint..." -ForegroundColor Cyan

# Set your target lookback period (e.g., last 7 days)
$LookbackDate = (Get-Date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Fetch sign-in logs with the Beta cmdlet to expose rich AuthenticationDetails
$SignInLogs = Get-MgBetaAuditLogSignIn -All -Filter "createdDateTime ge $LookbackDate" 

Write-Host "Processing and flattening data..." -ForegroundColor Cyan
$results = foreach ($log in $SignInLogs) {
    
    $methods = @()

    # 1. Check the detailed Beta authentication steps
    if ($log.AuthenticationDetails) {
        foreach ($step in $log.AuthenticationDetails) {
            
            # CORRECTED: The property is AuthenticationMethod (e.g., "Text message")
            if (![string]::IsNullOrWhiteSpace($step.AuthenticationMethod)) {
                $methods += $step.AuthenticationMethod
            }
            # Legacy/custom mapping fallback just in case
            elseif (![string]::IsNullOrWhiteSpace($step.AuthenticationMethodUsed)) {
                $methods += $step.AuthenticationMethodUsed
            }
            # Fallback to result detail ONLY if the method is genuinely blank
            elseif (![string]::IsNullOrWhiteSpace($step.AuthenticationStepResultDetail)) {
                $methods += $step.AuthenticationStepResultDetail
            }
        }
    }

    # 2. Check the specific Authenticator App details 
    if ($log.AuthenticationAppDeviceDetails -and !([string]::IsNullOrWhiteSpace($log.AuthenticationAppDeviceDetails.ClientApp))) {
        $methods += $log.AuthenticationAppDeviceDetails.ClientApp
    }

    # Consolidate methods, remove duplicates, and join them with a pipe
    $authMethods = if ($methods.Count -gt 0) {
        ($methods | Select-Object -Unique) -join " | "
    } else {
        if (![string]::IsNullOrWhiteSpace($log.AuthenticationRequirement)) {
            $log.AuthenticationRequirement
        } else {
            "None/Unknown"
        }
    }

    # Flatten the object to perfectly match the columns in your initial image
    [PSCustomObject]@{
        id                      = $log.Id
        createdDateTime         = $log.CreatedDateTime
        userPrincipalName       = $log.UserPrincipalName
        userDisplayName         = $log.UserDisplayName
        userId                  = $log.UserId
        appId                   = $log.AppId
        appDisplayName          = $log.AppDisplayName
        isInteractive           = $log.IsInteractive
        clientAppUsed           = $log.ClientAppUsed
        conditionalAccessStatus = $log.ConditionalAccessStatus
        correlationId           = $log.CorrelationId
        resourceId              = $log.ResourceDisplayName 
        resourceDisplayName     = $log.ResourceDisplayName
        riskEventTypes          = ($log.RiskEventTypes_v2 -join ", ")
        riskLevelDuringSignIn   = $log.RiskLevelDuringSignIn
        riskDetail              = $log.RiskDetail
        StatusErrc              = $log.Status.ErrorCode
        StatusFail              = $log.Status.FailureReason
        IPAddress               = $log.IpAddress
        City                    = $log.Location.City
        State                   = $log.Location.State
        Country                 = $log.Location.CountryOrRegion
        Latitude                = $log.Location.GeoCoordinates.Latitude
        Longitude               = $log.Location.GeoCoordinates.Longitude
        DeviceID                = $log.DeviceDetail.DeviceId
        DeviceDis               = $log.DeviceDetail.DisplayName
        DeviceOS                = $log.DeviceDetail.OperatingSystem
        DeviceBro               = $log.DeviceDetail.Browser
        DeviceIsC               = $log.DeviceDetail.IsCompliant
        DeviceIsM               = $log.DeviceDetail.IsManaged
        DeviceTru               = $log.DeviceDetail.TrustType
        authenticationMethod    = $authMethods
    }
}

# Define the output path for the CSV file
$exportPath = ".\SignInLogs_Beta_Extracted.csv"

# Export the results to a CSV file
$results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

Write-Host "Done! Results exported to $exportPath" -ForegroundColor Green
