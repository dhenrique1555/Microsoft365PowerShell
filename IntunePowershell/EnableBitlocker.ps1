start-transcript
$debugpreference = "continue"

#Disable Bitlocker first if needed
Disable-Bitlocker -MountPoint C: 



##Enable Bitlocker For Devices with TPM
#Test What Would Happen if Bitlocker was enabled
$BVol = Get-BitLockerVolume -MountPoint "C"
$Bvol.KeyProtector
Enable-Bitlocker -mountpoint "C:" -encryptionmethod XtsAes256 -recoverypasswordprotector  -whatif


#Actually Enable bitlocker if no problem was detected before
Enable-Bitlocker -mountpoint "C:" -encryptionmethod XtsAes256 -recoverypasswordprotector

#Backup Recovery Keys to AZure AD
$BLV = Get-BitLockerVolume -MountPoint "C:"
BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $BLV.KeyProtector[0].KeyProtectorId
BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $BLV.KeyProtector[1].KeyProtectorId
BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $BLV.KeyProtector[2].KeyProtectorId

Stop-transcript
