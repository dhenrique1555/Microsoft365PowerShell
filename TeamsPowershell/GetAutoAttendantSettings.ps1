$autoattendants = Get-CsAutoAttendant
$result = @()
foreach($autoattendant in $autoattendants){
$schedule = $autoattendant.schedules.weeklyrecurrentschedule | Out-string
$Result += New-Object PSObject -property $([ordered]@{ 
ID = $autoattendant.Id
Name = $autoattendant.Name
Language = $autoattendant.languageid
Timezone = $autoattendant.Timezoneid
VoiceResponseEnabled = $autoattendant.VoiceResponseEnabled
DefaultCallFlowName = $autoattendant.defaultcallflow.Name
DefaultCallFlowGreetingsType = $autoattendant.defaultcallflow.greetings.ActiveType
DefaultCallFlowGreetingsText = $autoattendant.defaultcallflow.greetings.texttospeechprompt
DefaultCallFlowGreetingsAudioFile = $autoattendant.defaultcallflow.greetings.AudioFilePrompt.filename
DefaultCallFlowMenu = $autoattendant.defaultcallflow.menu
DefaultCallFlowMenuPromptsType = $autoattendant.defaultcallflow.menu.Prompts.ActiveType
DefaultCallFlowMenuPromptsTextToSpeech = $autoattendant.defaultcallflow.menu.Prompts.TexttoSpeechPrompt
DefaultCallFlowMenuPromptsAudioFile = $autoattendant.defaultcallflow.menu.Prompts.AudioFilePrompt
DefaultCallFlowMenuOptionsAction = $autoattendant.defaultcallflow.menu.menuoptions.Action -join ","
DefaultCallFlowMenuOptionsDTMFResponse = $autoattendant.defaultcallflow.menu.menuoptions.DTmfRESPONSE -join ","
DefaultCallFlowMenuOptionsVoiceResponses = $autoattendant.defaultcallflow.menu.menuoptions.calltarget.VoiceResponses
DefaultCallFlowMenuOptionsCallTargetID = $autoattendant.defaultcallflow.menu.menuoptions.calltarget.ID -join "," 
DefaultCallFlowMenuOptionsCallTargetType = $autoattendant.defaultcallflow.menu.menuoptions.calltarget.type -join ","
DefaultCallFlowMenuOptionsCallEnableTranscription = $autoattendant.defaultcallflow.menu.menuoptions.calltarget.EnableTranscription -join ","
DefaultCallFlowMenuOptionsCallCallPriority = $autoattendant.defaultcallflow.menu.menuoptions.calltarget.CallPriority -join ","
DefaultCallFlowDialByNameEnabled = $autoattendant.defaultcallflow.menu.DialByNameEnabled
DefaultCallFlowDirectorySearchMethod = $autoattendant.defaultcallflow.menu.DirectorySearchMethod
DefaultCallFlowForceListenMenuEnabled = $autoattendant.defaultcallflow.ForceListenMenuEnabled
callflowsName = $autoattendant.callflows.Name -join ","
callflowsGreetingsType = $autoattendant.callflows.greetings.ActiveType -join ","
callflowsGreetingsText = $autoattendant.callflows.greetings.texttospeechprompt -join ","
callflowsGreetingsAudioFile = $autoattendant.callflows.greetings.AudioFilePrompt.filename -join ","
callflowsMenu = $autoattendant.callflows.menu -join ","
callflowsMenuPrompts = $autoattendant.callflows.menu.Prompts -join ","
callflowsMenuOptionsAction = $autoattendant.callflows.menu.menuoptions.Action -join ","
callflowsMenuOptionsDTMFResponse = $autoattendant.callflows.menu.menuoptions.DTmfRESPONSE -join ","
callflowsMenuOptionsVoiceResponses = $autoattendant.callflows.menu.menuoptions.calltarget.VoiceResponses -join ","
callflowsMenuOptionsCallTargetID = $autoattendant.callflows.menu.menuoptions.calltarget.ID -join ","
callflowsMenuOptionsCallTargetType = $autoattendant.callflows.menu.menuoptions.calltarget.type -join ","
callflowsMenuOptionsCallEnableTranscription = $autoattendant.callflows.menu.menuoptions.calltarget.EnableTranscription -join ","
callflowsMenuOptionsCallCallPriority = $autoattendant.callflows.menu.menuoptions.calltarget.CallPriority -join ","
CallFLowsDialByNameEnabled = $autoattendant.callflows.menu.DialByNameEnabled -join ","
callflowsDirectorySearchMethod = $autoattendant.callflows.menu.DirectorySearchMethod -join ","
callflowsForceListenMenuEnabled = $autoattendant.callflows.ForceListenMenuEnabled-join ","
ApplicationInstances = $autoattendant.ApplicationInstances -join ","
Schedule = $schedule
})
}

$result | export-csv c:\temp\TestTeamsAA.csv -NoTypeInformation -Encoding utf8
