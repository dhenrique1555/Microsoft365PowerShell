# ==========================================
# 1. Configuration
# ==========================================
$ExportPath = "C:\Temp\DefaultSignInMethods.csv"

# ==========================================
# 2. Authentication
# ==========================================
Write-Host "Authenticating to Microsoft Graph..." -ForegroundColor Cyan

# Requires specific permission scopes to read authentication methods and reports
Connect-MgGraph -Scopes "UserAuthenticationMethod.Read.All", "AuditLog.Read.All" -NoWelcome

# ==========================================
# 3. Extraction
# ==========================================
Write-Host "`nExtracting User Registration Details (this may take a moment for large tenants)..." -ForegroundColor Yellow

# The Beta module is required to expose the DefaultMfaMethod property reliably
$RegistrationDetails = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -All

if ($null -ne $RegistrationDetails -and$RegistrationDetails.Count -gt 0) {
    Write-Host " -> Extracted $($RegistrationDetails.Count) user records. Formatting data..." 
    
    $Results = foreach ($User in $RegistrationDetails) {
        [PSCustomObject]@{
            UserPrincipalName = $User.UserPrincipalName
            UserDisplayName   = $User.UserDisplayName
            UserType          = $User.UserType
            IsAdmin           = $User.IsAdmin
            IsMfaRegistered   = $User.IsMfaRegistered
            IsSsprRegistered  = $User.IsSsprRegistered
            DefaultMfaMethod  = $User.DefaultMfaMethod
            MethodsRegistered = ($User.MethodsRegistered -join " | ")
        }
    }

    # ==========================================
    # 4. Export
    # ==========================================
    $Results |Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nData extraction complete." -ForegroundColor Green
    Write-Host "File saved locally to: $ExportPath"
} else {
    Write-Host "`nNo user registration details were found in this tenant." -ForegroundColor DarkGray
}
