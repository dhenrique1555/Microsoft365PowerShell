# ==============================================================================
# Variables Configuration
# ==============================================================================
$clientId       = "YOUR-APP-CLIENT-ID"
$tenantId       = "YOUR-TENANT-ID"
$targetSubject  = "Your Meeting Subject Here" # The exact or partial subject of the meeting
$outputFolder   = "C:\temp\Transcripts"       # Folder to save the .vtt files

# Calculate a 60-day window to search your calendar (30 days back, 30 days forward)
$start = (Get-Date).AddDays(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$end   = (Get-Date).AddDays(30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Ensure destination folder exists
if (-not (Test-Path $outputFolder)) { 
    New-Item -ItemType Directory -Path $outputFolder | Out-Null 
}

# ==============================================================================
# Step 1: Authenticate
# ==============================================================================
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -ClientId $clientId -TenantId $tenantId -Scopes "OnlineMeetings.Read, OnlineMeetingTranscript.Read.All, Calendars.Read"

$myUserId = (Get-MgContext).Account

# ==============================================================================
# Step 2: Find the Meeting via Calendar View
# ==============================================================================
Write-Host "Searching calendar for meeting matching subject: '$targetSubject'..." -ForegroundColor Cyan

# Fetch calendar events and filter by Subject
$calendarEvents = Get-MgUserCalendarView -UserId $myUserId -StartDateTime $start -EndDateTime $end -All |
    Where-Object { $_.Subject -match $targetSubject -and $_.IsOnlineMeeting -eq $true }

# If multiple occurrences are found, grab the most recent one
if ($calendarEvents.Count -gt 1) {
    Write-Host "Multiple meetings found. Grabbing the first match..." -ForegroundColor Yellow
    $calendarEvent = $calendarEvents[0]
} else {
    $calendarEvent = $calendarEvents
}

if (-not $calendarEvent) {
    Write-Host "Meeting not found in calendar. Check the subject or date range." -ForegroundColor Red
    break
}

Write-Host "Calendar Event Found: $($calendarEvent.Subject)" -ForegroundColor Green

# ==============================================================================
# Step 3: Get the True Base64 Online Meeting ID via REST
# ==============================================================================
$rawUrl = $calendarEvent.OnlineMeeting.JoinUrl
$encodedUrl = [uri]::EscapeDataString($rawUrl)
$meetingUri = "https://graph.microsoft.com/beta/me/onlineMeetings?`$filter=JoinWebUrl eq '$encodedUrl'"

Write-Host "Resolving true Base64 Meeting ID..." -ForegroundColor Cyan

try {
    $meetingResponse = Invoke-MgGraphRequest -Method GET -Uri $meetingUri
    
    if ($meetingResponse.value.Count -eq 0) {
        Write-Host "Could not resolve the calendar URL to an Online Meeting object." -ForegroundColor Red
        break
    }

    $meetingId = $meetingResponse.value[0].id
    Write-Host "Base64 Meeting ID Resolved: $meetingId" -ForegroundColor Green

} catch {
    Write-Host "Failed to query the online meetings endpoint: $($_.Exception.Message)" -ForegroundColor Red
    break
}

# ==============================================================================
# Step 4: Extract and Download the Transcript
# ==============================================================================
$transcriptUri = "https://graph.microsoft.com/beta/me/onlineMeetings/$meetingId/transcripts"

Write-Host "Checking for available transcripts..." -ForegroundColor Cyan

try {
    $transcriptResponse = Invoke-MgGraphRequest -Method GET -Uri $transcriptUri
    
    if ($transcriptResponse.value.Count -gt 0) {
        
        # Loop through available transcripts (usually just 1, but sometimes more if restarted)
        foreach ($transcript in $transcriptResponse.value) {
            
            $transcriptId = $transcript.id
            $cleanSubject = $calendarEvent.Subject -replace '[\\/:*?"<>|]', '_'
            $outputPath   = Join-Path $outputFolder "$cleanSubject-$transcriptId.vtt"
            
            $contentUri = "https://graph.microsoft.com/beta/me/onlineMeetings/$meetingId/transcripts/$transcriptId/content?`$format=text/vtt"
            
            Write-Host "Downloading transcript [$transcriptId]..." -ForegroundColor Cyan
            
            # Download the file
            Invoke-MgGraphRequest -Method GET -Uri $contentUri -Outputfilepath $outputPath
            
            Write-Host "Success! Saved to: $outputPath" -ForegroundColor Green
        }
        
    } else {
        Write-Host "No transcripts found for this meeting. Transcription may not have been started." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to fetch or download transcripts: $($_.Exception.Message)" -ForegroundColor Red
}