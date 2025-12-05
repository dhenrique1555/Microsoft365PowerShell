 
  #Connect to Microsoft Graph
# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

#Extract the access token from the AzAccount authentication context and use it to connect to Microsoft Graph
$token = (Get-AzAccessToken -ResourceTypeName MSGraph).token

$securetoken = ConvertTo-SecureString -String $token -ASPLAINTEXT -force
Connect-MgGraph -AccessToken $token
Get-mgcontext | Select -expandproperty Scopes 

 #StorageAccountVariables
$StorageAccountName = ''
$StorageAccountKey = ""
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = 'AllAppsProperties.csv'
$ContainerName  = ''
 




$AssignmentIncludeAllUsers="#microsoft.graph.allLicensedUsersAssignmentTarget"    #Target type of assignment that represents an 'All users' inclusion assignment
$AssignmentExclusionTarget="#microsoft.graph.exclusionGroupAssignmentTarget"  #Target type of assignment that represents an exclusion assignment
$AssignmentIncludeAllDevices="FUTURE"    #Target type of assignment that represents an 'All device' inclusion assignment
$csvfile = "$Env:temp/AllAppsProperties.csv"
Write-Host "Getting the list of apps. Please wait....."
$apps = Get-MgBetaDeviceAppManagementMobileApp -All -ExpandProperty Assignments  -ErrorAction Stop
Write-Host "Total apps found: $($apps.Count), extracting the data of each application" -ForegroundColor Cyan
# Initialize an array to store the app information
$appInfoList = @()
foreach ($app in $apps) {
$appname = $app.displayname
   If ($app.Assignments)
            {
            #This application is assigned.  Lets capture each group that it is assigned to and indicate include / exclude, required / available / uninstall
            $Assignments=""
            foreach ($Assignment in $app.assignments)
                {
                #for each assignment, get the intent (required / available / uninstall)
                $AssignmentIntent=$Assignment.intent
                if ($Assignment.target.AdditionalProperties."@odata.type" -eq $AssignmentExclusionTarget)
                    {
                    #This is an exclusion assignment
                    $AssignmentMode="exclude"
                    $AssignmentGroupName=""
                    }
                elseif ($Assignment.target.AdditionalProperties."@odata.type" -eq $AssignmentIncludeAllUsers)
                    {
                    #This is the all users assignment!
                    $AssignmentMode="include"
                    $AssignmentGroupName="All users"
                    }
                elseif ($Assignment.target.AdditionalProperties."@odata.type" -eq $AssignmentIncludeAllDevices)
                    {
                    #This is the all devices assignment!
                    $AssignmentMode="include"
                    $AssignmentGroupName="All devices"
                    }
                else
                    {
                    #This is an inclusion assignment
                    $AssignmentMode="include"
                    $AssignmentGroupName=""
                    }
                #Get the name corresponding to the assignment groupID (objectID in Azure)
                if ($AssignmentGroupName -eq "")
                    {
                    $AssignmentGroupID=$($Assignment.target.AdditionalProperties."groupId")   #"groupId" is case sensitive!
                    if ($null -ne $AssignmentGroupID)
                        {
                        <#
                        Permissions required as per: https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.groups/get-mggroup?view=graph-powershell-1.0
                        GroupMember.Read.All
                        #>
                        try
                            {
                            $AssignmentGroupName=$(Get-MgGroup -GroupId $AssignmentGroupID -ErrorAction Stop).displayName
                            #If here, the group assignment on the app is still valid
                            }
                        catch
                            {
                            #If here, the group assignment on the app is invalid (the group no longer exists)
                            Write-Host "Group ID $($AssignmentGroupID) on app $appname no longer exists!"
                            $AssignmentGroupName=$AssignmentGroupID + "_NOTEXIST"
                            }
                        }
                    else
                        {
                        #if we cannot search for it
                        $AssignmentGroupName="UNKNOWN"
                        }
                    }
                #Save the assignment info
                If ($Assignments -eq "")
                    {
                    #First assignment for this app
                    $Assignments="$AssignmentIntent / $AssignmentMode / " + $AssignmentGroupName
                    }
                else
                    {
                    #additional assignment for this app
                    $Assignments=$Assignments + "`n" + "$AssignmentIntent / $AssignmentMode / " + $AssignmentGroupName
                    }
                }
            }
        else
            {
            #This application isn't assigned
            $Assignments="NONE"
            }
			
# Process detection rules
# Process detection rules
$detectionRules = @()
$detectionDetails = @()

if ($null -ne $app.AdditionalProperties.detectionRules) {
    foreach ($rule in $app.AdditionalProperties.detectionRules) {
        switch ($rule.'@odata.type') {
            "#microsoft.graph.win32LobAppProductCodeDetection" {
                $detectionRules += "MSI"
                $detectionDetails += "MSI ProductCode: $($rule.productCode)"
            }
            "#microsoft.graph.win32LobAppRegistryDetection" {
                $detectionRules += "Registry"
                $detectionDetails += "Registry: $($rule.keyPath)\$($rule.valueName) | Type: $($rule.detectionType)"
            }
            "#microsoft.graph.win32LobAppFileSystemDetection" {
                $detectionRules += "FileSystem"
                $detectionDetails += "FileSystem: $($rule.path)\$($rule.fileOrFolderName) | Type: $($rule.detectionType)"
            }
            "#microsoft.graph.win32LobAppPowerShellScriptDetection" {
                $detectionRules += "Script"
                $detectionDetails += "Script: $($rule.scriptContent)"
            }
            default {
                $detectionRules += "Unknown"
                $detectionDetails += "Unknown rule type: $($rule.'@odata.type')"
            }
        }
    }
}

# Convert to strings for CSV output
$detectionRulesString = $detectionRules -join ", "
$detectionDetailsString = $detectionDetails -join " | "


# Process requirement rules
    $requirementRules = @()
    $requirementDetails = @()
    $requirementRuleScript = "NONE"
	 if ($null -ne $app.AdditionalProperties.requirementRules) {
        foreach ($rule in $app.AdditionalProperties.requirementRules) {
            $ruleType = switch ($rule.'@odata.type') {
                "#microsoft.graph.win32LobAppPowerShellScriptRequirement" {
                    $requirementDetails += "Script: $($rule.displayName)"
                    "Script"
                    break
                }
                "#microsoft.graph.win32LobAppRegistryRequirement" {
                    $requirementDetails += "Registry: $($rule.keyPath)\$($rule.valueName)"
                    "Registry"
                    break
                }
                "#microsoft.graph.win32LobAppFileSystemRequirement" {
                    $requirementDetails += "FileSystem: $($rule.path)\$($rule.fileOrFolderName)"
                    "FileSystem"
                    break
                }
                "#microsoft.graph.win32LobAppProductCodeRequirement" {
                    $requirementDetails += "MSI"
                    "MSI"
                    break
                }
                default { "Unknown"; break }
            }
            $requirementRules += $ruleType
        }
    }

    $requirementRulesString = $requirementRules -join ", "
    $requirementDetailsString = $requirementDetails -join " | "

 # Check dependencies
    $HasDependencies = if ($app.dependentAppCount -gt 0) { "Yes" } else { "No" }

    # Add the app information to the list
    $appInfoList += [PSCustomObject]@{
		AppID				  =  $app.ID	
        displayName           = $app.DisplayName
        displayVersion        = $app.AdditionalProperties.displayVersion
        description           = $app.description
        publisher             = $app.publisher
        setupFilePath         = $app.AdditionalProperties.setupFilePath
        installCommandLine    = $app.AdditionalProperties.installCommandLine
        uninstallCommandLine  = $app.AdditionalProperties.uninstallCommandLine
        allowedArchitectures=$app.AdditionalProperties.allowedArchitectures
        detectionRules        = $detectionRulesString
        detectionDetails      = $detectionDetailsString
        requirementRules      = $requirementRulesString
        requirementDetails    = $requirementDetailsString
        hasDependencies       = $HasDependencies
        createdDateTime       = (([datetime]$app.createdDateTime).ToLocalTime()).ToString("MM/dd/yyyy HH:mm:ss")
        lastModifiedDateTime  = (([datetime]$app.lastModifiedDateTime).ToLocalTime()).ToString("MM/dd/yyyy HH:mm:ss")
        owner                 = $app.owner
        developer             = $app.developer
        notes                 = $app.notes
        uploadState           = $app.uploadState
        publishingState       = $app.publishingState
        isAssigned            = $app.isAssigned
        Assignments           = $Assignments
       

    }
}

# Export the app information to a CSV file
$appInfoList | Export-Csv -Path $csvfile -NoTypeInformation -Encoding UTF8

 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $csvfile -Blob $FileName -Force
