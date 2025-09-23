
# -----------------------------
# CONFIG
# -----------------------------
$TenantId = ""
$ClientId = ""
$ClientSecret = ""

# ===============================================
# Intune Data Warehouse Export Script (PowerShell)
# App Registration / App-Only Auth
# Handles paging & exports CSV
# ===============================================
# Resource and base URL
$Resource = "https://api.manage.microsoft.com/"
#Intune Datawarehouse URL in Intune Admin Portal
$BaseUrl = ""

# List of datasets to export
$Datasets = @(
    "appRevisions",
    "appTypes",
    "compliancePolicyStatusDeviceActivities",
    "compliancePolicyStatusDevicePerPolicyActivities",
    "complianceStates",
    "dates",
    "deviceCategories",
    "deviceConfigurationProfileDeviceActivities",
    "deviceConfigurationProfileUserActivities",
    "deviceEnrollmentTypes",
    "devicePropertyHistories",
    "deviceRegistrationStates",
    "devices",
    "deviceTypes",
    "enrollmentActivities",
    "enrollmentEventStatuses",
    "enrollmentFailureCategories",
    "enrollmentFailureReasons",
    "intuneManagementExtensionHealthStates",
    "intuneManagementExtensions",
    "intuneManagementExtensionVersions",
    "mamApplicationInstances",
    "mamApplications",
    "mamCheckins",
    "mamDeviceHealths",
    "mamPlatforms",
    "managementAgentTypes",
    "managementStates",
    "mobileAppInstallStates",
    "mobileAppInstallStatusCounts",
    "ownerTypes",
    "policies",
    "policyDeviceActivities",
    "policyPlatformTypes",
    "policyTypeActivities",
    "policyTypes",
    "policyUserActivities",
    "termsAndConditions",
    "userDeviceAssociations",
    "users",
    "userTermsAndConditionsAcceptances",
    "vppProgramTypes"
)


# Output folder
$OutputFolder = "$env:TEMP\IntuneDW"
if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder | Out-Null }

# -----------------------------
# GET APP-ONLY TOKEN
# -----------------------------
Write-Host "🔑 Acquiring app-only token..."
$Body = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    resource      = $Resource
}

$TokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.windows.net/$TenantId/oauth2/token" `
    -Body $Body -ContentType "application/x-www-form-urlencoded"

$AccessToken = $TokenResponse.access_token
$AuthHeader = @{ Authorization = "Bearer $AccessToken" }
Write-Host "✅ Token acquired successfully"

# -----------------------------
# FUNCTION TO HANDLE PAGING
# -----------------------------
function Get-DWData {
    param([string]$Url)

    $AllResults = @()
    $NextLink = $Url.Trim()
    $Page = 1
    $TotalFetched = 0

    while ($NextLink) {
        Write-Host "Fetching page $Page : $NextLink"
        try {
            $Response = Invoke-RestMethod -Uri $NextLink -Headers $AuthHeader -Method Get
        } catch {
            Write-Host "❌ Failed to fetch $NextLink : $_"
            break
        }

        if ($Response.value) {
            $Count = $Response.value.Count
            $TotalFetched += $Count
            Write-Host "  → Retrieved $Count rows (Total: $TotalFetched)"
            $AllResults += $Response.value
        }

        $Page++

        # Use nextLink exactly as returned, no modification
        if ($Response.'@odata.nextLink') {
            $NextLink = $Response.'@odata.nextLink'.Trim()
        } else {
            $NextLink = $null
        }
    }

    Write-Host "Finished fetching dataset. Total rows: $TotalFetched"
    return $AllResults
}

# -----------------------------
# EXPORT EACH DATASET TO CSV
# -----------------------------
foreach ($Dataset in $Datasets) {
    Write-Host "`n📦 Exporting dataset: $Dataset"
# Trim to remove any hidden characters
$BaseUrl = $BaseUrl.Trim()
$Dataset = $Dataset.Trim()

$InitialUrl = "$BaseUrl/$Dataset" + "?api-version=v1.0"

Write-Host "URL to call: $InitialUrl"
    $Data = Get-DWData -Url $InitialUrl

    if ($Data.Count -gt 0) {
        $CsvPath = Join-Path $OutputFolder "IntuneDW_$Dataset.csv"
        $Data | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "✅ Exported $($Data.Count) rows to $CsvPath"
    } else {
        Write-Host "⚠️ No data returned for dataset: $Dataset"
    }
}

Write-Host "`n🎉 All datasets exported successfully to $OutputFolder"
