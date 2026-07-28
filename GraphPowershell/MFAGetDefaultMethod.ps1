# Connect to Graph with the required scope
Connect-MgGraph -Scopes "UserAuthenticationMethod.Read.All", "AuditLog.Read.All" 

Write-Host "Fetching user registration details..." -ForegroundColor Cyan

# Example 1: Fetch for a single user
$TargetUser = "user@infios.com"
$SingleUserDetail = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -UserRegistrationDetailsId $TargetUser

Write-Host "`nDetails for $TargetUser" -ForegroundColor Yellow
Write-Host "Default Method configured: $($SingleUserDetail.DefaultMfaMethod)"
Write-Host "Is MFA Registered: $($SingleUserDetail.IsMfaRegistered)"
Write-Host "All Registered Methods: $($SingleUserDetail.MethodsRegistered -join ', ')"

# ---------------------------------------------------------

# Example 2: Fetch a bulk report for ALL users and export to CSV
Write-Host "`nFetching report for all users..." -ForegroundColor Cyan
$AllUsersDetails = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -All

$Report = foreach ($User in $AllUsersDetails) {
    [PSCustomObject]@{
        UserPrincipalName = $User.UserPrincipalName
        UserDisplayName   = $User.UserDisplayName
        IsMfaRegistered   = $User.IsMfaRegistered
        DefaultMfaMethod  = $User.DefaultMfaMethod
        MethodsRegistered = ($User.MethodsRegistered -join " | ")
    }
}

$ExportPath = ".\Default_MFA_Methods_Report.csv"
$Report | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8

Write-Host "Done! Full tenant report exported to $ExportPath" -ForegroundColor Green
