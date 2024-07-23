#Connect to PnP Online
$SiteURL= "https://kscsglobal.sharepoint.com/sites/TS-CS"
Connect-PnPOnline -Url $url -Interactive
#Set Variables for Source Folder and Destination Folder (Destination must be created before)
$SourceURL = "/sites/TestVersioning/Shared%20Documents/ToCopy"
$TargetURL = "/sites/TestVersioningNoRetention/Shared%20Documents/TargetFolder"
#Create and Follow Job Status
$job = copy-pnpfile -sourceurl $SourceURL -targeturl $TargetURL
$jobStatus = Receive-PnPCopyMoveJobStatus -Job $job

if($jobStatus.JobState -eq 0)
{
  Write-Host "Job finished"
}
