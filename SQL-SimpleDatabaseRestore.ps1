<#============================================================================
  
  Written by Christophe LAPORTE, SQL Server MVP / MCM
	Blog    : http://conseilit.wordpress.com
	Twitter : @ConseilIT
  
  You may alter this code for your own *non-commercial* purposes. You may
  republish altered code as long as you give due credit.
  
  THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
  ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED 
  TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
  PARTICULAR PURPOSE.

============================================================================#>

# Assuming same disk infrastructure, no Move option

Clear-Host
$Instance = "SQL2017"
$Database = "MyDB"
$BackupFolder = "\\BackupShare\SQL\$Instance\$Database"
$IsOlaStructure = $true


If ($IsOlaStructure) {
    $BackupFile = get-childitem "$BackupFolder\FULL\*" -recurse | Where-Object {$_.Extension -eq ".bak" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
else {
    $BackupFile = get-childitem "$BackupFolder\*" -recurse | Where-Object {$_.Extension -eq ".bak" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$LastFullBackupFile = $BackupFile.FullName
$LastFullBackupDate = $BackupFile.LastWriteTime

#$LastFullBackupFile
#$LastFullBackupDate


# restore this file
write-host "-- Restore the last Full Backup : " $LastFullBackupDate
Restore-SqlDatabase -Database $Database -BackupFile $LastFullBackupFile -ServerInstance "$Instance" -NoRecovery -Script

# list the last diff file
If ($IsOlaStructure) {
    $BackupFile =  get-childitem "$BackupFolder\DIFF\*" -recurse | Where-Object LastWriteTime -ge $LastFullBackupDate | Where-Object {$_.Extension -eq ".bak" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
else {
    $BackupFile =  get-childitem "$BackupFolder\*" -recurse | Where-Object LastWriteTime -ge $LastFullBackupDate | Where-Object {$_.Extension -eq ".diff" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if ($BackupFile) {
    $LastFullBackupFile = $BackupFile.FullName
    $LastFullBackupDate = $BackupFile.LastWriteTime
    write-host "-- Restore the last Differential Backup : " $LastFullBackupDate
    Restore-SqlDatabase -Database $Database -BackupFile $LastFullBackupFile -ServerInstance "$Instance" -NoRecovery -Script
}

# list all trn files newer than the full backup
write-host "-- Restore all transaction log"
If ($IsOlaStructure) {
$BackupFiles =  get-childitem "$BackupFolder\LOG\*" -recurse | Where-Object LastWriteTime -ge $LastFullBackupDate | Where-Object {$_.Extension -eq ".trn" } | Sort-Object LastWriteTime
}
else {
    $BackupFiles =  get-childitem "$BackupFolder\*" -recurse | Where-Object LastWriteTime -ge $LastFullBackupDate | Where-Object {$_.Extension -eq ".trn" } | Sort-Object LastWriteTime
}
#$BackupFiles =  get-childitem $BackupFolder  | Where-Object {$_.Extension -eq ".trn" } | Sort-Object FullName
ForEach ($BackupFile in $BackupFiles) {

    $LogBackupFile = $BackupFile.FullName
    $LogBackupDate = $BackupFile.LastWriteTime

    #$LogBackupFile
    #$LogBackupDate
    write-host "-- Restore the transaction log : " $LogBackupDate
    Restore-SqlDatabase -Database $Database -BackupFile $LogBackupFile -ServerInstance "$Instance" -NoRecovery -RestoreAction 'Log' -Script

}

write-host "-- Recovery de la base "
write-host "-- RESTORE LOG [$Database] WITH RECOVERY;"
