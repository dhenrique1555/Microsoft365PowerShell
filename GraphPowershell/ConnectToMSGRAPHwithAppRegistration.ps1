#ConnectGraph
$ApplicationID = read-host "Insert App ID"
$TenatDomainName = read-host "Insert Tenant Root Domain"
$AccessSecret = read-host "Insert App Secret"



$Body = @{    
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    client_Id     = $ApplicationID
    Client_Secret = $AccessSecret
}



$ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenatDomainName/oauth2/v2.0/token" -Method POST -Body $Body
$token = $ConnectGraph.access_token



Connect-mggraph -accesstoken $token
