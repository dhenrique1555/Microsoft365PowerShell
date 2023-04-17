$usertobeadded = read-host "Enter user to be added"
$roommailbox = read-host "Enter Room Mailbox"
$oldusers = (Get-CalendarProcessing -Identity $roommailbox).BookInPolicy
$newusers = $oldusers + $usertobeadded
Set-calendarprocessing -identity $roommailbox -bookinpolicy $newusers
(Get-CalendarProcessing -Identity $roommailbox).BookInPolicy
