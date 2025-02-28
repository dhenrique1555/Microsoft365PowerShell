$result  = @()
$autoattendants = @()
$autoattendants = import-csv c:\temp\AA.csv 
foreach($autoattendant in $autoattendants){

$autoattendantInfo = Get-CsAutoAttendant -identity $autoattendant.id 

$Result += New-Object PSObject -property $([ordered]@{ 
ID = $autoattendantInfo.ID
DisplayName = $autoattendantInfo.Name
GreetingType = $autoattendantInfo.DefaultCallFlow.Greetings.ActiveType
GreetingTextToSpeech = $autoattendantInfo.DefaultCallFlow.Greetings.TextToSpeechPrompt
GreetingAudioFilePrompt = $autoattendantInfo.DefaultCallFlow.Greetings.AudioFilePrompt
MenuPromptsType = $autoattendantInfo.DefaultCallFlow.Menu.Prompts.ActiveType
MenuPromptsTextToSpeech = $autoattendantInfo.defaultcallflow.menu.prompts.texttospeechprompt
MenuPromptsAudioFilePrompt = $autoattendantInfo.defaultcallflow.menu.prompts.AudioFilePrompt
AfterHoursGreetingType = $autoattendantInfo.callflows.Greetings.ActiveType -join ","
AfterHoursGreetingTextToSpeechPrompt = $autoattendantInfo.callflows.Greetings.TextToSpeechPrompt -join ","
AfterHoursGreetingAudioFilePrompt = $autoattendantInfo.callflows.Greetings.AudioFilePrompt -join ","
}
)

}
