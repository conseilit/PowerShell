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

$DatabasesToRestore = "c:\temp\RestoreDatabase.csv"
<#
# use the following script to create one
$DBList = @"
"source";"destination";"database"
"SourceInstance1";"DestinationInstance1"; "Database1"
"SourceInstance2";"DestinationInstance2"; "Database2"
"SourceInstance3";"DestinationInstance3"; "Database3"
"SourceInstance4";"DestinationInstance4"; "Database4"
"SourceInstance5";"DestinationInstance5"; "Database5"
"SourceInstance6";"DestinationInstance6"; "Database6"
"@
$DBList >>$DatabasesToRestore
#>

[bool]$global:Verbose = $true
[string]$global:BackupFolderRoot = "\\BackupShare\SQL"
[bool]$global:IsOlaStructure = $true
[bool]$global:ShowTSQL = $true
[bool]$global:PerformRestore = $False
[string]$global:RestoreDBprefix = "" # specify a prefix here

function GetFormattedDate(){
	return (Get-Date).toString("yyyy-MM-dd HH:mm:ss")
}


#region Log
$global:OutputDirectory = ".\SQL-RestoreDatabaseOutput\"
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



function RestoreDatabase ( [string] $Source, [string] $destination, [string] $Database )  {
    
    $BackupFolder = Join-Path -Path $global:BackupFolderRoot -ChildPath $Source
    $BackupFolder = Join-Path -Path $BackupFolder -ChildPath $Database
    Write-Log "Restoring $Database on $destination from $BackupFolder"

    $Server = New-Object -TypeName  Microsoft.SQLServer.Management.Smo.Server($destination)

        
    #region Database backup
    If ($global:IsOlaStructure) {
        $LastFullBackup = get-childitem "$BackupFolder\FULL\*" -recurse -ErrorAction:silentlycontinue | Where-Object {$_.Extension -eq ".bak" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    else {
        $LastFullBackup = get-childitem "$BackupFolder\*" -recurse -ErrorAction:silentlycontinue | Where-Object {$_.Extension -eq ".bak" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    $LastFullBackupFile = $LastFullBackup.FullName
    $LastFullBackupDate = $LastFullBackup.LastWriteTime
    
    if ($global:Verbose) {
        Write-Log "Last Full Backup File : $LastFullBackupFile"
        Write-Log "Last Full Backup Date : $LastFullBackupDate"
    }

    # if wanna a DB prefix to restore as a "new" database, update the global variable
    $Database= $global:RestoreDBprefix + $Database

    # Create restore object and specify the settings
    $smoRestore = new-object("Microsoft.SqlServer.Management.Smo.Restore")
    $smoRestore.Database = $Database
    $smoRestore.NoRecovery = $true;
    $smoRestore.ReplaceDatabase = $true;
    $smoRestore.Action = "Database"
           
          
    # Create location to restore from
    $backupDevice = New-Object("Microsoft.SqlServer.Management.Smo.BackupDeviceItem") ($LastFullBackupFile, "File")
    if ($smoRestore.Devices.Count -ge 1) {
        $smoRestore.Devices.Clear();
    }
    $smoRestore.Devices.Add($backupDevice)

    # retreiving the database data and log files 
    # the physical disk layer may be different, have to use the MOVE TO option
    Write-Log "Retriving database files from backup file  $LastFullBackupFile"  
    $tSQL = "RESTORE FILELISTONLY FROM DISK = '$LastFullBackupFile'"
    if ($global:ShowTSQL) {Write-Log "T-SQL : $tSQL"}
    $FileList  = Invoke-SqlCmd -Query $tSQL -Serverinstance $destination


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
            
    Write-Log ""

    # Restoring the database now
    Write-Log "Begin Restore $DatabaseName on $destination from $LastFullBackupFile" 

    $tSQL =  $smoRestore.Script($server.DomainInstanceName) 
    if ($global:ShowTSQL) {Write-Log "T-SQL : $tSQL"}

    try {
        If ([bool]$global:PerformRestore){
            $ActiveConnections = $server.GetActiveDBConnectionCount("$DatabaseName")
            if ($ActiveConnections -gt 0) {
                Write-Log "$ActiveConnections active connections on $DatabaseName" 
                Write-Log "Killing all of them before starting restore ..."
                $server.KillAllProcesses("$DatabaseName")
            }
                
            Invoke-Sqlcmd -Query  $tSQL.Item(0) -ServerInstance $server.DomainInstanceName  -QueryTimeout 0
        }
    }
    catch {
       Write-Log -ForegroundColor Red $_.Exception.Message
    }
    finally {
        Write-Log "  Done !!"
    }
    Write-Log ""
    #endregion

    #region differential backup
    # find the last differential backup file
	If ($global:IsOlaStructure) {
		$BackupFile =  get-childitem "$BackupFolder\DIFF\*" -recurse -ErrorAction:silentlycontinue  | Where-Object LastWriteTime -ge $LastFullBackupDate | Where-Object {$_.Extension -eq ".bak" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
	}
	else {
		$BackupFile =  get-childitem "$BackupFolder\*" -recurse -ErrorAction:silentlycontinue  | Where-Object LastWriteTime -ge $LastFullBackupDate | Where-Object {$_.Extension -eq ".diff" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
	}
    
	if ($BackupFile) {
		$LastFullBackupFile = $BackupFile.FullName
		$LastFullBackupDate = $BackupFile.LastWriteTime
        if ($global:Verbose) {
            Write-Log "Last Differential Backup File : $LastFullBackupFile"
            Write-Log "Last Differential Backup Date : $LastFullBackupDate"
        }

        $tSQL = Restore-SqlDatabase -Database $Database -BackupFile $LastFullBackupFile -ServerInstance "$Instance" -NoRecovery -Script
        if ($global:ShowTSQL) {Write-Log "T-SQL : $tSQL"}

        try {
            If ([bool]$global:PerformRestore){
                Invoke-Sqlcmd -Query  $tSQL.Item(0) -ServerInstance $server.DomainInstanceName  -QueryTimeout 0
            }
        }
        catch {
           Write-Log -ForegroundColor Red $_.Exception.Message
        }
        finally {
            Write-Log "  Done !!"
        }
        Write-Log ""
    }
    else {
        Write-Log "No differential backup found"

    }
    #endregion 
    
    #region transaction log
	# list all trn files newer than the full / differential backup
	write-Log "Restore all transaction log"
	If ($global:IsOlaStructure) {
	    $BackupFiles =  get-childitem "$BackupFolder\LOG\*" -recurse -ErrorAction:silentlycontinue | Where-Object LastWriteTime -ge $LastFullBackupDate | Where-Object {$_.Extension -eq ".trn" } | Sort-Object LastWriteTime
	}
	else {
		$BackupFiles =  get-childitem "$BackupFolder\*" -recurse -ErrorAction:silentlycontinue | Where-Object LastWriteTime -ge $LastFullBackupDate | Where-Object {$_.Extension -eq ".trn" } | Sort-Object LastWriteTime
    }
    
    if(!($BackupFiles)) {
        write-Log "No transaction log backup found"
    }
    else {
        ForEach ($BackupFile in $BackupFiles) {
        
            $LogBackupFile = $BackupFile.FullName
            $LogBackupDate = $BackupFile.LastWriteTime
        
            write-Log "Restoring $LogBackupFile ($LogBackupDate) " 
            $tSQL = Restore-SqlDatabase -Database $Database -BackupFile $LogBackupFile -ServerInstance "$Instance" -NoRecovery -RestoreAction 'Log' -Script
            if ($global:ShowTSQL) {Write-Log "T-SQL : $tSQL"}

            try {
                If ([bool]$global:PerformRestore){
                    Invoke-Sqlcmd -Query  $tSQL.Item(0) -ServerInstance $server.DomainInstanceName  -QueryTimeout 0
                }
            }
            catch {
               Write-Log -ForegroundColor Red $_.Exception.Message
            }
            finally {
                Write-Log "  Done !"
            }
        }
        Write-Log ""
    }
    #endregion
    
}




# main program
$timestamp = (Get-Date -format "yyyyMMddHHmmss")
New-Log 

Write-Log "Getting databases to restore from $DatabasesToRestore"
$RestoreOperations = Import-Csv $DatabasesToRestore  -Delimiter ";"

foreach ($RestoreOperation in $RestoreOperations) {

    RestoreDatabase -Source $RestoreOperation.Source -destination $RestoreOperation.Destination -Database $RestoreOperation.Database
    # add some functionality : CheckDB, change DB Compat Level, Drop auto created stats, alter index, ...
}

$LogMessage = "Ending module at $(get-date -format "dd/MM/yyyy HH:mm:ss")"
write-log $LogMessage

