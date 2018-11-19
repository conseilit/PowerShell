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

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null

Clear-Host

[bool]$global:Verbose = $true
[string]$global:BackupFolderRoot = "\\BackupShare\SQL"
#[string]$global:BackupFolderRoot = "C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\X1CARBON`$SQL2017\AdventureWorks"
[bool]$global:ShowTSQL = $false
[bool]$global:PerformRestore = $true
[string]$global:RestoreDBprefix = "" # specify a prefix here

$Instance="X1carbon\sql2017"
$DatabaseList = "AdventureWorks","AdventureWorks2008"



#region Log
$global:OutputDirectory = ".\SQL-RestoreDatabaseFromFilesOutput\"
$WriteHost = $true
function New-Log {

    $Logoutputfile   = $global:OutputDirectory + $timestamp +"_Summary.log" ; 

    if ((Test-Path -Path $global:OutputDirectory) -eq $false ) {
        Write-Host "Create directory $global:OutputDirectory" ;
        $dir = New-Item -type directory $global:OutputDirectory -Force ;
    } 
    else {
        if ($PurgeLogFiles -eq $true) {
           Get-ChildItem -Path $global:OutputDirectory | Remove-Item 
        }
        
    }


    $LogMessage = (Get-Date -format "yyyy-MM-dd HH:mm:ss : ") + $(split-path $MyInvocation.PSCommandPath -Leaf) + " starting at $(get-date -format "dd/MM/yyyy HH:mm:ss")"
    if ($WriteHost -eq $true) {
        Write-Host $LogMessage 
    }

    $LogMessage = $LogMessage + "`r`n"
    $global:logfile = $Logoutputfile
    $file = New-Item $global:logfile -type File -value $LogMessage  -force 

    write-log ""
}


function Write-Log ( [string] $LogMessage ) {

    $LogMessage = (Get-Date -format "yyyy-MM-dd HH:mm:ss : ") + $LogMessage
    Add-Content -path $global:logfile -value $LogMessage
    if ($WriteHost -eq $true) {
        Write-Host $LogMessage 
    }
     
}
#endregion



function RestoreFullBackupWithMove ( [string] $Database, [string] $BackupFile )  {
    

    if ($global:Verbose) {Write-Log "Restoring $Database from $BackupFile "}

    $Server = New-Object -TypeName  Microsoft.SQLServer.Management.Smo.Server($instance)

        
    #region Database backup
    # if wanna a DB prefix to restore as a "new" database, update the global variable
    $Database= $global:RestoreDBprefix + $Database

    # Create restore object and specify the settings
    $smoRestore = new-object("Microsoft.SqlServer.Management.Smo.Restore")
    $smoRestore.Database = $Database
    $smoRestore.NoRecovery = $true;
    $smoRestore.ReplaceDatabase = $true;
    $smoRestore.Action = "Database"
           
          
    # Create location to restore from
    $backupDevice = New-Object("Microsoft.SqlServer.Management.Smo.BackupDeviceItem") ($BackupFile, "File")
    if ($smoRestore.Devices.Count -ge 1) {
        $smoRestore.Devices.Clear();
    }
    $smoRestore.Devices.Add($backupDevice)

    # retreiving the database data and log files 
    # the physical disk layer may be different, have to use the MOVE TO option
    if ($global:Verbose) {Write-Log "Retriving database files from backup file  $BackupFile"}  
    $tSQL = "RESTORE FILELISTONLY FROM DISK = '$BackupFile'"
    if ($global:ShowTSQL) {Write-Log "T-SQL : $tSQL"}
    $FileList  = Invoke-SqlCmd -Query $tSQL -Serverinstance $instance


    # Move each file to the destination data / log folder
    $DataFileCount = 1
    foreach ($file in $FileList) {
        $rsfile = new-object('Microsoft.SqlServer.Management.Smo.RelocateFile')    
        $rsfile.LogicalFileName = $file.LogicalName    
        if ($file.Type -eq 'D') {      
            $rsfile.PhysicalFileName = $Server.DefaultFile + $Database + "_Data" + $DataFileCount + ".mdf"
            $DataFileCount += 1
        }    
        else {        
            $rsfile.PhysicalFileName = $Server.DefaultLog + $Database + "_Log.ldf"
        }
        if ($global:Verbose){
           Write-Log "Moving $($file.LogicalName) : $($file.PhysicalName) ==> $($rsfile.PhysicalFileName)"
        }     
        $smoRestore.RelocateFiles.Add($rsfile)  | Out-Null 
    }
            
    if ($global:Verbose) {Write-Log ""}

    # Restoring the database now
    $tSQL =  $smoRestore.Script($server.DomainInstanceName) 
    if ($global:ShowTSQL) {Write-Log "T-SQL : $tSQL"}

    try {
        If ($global:PerformRestore){
            $ActiveConnections = $server.GetActiveDBConnectionCount("$Database")
            if ($ActiveConnections -gt 0) {
                Write-Log "$ActiveConnections active connections on $Database" 
                Write-Log "Killing all of them before starting restore ..."
                $server.KillAllProcesses("$Database")
            }
                
            Invoke-Sqlcmd -Query  $tSQL.Item(0) -ServerInstance $instance  -QueryTimeout 0
        }
    }
    catch {
       Write-Log -ForegroundColor Red $_.Exception.Message
    }
    finally {
        Write-Log "$(split-path $BackupFile -leaf) successfully restored !"
    }
    Write-Log ""
    #endregion

    
}

