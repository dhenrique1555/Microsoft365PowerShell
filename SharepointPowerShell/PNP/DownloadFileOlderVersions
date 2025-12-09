#Set Parameters
$SiteURL = ""
$FileRelativeURL = "/sites/DaniloTestTeam/Shared Documents/Root Folder/Document.docx"
$DownloadPath = "C:\Temp"
 
#Connect to PnP Online
Connect-PnPOnline -Url $SiteURL -Interactive
$Ctx = Get-PnPContext
 
#Get the File
$File = Get-PnPFile -Url $FileRelativeURL
 
#Get File Versions
$FileVersions = Get-PnPProperty -ClientObject $File -Property Versions
 
If($FileVersions.Count -gt 0)
{
    Foreach($Version in $FileVersions)
    {
        #Frame File Name for the Version
        $VersionFileName = "$($DownloadPath)\$($Version.VersionLabel)_$($File.Name)"
          
        #Get Contents of the File Version
        $VersionStream = $Version.OpenBinaryStream()
        $Ctx.ExecuteQuery()
  
        #Download File version to local disk
        [System.IO.FileStream] $FileStream = [System.IO.File]::Open($VersionFileName,[System.IO.FileMode]::OpenOrCreate)
        $VersionStream.Value.CopyTo($FileStream)
        $FileStream.Close()
          
        Write-Host -f Green "Version $($Version.VersionLabel) Downloaded to :" $VersionFileName
    }
}
Else
{
    Write-host -f Yellow "No Versions Found!"
}
