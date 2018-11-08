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
 
clear-host
 
#$DiscoveredInstanceList = sqlcmd -L
# or
$DiscoveredInstanceTable = [System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources()
$DiscoveredInstanceList = @()
ForEach ($InstanceName in $DiscoveredInstanceTable) {
    $s = $InstanceName.ServerName
    if (-not ([string]::IsNullOrEmpty($InstanceName.Instancename))) {
        $s += "\" + $InstanceName.Instancename
    }
    $DiscoveredInstanceList += $s
}
# or
# $DiscoveredInstanceList = "srv1","srv2"
 
try {
    $AdditionalInstancesListFile = Get-Content "C:\temp\AdditionalServers.txt"
    $DiscoveredInstanceList += $AdditionalInstancesListFile
}
catch {}
 
$ExcludedHostList = "devsql2017","(local)"
 
[int]$global:TotalDatabaseStorage = 0
[int]$global:TotalDatabaseCount = 0
 
$ListInstances = @()
$ListDatabases = @()
$InstanceErrorList = @()
$DisplayInstanceErrorList = $false
 
$Debug = $false
 
$CheckDatabaseDetails = $true
$CheckLastUserAccess = $true
$CheckSystemDatabases = $true
 
$OutGridView = $true
$ExportCSV = $true
$ExportCSVFile = "c:\temp\SQLInstancesInventory.csv"
 
ForEach ($InstanceName in $DiscoveredInstanceList) {
    $InstanceName = $InstanceName.trim()
    if ($InstanceName -eq "") {continue}
    if ($InstanceName -eq "Servers:") {continue}
 
    # Check excluded instances
    if ($ExcludedHostList -contains $InstanceName) {
        if ($Debug) {
            Write-Host $InstanceName " excluded" -ForegroundColor yellow
        }
        continue
    }
 
    $Server = New-Object -TypeName  Microsoft.SQLServer.Management.Smo.Server($InstanceName)
    $Server.ConnectionContext.ConnectTimeout = 1
 
    if (!($Server.ComputerNamePhysicalNetBIOS)) {
        $InstanceErrorList +=  "Error connecting $InstanceName"
        continue
    }
    else {
 
        $Databases = $server.Databases | Where-Object Status -eq "normal" | sort-object ID
 
        Write-Host $InstanceName "-"$Server.Edition "-" $Server.VersionString "(" $Server.ProductLevel ") -" $Server.collation `
 
        $InstanceStorage = 0
        $DatabaseCount = 0
        foreach ($Database in $Databases) {
             try {
                 If (($CheckSystemDatabases) -or ($Database.iD -gt 4)) {
                    $InstanceStorage += $Database.size
                    $DatabaseCount += 1
                    if ($CheckDatabaseDetails) {
                        if ($debug) {
                            Write-Host "  " $Database.Name "- Owner" $Database.Owner "- RecoveryModel" $Database.RecoveryModel "- Size" $Database.Size.ToString("N") "MB"
                        }
 
                        if ($CheckLastUserAccess) {
                            $tSQL = "SELECT database_id , 
                                           CASE WHEN max(last_user_seek) > max(last_user_scan) THEN max(last_user_seek)
                                                ELSE max(last_user_scan)
                                           END AS LastUserRead,
                                           max(last_user_update) as LastUserWrite
                                    FROM sys.dm_db_index_usage_stats
                                    WHERE database_id = " + $Database.ID + "
                                    GROUP BY database_id "
 
                            $LastUserRead = $Database.ExecuteWithResults($tSQL).Tables[0].LastUserRead
                            $LastUserWrite = $Database.ExecuteWithResults($tSQL).Tables[0].LastUserWrite
 
                            if (-not ([string]::IsNullOrEmpty($LastUserRead))) {$LastUserRead = $LastUserRead.ToString("yyyy-MM-dd HH:mm:ss")}
                            if (-not ([string]::IsNullOrEmpty($LastUserWrite))) {$LastUserWrite = $LastUserWrite.ToString("yyyy-MM-dd HH:mm:ss")}
 
                        }
                        else {
                            $LastUserRead = ""
                            $LastUserWrite = ""
                        }
 
                        $LastKnownGood = $($Database.ExecuteWithResults("DBCC DBINFO() WITH TABLERESULTS").Tables[0] | Where-Object {$_.Field -eq "dbi_dbccLastKnownGood"} | Select-Object -First 1).value
 
                        $ListDatabases += New-Object PSObject -Property @{InstanceName=$Server.name;`
                                                                          VersionMajor=$Server.VersionMajor;`
                                                                          DatabaseName=$Database.Name;`
                                                                          CompatibilityLevel=$Database.CompatibilityLevel.ToString().replace("Version","");`
                                                                          RecoveryModel=$Database.RecoveryModel;`
                                                                          Size=$Database.Size.ToString("N");`
                                                                          Owner=$Database.Owner;`
                                                                          Collation=$Database.collation;`
                                                                          AutoClose=$Database.AutoClose;`
                                                                          AutoShrink=$Database.AutoShrink;`
                                                                          IsReadCommittedSnapshotOn=$Database.IsReadCommittedSnapshotOn;`
                                                                          PageVerify=$Database.PageVerify;`
                                                                          ActiveConnections=$Database.ActiveConnections;`
                                                                          CreateDate=$database.CreateDate.ToString("yyyy-MM-dd HH:mm:ss");`
                                                                          LastFullBackupDate=$database.LastBackupDate.ToString("yyyy-MM-dd HH:mm:ss");`
                                                                          LastLogBackupDate=$database.LastLogBackupDate.ToString("yyyy-MM-dd HH:mm:ss");`
                                                                          LastKnownGood=$LastKnownGood;`
                                                                          LastUserRead=$LastUserRead;`
                                                                          LastUserWrite=$LastUserWrite;`
                                                                          }
                    }
                 }
            }
            catch {
                Write-host -ForegroundColor Red $_.Exception.Message
            }
        }
        $global:TotalDatabaseStorage += $InstanceStorage
        $global:TotalDatabaseCount += $DatabaseCount
 
        if ($Debug) {
 
            Write-Host $InstanceName ": " $DatabaseCount " Databases ("$InstanceStorage.ToString("N") "MB )" 
        }
 
        $TFList = $Server.EnumActiveGlobalTraceFlags() | Where-Object Global -EQ 1 | Select-Object TraceFlag
        if (-not ([string]::IsNullOrEmpty($TFList))) {
            $TraceFlags = [string]::Join(",",$TFList.TraceFlag)
        }
        else {$TraceFlags = ""} 
 
        $ListInstances += New-Object PSObject -Property @{NetName=$Server.NetName;`
                                                         InstanceName=$Server.name;`
                                                         Edition=$Server.Edition;`
                                                         VersionMajor=$Server.VersionMajor;`
                                                         Version=$Server.VersionString;`
                                                         ProductLevel=$Server.ProductLevel;`
                                                         Collation=$Server.collation;`
                                                         Processors=$server.Processors;`
                                                         PhysicalMemory=$Server.PhysicalMemory;`
                                                         MaxServerMemory=$Server.Configuration.MaxServerMemory.RunValue;`
                                                         DatabaseCount=$DatabaseCount;`
                                                         TotalSizeMB=$InstanceStorage.ToString("N");`
                                                         ServiceAccount=$Server.ServiceAccount;`
                                                         LoginMode=$Server.LoginMode;`
                                                         DatabaseEngineType=$Server.DatabaseEngineType;`
                                                         ActiveSessions=$server.EnumProcesses($false).Rows.Count;`
                                                         TraceFlags=$TraceFlags;`
                                                         }
    }
 
}
 
if ($OutGridView) {
    $ListInstances | Sort-Object InstanceName | Select-Object NetName, InstanceName,Edition,VersionMajor,Version,ProductLevel,`
                                                             Collation,Processors,PhysicalMemory,MaxServerMemory,DatabaseCount,`
                                                             TotalSizeMB,ServiceAccount,LoginMode,DatabaseEngineType,ActiveSessions,TraceFlags |   `
                                                Out-GridView
 
    if ($CheckDatabaseDetails) {
        $ListDatabases | Sort-Object InstanceName,DatabaseName | Select-Object InstanceName,VersionMajor,DatabaseName,CompatibilityLevel,`
                                                                               ActiveConnections,RecoveryModel,Collation,AutoClose,AutoShrink,`
                                                                               IsReadCommittedSnapshotOn,PageVerify,Size,Owner,CreateDate,`
                                                                               LastFullBackupDate,LastLogBackupDate,LastKnownGood,LastUserRead,LastUserWrite | `
                                                                 Out-GridView
    }
}
 
