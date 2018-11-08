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
# $InstanceList = sqlcmd -L
# or
# $InstanceList = [System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources()
# or
# $InstanceList = "srv1","srv2"
$InstanceList = Get-Content C:\temp\Serveurs.txt 


# excluded instances
$ExcludedHostList = "devsql2016","devsql2017"


$Debug = $false
$ConnectionTimeout = 1

$InstanceErrorList = @()
$DisplayInstanceErrorList = $false
$ShowDisabledJobs = $false


function Get-SQLFailedJobs ([object] $Server) {
    
    Write-host  -ForegroundColor Green "Connecting " $Server.name
    Write-host $Server.Edition " - Version " $Server.VersionString " (" $Server.ProductLevel ") - " $Server.collation


    if ($server.EngineEdition -match "Express") {
        Write-Host "SQL Server Express Edition - no jobs !" -ForegroundColor Magenta
        return
    }

    if (!($Server.ConnectionContext.IsInFixedServerRole("sysadmin"))) { 
        Write-Host $Server.ConnectionContext.TrueLogin "is not sysadmin !" -ForegroundColor Magenta
        $InstanceErrorList += "Missing permissions on $InstanceName"

        if ($Server.Databases["msdb"].IsMember("SQLAgentOperatorRole")) {
            Write-Host $Server.ConnectionContext.TrueLogin "is SQLAgentOperatorRole"
        }
        elseif ($Server.Databases["msdb"].IsMember("SQLAgentReaderRole")) {
            Write-Host $Server.ConnectionContext.TrueLogin "is not SQLAgentOperatorRole !" -ForegroundColor Magenta
            Write-Host $Server.ConnectionContext.TrueLogin "is SQLAgentReaderRole" 
        }
        else {
            Write-Host $Server.ConnectionContext.TrueLogin "is not SQLAgentOperatorRole !" -ForegroundColor Magenta
            Write-Host $Server.ConnectionContext.TrueLogin "is not SQLAgentReaderRole !" -ForegroundColor Magenta
            return
        }

    }

    
    $SQLAgent = $Server.JobServer

    Write-Host "ServiceAccount : " $SQLAgent.ServiceAccount -NoNewline 
    Write-Host " | ServiceStartMode : " $SQLAgent.ServiceStartMode " | AgentAutoStart : " $SQLAgent.SqlAgentAutoStart  -NoNewline 
    
    if (!($SQLAgent.SqlAgentMailProfile)) {
        Write-Host " | SqlAgentMailProfile : none " -ForegroundColor red -NoNewline
    }
    else {
        Write-Host " | SqlAgentMailProfile : " $SQLAgent.SqlAgentMailProfile -NoNewline
    }
    
        
    if (($SQLAgent.MaximumHistoryRows -eq -1) -or ($SQLAgent.MaximumHistoryRows -eq 999999)) {
        Write-Host " | MaximumHistoryRows : " $SQLAgent.MaximumHistoryRows -NoNewline
    }
    else {
        Write-Host " | MaximumHistoryRows : " $SQLAgent.MaximumHistoryRows -ForegroundColor red -NoNewline
    }
    
    if ($SQLAgent.MaximumJobHistoryRows -eq 100) {
        Write-Host " | MaximumJobHistoryRows : " $SQLAgent.MaximumJobHistoryRows  -ForegroundColor red -NoNewline
    }
    else {
        Write-Host " | MaximumJobHistoryRows : " $SQLAgent.MaximumJobHistoryRows  -NoNewline
    }

    
    Write-Host " "
    Write-Host $Server.JobServer.Jobs.Count " job(s) found " -ForegroundColor Magenta
    Write-Host " "
    

    if ($ShowDisabledJobs) {
        $DisabledJobs = @()
        $DisabledJobs = $Server.JobServer.Jobs | Where-Object IsEnabled -eq $False `
                                             | Select-Object Name,OwnerLoginName,LastRunDate,LastRunOutcome 
        
        Write-Host $DisabledJobs.Count " disabled job(s) found"
        $DisabledJobs | Format-Table -AutoSize
        
    }
    
    
    Write-Host " "
    $FailedJobs = @()
    $FailedJobs = $Server.JobServer.Jobs | Where-Object IsEnabled -eq $True `
                                         | Where-Object LastRunOutcome -eq "Failed" `
                                         | Where-Object NextRunDate -gt (Get-date) `
                                         | Select-Object Name,OwnerLoginName,EmailLevel,OperatorToEmail,LastRunDate,LastRunOutcome,NextRunDate 
    
    Write-Host $FailedJobs.Count " failed job(s) found"
    
    $FailedJobs | Format-Table -AutoSize
     

    Write-Host " "

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
        Get-SQLFailedJobs $Server
        write-host "_____________________________________________________________________________" -ForegroundColor Green
        Write-Host " "
    }

}

if ($DisplayInstanceErrorList) {
    write-host ""
    write-host "Errors : "
    $InstanceErrorList
}

