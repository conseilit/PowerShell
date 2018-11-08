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

# Can use a predefined list instead ....
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
    $FileInstanceList = Get-Content "C:\temp\AdditionalServers.txt" 
    $DiscoveredInstanceList += $FileInstanceList
}
catch {}


$ExcludedHostList = "devsql2016","(local)"



$ShowSystemDatabases = $false 
[int]$global:TotalDatabaseStorage = 0
[int]$global:TotalDatabaseCount = 0


$Debug = $false
$ConnectionTimeout = 1

$CheckBackup = $true
$PctLogUsedThreshold = 70
$LastFullBackupAge = -1
$LastDiffBackupAge = -1 # hoping there is at least a full or a diff backup the day before ...

$LastdbccLastKnownGoodAge = -7

$CheckAutoShrink = $true
$CheckAutoClose = $true
$CheckdbccLastKnownGood = $true

$InstanceErrorList = @()
$DisplayInstanceErrorList = $false


function Get-SQLBackup ([object] $Server) {

    Write-host  -ForegroundColor Green "Connecting "$Server.name
    Write-host $Server.Edition " - Version " $Server.VersionString " (" $Server.ProductLevel ") - " $Server.collation

    if (!($Server.ConnectionContext.IsInFixedServerRole("sysadmin"))) { 
        Write-Host $Server.ConnectionContext.TrueLogin " is not sysadmin !" -ForegroundColor Magenta
        $InstanceErrorList += "Missing permissions on $InstanceName"
    }

    $Databases = $server.Databases | Where-Object Status -eq "normal" | sort-object ID


    write-host ""
    $InstanceStorage = 0
    foreach ($Database in $Databases) {
         try {
             $InstanceStorage += $Database.size


             if (!($Server.ConnectionContext.IsInFixedServerRole("sysadmin"))) { 
                continue 
             }



             If (($ShowSystemDatabases) -or ($Database.iD -gt 4)) {
                Write-Host $Database "("$Database.size.ToString("N") "MB ) " -NoNewline

                if ($CheckdbccLastKnownGood) {
                    $LastKnownGood = $($Database.ExecuteWithResults("DBCC DBINFO() WITH TABLERESULTS").Tables[0] | Where-Object {$_.Field -eq "dbi_dbccLastKnownGood"}).value #  | Select-Object Value
                    $LastKnownGood = [datetime]::ParseExact($LastKnownGood.split(" ")[0],'yyyy-MM-dd',$null)
                    if ($LastKnownGood -lt (Get-date).AddDays($LastdbccLastKnownGoodAge)) {
                        Write-Host " | CheckDB " $LastKnownGood.ToString("yyyy-MM-dd") " " -NoNewline -ForegroundColor Red
                    }
                    else{
                        Write-Host " | CheckDB " $LastKnownGood.ToString("yyyy-MM-dd") " " -NoNewline 
                    }
                 }
                
                
                if ($Database.AutoShrink -and $CheckAutoShrink) {
                    Write-Host " | AutoShrink " -NoNewline -ForegroundColor Red
                }
                if ($database.AutoClose -and $CheckAutoClose) {
                    Write-Host " | AutoClose " -NoNewline -ForegroundColor Red
                }


                if ($CheckBackup) {

                    $PercentLogUsed =  [math]::round(($Database.LogFiles[0].UsedSpace*100.0/($Database.LogFiles[0].Size)),2)
                    if ($PercentLogUsed -ge $PctLogUsedThreshold) {
                        Write-Host "| Recovery" $database.RecoveryModel "("$database.LogReuseWaitStatus","$PercentLogUsed "% ," $([math]::round(($Database.LogFiles[0].UsedSpace),2)) "KB)"   -NoNewline -ForegroundColor red
                    }
                    else {
                        Write-Host "| Recovery" $database.RecoveryModel "("$database.LogReuseWaitStatus","$PercentLogUsed "% ," $([math]::round(($Database.LogFiles[0].UsedSpace),2)) "KB)"   -NoNewline 
                    }
                     

                    if ($database.LastBackupDate -lt (Get-date).AddDays($LastFullBackupAge)) {
                        $OupsHopeForDiffBackup = $true
                    }
                    else{
                        $OupsHopeForDiffBackup = $false
                    }

               
                    if ($OupsHopeForDiffBackup) {
                        if ($database.LastDifferentialBackupDate -lt (Get-date).AddDays($LastDiffBackupAge)) {
                            $ButThereIsaDiffBackup = $false
                        }
                        else{
                            $ButThereIsaDiffBackup = $true
                        }
                    }

                    if (($OupsHopeForDiffBackup) -and (!($ButThereIsaDiffBackup)) ) {
                        Write-Host " | Last Full" $database.LastBackupDate.ToString("yyyy-MM-dd") -NoNewline -ForegroundColor Red
                        Write-Host " | Last Diff" $database.LastDifferentialBackupDate.ToString("yyyy-MM-dd") -NoNewline -ForegroundColor Red
                    }
                    elseif (($OupsHopeForDiffBackup) -and ($ButThereIsaDiffBackup)) {
                        Write-Host " | Last Full" $database.LastBackupDate.ToString("yyyy-MM-dd") -NoNewline -ForegroundColor Magenta
                        Write-Host " | Last Diff" $database.LastDifferentialBackupDate.ToString("yyyy-MM-dd") -NoNewline
                    }
                    else {
                        Write-Host " | Last Full" $database.LastBackupDate.ToString("yyyy-MM-dd") -NoNewline 
                        if ($database.LastDifferentialBackupDate.Year -ne 1){
                            Write-Host " | Last Diff" $database.LastDifferentialBackupDate.ToString("yyyy-MM-dd") -NoNewline
                        }
                        else {
                            Write-Host " | Last Diff - none - " -NoNewline
                        }
                   
                    }


                    if ($database.RecoveryModel -ne "Simple"){
                        if ( $database.LastLogBackupDate -lt (Get-date).AddHours(-4) ) {
                            Write-Host " | Last Log" $database.LastLogBackupDate.ToString("yyyy-MM-dd HH:mm:ss") -NoNewline -ForegroundColor Red
                        }
                        else
                        {
                            Write-Host " | Last Log" $database.LastLogBackupDate.ToString("yyyy-MM-dd HH:mm:ss") -NoNewline 
                        }
                    }
                    else {
                        Write-Host " | Last Log N/A" -NoNewline
                    }
                }

                write-host ""
             }
        }
        catch {
            
            if ($Debug) {
                #Write-Host "Missing permissions on $server $Database" -ForegroundColor Red
                Write-host -ForegroundColor Red $_.Exception.Message
            }
        }
    }


    Write-Host ""
    write-host $server.Databases.Count "Databases ("$InstanceStorage.ToString("N") "MB )"
    $global:TotalDatabaseStorage = $global:TotalDatabaseStorage + $InstanceStorage   
    $global:TotalDatabaseCount = $global:TotalDatabaseCount  + $server.Databases.Count
}



ForEach ($InstanceName in $InstanceList) {
    $InstanceName = $InstanceName.trim()
    if ($InstanceName -eq "") {continue}
    if ($InstanceName -eq "Servers:") {continue}

    # Check excluded instances
    if ($ExcludedHostList -contains $InstanceName) {
        if ($Debug) {
            write-host "#############################################################################" -ForegroundColor yellow
            Write-Host $InstanceName " excluded" -ForegroundColor yellow
            write-host "_____________________________________________________________________________" -ForegroundColor yellow
            Write-Host " "
        }
        continue
    }
        
    $Server = New-Object -TypeName  Microsoft.SQLServer.Management.Smo.Server($InstanceName)
    $Server.ConnectionContext.ConnectTimeout = $ConnectionTimeout

    if (!($Server.ComputerNamePhysicalNetBIOS)) {
        $InstanceErrorList +="Error connecting $InstanceName"
    }
    else {
        write-host "#############################################################################" -ForegroundColor Green
        Get-SQLBackup $Server
        write-host "_____________________________________________________________________________" -ForegroundColor Green
        Write-Host " "
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