function RestoreDatabase ([string] $Database) {

    $BackupFileList = @()

    $BackupFolder = Join-Path -path $global:BackupFolderRoot -childpath $Database

    Write-Log "Restore database $Database"
    Write-log "Getting all backup files from  $BackupFolder"    
    
    $FileList = get-childitem "$BackupFolder\*" -recurse -ErrorAction:silentlycontinue 

    Foreach($BackupFile in $FileList) {
        
        if ($global:Verbose) {Write-log "Reading header from backup file  $($BackupFile.FullName)" }
           
        $tSQL = "RESTORE HEADERONLY FROM DISK = '$($BackupFile.FullName)'"
        if ($global:ShowTSQL) {write-log $tSQL}
        $headerInfo  = Invoke-SqlCmd -Query $tSQL -Serverinstance $Instance -QueryTimeout 0
    
        if ($headerInfo.DatabaseName -eq $Database) {

            $BackupFileList += New-Object PSObject -Property @{DatabaseName=$headerInfo.DatabaseName;`
                                                              BackupFile=$BackupFile.FullName;`
                                                              BackupFileName=$BackupFile.Name;`
                                                              BackupTypeDescription=$headerInfo.BackupTypeDescription;`
                                                              BackupStartDate=$headerInfo.BackupStartDate;`
                                                              BackupFinishDate=$headerInfo.BackupFinishDate;`
                                                              FirstLSN=$headerInfo.FirstLSN;`
                                                              LastLSN=$headerInfo.LastLSN;`
                                                            }
        }
    }

    write-log ""

    if ($global:Verbose) {
        write-log "Raw data"
        $BackupFileList | Select-object BackupFileName,BackupTypeDescription, FirstLsn, LastLSN, BackupStartDate, BackupFinishDate| format-table -AutoSize
        write-log "Sorted file list"
        $BackupFileList | Select-object BackupFileName,BackupTypeDescription, FirstLsn, LastLSN, BackupStartDate, BackupFinishDate| Sort-Object LastLsn | format-table -AutoSize
    }

    write-log "Newest Full backup found :"
    if ($global:Verbose) {
        $BackupFileList | Where-Object BackupTypeDescription -eq "Database" | Sort-Object LastLsn -Descending | Select-Object -First 1 `
                        | Select-object BackupFileName,BackupTypeDescription, FirstLsn, LastLSN, BackupStartDate, BackupFinishDate | format-table -AutoSize
    }
    $LastFullBackup = $BackupFileList | Where-Object BackupTypeDescription -eq "Database" | Sort-Object LastLsn -Descending | Select-Object -First 1
    
    RestoreFullBackupWithMove -Database $Database -BackupFile $LastFullBackup.BackupFile
    
    if ($global:Verbose) {Write-log "Backup Database LastLSN $($LastFullBackup.LastLsn)"}

    
    #region differential backup
    # find the last differential backup file
    write-log "Newest differential backup found :"
    if ($global:Verbose) {
        $BackupFileList | Where-Object BackupTypeDescription -eq "Database Differential" | Where-Object FirstLsn -GT $($LastFullBackup.LastLsn) `
                        | Sort-Object LastLsn -Descending | Select-Object -First 1 `
                        | Select-object BackupFileName,BackupTypeDescription, FirstLsn, LastLSN, BackupStartDate, BackupFinishDate | format-table -AutoSize
    }
    $LastDiffBackup = $BackupFileList | Where-Object BackupTypeDescription -eq "Database Differential" | Where-Object FirstLsn -GT $($LastFullBackup.LastLsn) `
                                      | Sort-Object LastLsn -Descending | Select-Object -First 1
   
    if ($global:Verbose) {Write-log "Backup Differential $($LastDiffBackup.BackupFile)"}

	if ($LastDiffBackup) {

        $tSQL = Restore-SqlDatabase -Database $Database -BackupFile $LastDiffBackup.BackupFile -ServerInstance $Instance -NoRecovery -Script
        if ($global:ShowTSQL) {Write-Log "T-SQL : $tSQL"}

        try {
            If ($global:PerformRestore){
                Invoke-Sqlcmd -Query  $tSQL -ServerInstance $Instance  -QueryTimeout 0
            }
        }
        catch {
           Write-Log -ForegroundColor Red $_.Exception.Message
        }
        finally {
            Write-Log "$($LastDiffBackup.BackupFilename) successfully restored !"
            $LastDiffBackupLastLsn = $($LastDiffBackup.LastLsn)
            if ($global:Verbose) {Write-log "Backup Database LastLSN $($LastDiffBackup.LastLsn)"}
        }
        Write-Log ""
    }
    else {
        Write-Log "No differential backup found"
        $LastDiffBackupLastLsn = $($LastFullBackup.LastLsn)
    }
    #endregion 


    
    #region transaction log
	# list all trn files newer than the full / differential backup
    write-log "Subsequents transaction log backups :"
    if ($global:Verbose) {
        $BackupFileList | Where-Object BackupTypeDescription -eq "Transaction Log" | Where-Object LastLsn -GE $LastDiffBackupLastLsn | Sort-Object LastLsn  `
                        | Select-object BackupFileName,BackupTypeDescription, FirstLsn, LastLSN, BackupStartDate, BackupFinishDate | ft -AutoSize
    }

    $LastTLogBackup = $BackupFileList | Where-Object BackupTypeDescription -eq "Transaction Log" | Where-Object LastLsn -GE $LastDiffBackupLastLsn `
                                      | Sort-Object LastLsn  
                    

    if(!($LastTLogBackup)) {
        write-Log "No transaction log backup found"
    }
    else {
        ForEach ($TLogBackup in $LastTLogBackup) {
        
            if ($global:Verbose) {write-Log "Restoring $($TLogBackup.BackupFile)"}
            $tSQL = Restore-SqlDatabase -Database $Database -BackupFile $TLogBackup.BackupFile -ServerInstance $Instance -NoRecovery -RestoreAction 'Log' -Script
            if ($global:ShowTSQL) {Write-Log "T-SQL : $tSQL"}

            try {
                If ($global:PerformRestore){
                    Invoke-Sqlcmd -Query  $tSQL -ServerInstance $Instance  -QueryTimeout 0
                }
            }
            catch {
               Write-Log -ForegroundColor Red $_.Exception.Message
            }
            finally {
                Write-Log "$($TLogBackup.BackupFilename) successfully restored !"
            }
        }
        Write-Log ""
    }
    #endregion


    #region recovery
    $tSQL = "RESTORE LOG [$Database] WITH RECOVERY"
    try {
        If ($global:PerformRestore){
            Invoke-Sqlcmd -Query  $tSQL -ServerInstance $Instance  -QueryTimeout 0
        }
    }
    catch {
        Write-Log -ForegroundColor Red $_.Exception.Message
    }
    finally {
        Write-Log "Recovery complete !!"
    }
    Write-Log ""
    #endregion

}


# main program
$timestamp = (Get-Date -format "yyyyMMddHHmmss")
New-Log 


foreach ($DatabaseToRestore in $DatabaseList) {
    #RestoreDatabase -Database "AdventureWorks"
    RestoreDatabase -Database $DatabaseToRestore
} 

$LogMessage = "Ending module at $(get-date -format "dd/MM/yyyy HH:mm:ss")"
write-log $LogMessage