if ($ExportCSV) {
 
    $ListInstances | Sort-Object InstanceName | Select-Object NetName, InstanceName,Edition,VersionMajor,Version,ProductLevel,`
                                                             Collation,Processors,PhysicalMemory,MaxServerMemory,DatabaseCount,`
                                                             TotalSizeMB,ServiceAccount,LoginMode,DatabaseEngineType,ActiveSessions,TraceFlags |   `
                                                Export-Csv $ExportCSVFile -NoTypeInformation  -Force -Delimiter ";"
 
    if ($CheckDatabaseDetails) {
        $ListDatabases | Sort-Object InstanceName,DatabaseName | Select-Object InstanceName,VersionMajor,DatabaseName,CompatibilityLevel,`
                                                                               ActiveConnections,RecoveryModel,Collation,AutoClose,AutoShrink,`
                                                                               IsReadCommittedSnapshotOn,PageVerify,Size,Owner,CreateDate,`
                                                                               LastFullBackupDate,LastLogBackupDate,LastKnownGood,LastUserRead,LastUserWrite | `
                                                                 Export-Csv $ExportCSVFile -NoTypeInformation -Force -Delimiter ";"
    }
}
 
# Display grand total 
if ($global:TotalDatabaseCount -gt 0) {
    write-host ""
    write-host "Grand Total :"
    Write-Host $global:TotalDatabaseCount " Databases ("$global:TotalDatabaseStorage.ToString("N") "MB )" 
}
 
if ($DisplayInstanceErrorList) {
    write-host ""
    write-host "Errors :"
    $InstanceErrorList
}