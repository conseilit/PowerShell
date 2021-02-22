
# SQL Server restore scripts based on dbaTools commands
# Thanks to Chrissy LeMaire (@cl | https://blog.netnerds.net/ )
#          , Row Sewell (@SQLDBAWithBeard | https://sqldbawithabeard.com/)
#          , and all SQL Server community members
# http://dbatools.io


# List of backup files
$backupPath = "\\Rebond\backup\MultipleDatabases"
Get-ChildItem -Path $backupPath 

# Restore multiple databases at once - the quickest way
Restore-DbaDatabase -SqlInstance SQL15AG1 `
                    -Path $backupPath `
                    -UseDestinationDefaultDirectories
 
# list databases
get-dbaDatabase -SqlInstance SQL15AG1 -ExcludeSystem | format-table -autosize
 



# Restore single databases on different location on multiple instances
$backupPath = "\\Rebond\backup\AdventureWorks"
Get-ChildItem -Path $backupPath 

$tSQL = Get-ChildItem -Path $backupPath `
            | Select-Object -First 1 `
            | Restore-DbaDatabase -SqlInstance SQL15AG1 `
                                  -DestinationDataDirectory G:\MSSQL15.MSSQLSERVER\MSSQL\DATA `
                                  -DestinationLogDirectory H:\MSSQL15.MSSQLSERVER\Log `
                                  -WithReplace `
                                  -NoRecovery `
                                  -OutputScriptOnly
Write-Host $tSQL
 
Invoke-DbaQuery -SqlInstance SQL15AG1,SQL15AG2 `
                -Query $tSQL


# list databases
get-dbaDatabase -SqlInstance SQL15AG1,SQL15AG2 -ExcludeSystem | format-table -autosize




# Restore a copy of a database at a specific point in time
$BackupPath = "\\Rebond\backup\AdventureworksLT"
Get-ChildItem -Path $backupPath -Recurse -Directory # looks like OH folder structure :-)
Get-ChildItem -Path $backupPath -Recurse

$RestoreTime = Get-Date('16:20 20/02/2021')
$RestoredDatabaseNamePrefix = $RestoreTime.ToString("yyyyMMdd_HHmmss_") 


$Result = Restore-DbaDatabase -SqlInstance SQL15AG1 `
                    -Path $BackupPath `
                    -UseDestinationDefaultDirectories `
                    -MaintenanceSolutionBackup `
                    -RestoredDatabaseNamePrefix $RestoredDatabaseNamePrefix `
                    -DestinationFilePrefix $RestoredDatabaseNamePrefix `
                    -RestoreTime $RestoreTime `
                    -WithReplace 
 
 
$Result | Select-Object Database, BackupFile, FileRestoreTime, DatabaseRestoreTime | Format-Table -AutoSize
 
Write-Host "Time taken to restore $($Result[$Result.count - 1].Database) database : $($Result[$Result.count - 1].DatabaseRestoreTime) ($($Result.count) files)"
 
# list databases
get-dbaDatabase -SqlInstance SQL15AG1 -ExcludeSystem | format-table -autosize


# cleanup
$Databases = get-dbaDatabase -SqlInstance SQL15AG1,SQL15AG2 -ExcludeSystem -ExcludeDatabase "_DBA"  
$Databases | Format-Table -AutoSize
$Databases | remove-dbaDatabase -Confirm:$false | Out-Null

 
