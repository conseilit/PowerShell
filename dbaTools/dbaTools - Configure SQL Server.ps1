#==============================================================================
#
#  Summary:  SQL Server configuration using dbaTools
#
#  ----------------------------------------------------------------------------
#  Written by Christophe LAPORTE
#	Blog    : http://conseilit.wordpress.com
#	Twitter : @ConseilIT
#  
#  You may alter this code for your own *non-commercial* purposes. You may
#  republish altered code as long as you give due credit.
#  
#  THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
#  ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED 
#  TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
#  PARTICULAR PURPOSE.
#==============================================================================

#
# Script based on dbaTools commands
# Thanks to Chrissy LeMaire (@cl | https://blog.netnerds.net/ )
#          , Rob Sewell (@SQLDBAWithBeard | https://sqldbawithabeard.com/)
#          , and all SQL Server community
# http://dbatools.io
# Install-Module dbatools  -Scope CurrentUser
#


Clear-Host
$InstanceName             = "SQLBAG1"
$dbaDatabase              = "_DBA"
$BackupCleanupTime        = 15 <# days #> * 24

$BackupStrategy           = "FullDiffLog" <# FullDiffLog | FullLog  #>
$TimeLimit                = 7200          <# Time limit in seconds for Index & Stats management #>
$IncludeMonitoring        = $true         <# Add tables & jobs to monitor SQL Server activity : CPU, TempDB Usage, LogReuseWaitDescription #>
$MonitoringCleanupTime    = 90            <# Days #>
$MonitoringInterval       = 5             <# Minutes #>
$AdjustMaxMemory          = $true         <# Adjust Max Memory Setting #>




[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Log($out) { 
    $out=[System.DateTime]::Now.ToString("yyyy.MM.dd-hh:mm:ss") + " ---- " + $out; 
    Write-Output "$out" 
} 

Log "Begin"

$dbaToolsModule = Get-Module -ListAvailable -Name dbatools
if ($dbaToolsModule) {
    Log "dbaTools module version $($dbaToolsModule.Version) installed"
} 
else {
    Log "Module dbatools missing"
    Log "Please run the following command"
    Log "Install-Module dbatools  -Scope CurrentUser"
    return
}


if ((Get-InstalledModule -Name "dbatools").version.major -ge 2) {
    # Due to changes by MS https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/
    Set-DbatoolsInsecureConnection -SessionOnly  | Out-Null
}



# check connection to the instance
try {
    Log "Connecting $InstanceName"
    $Server = Connect-DbaInstance -SqlInstance $InstanceName
    #$cred = Get-Credential
    #$Server = Connect-DbaInstance -SqlInstance $InstanceName -SqlCredential $cred
    $Server | Select-Object DomainInstanceName,VersionMajor,DatabaseEngineEdition,Edition,ServiceAccount
} catch {
    Log "Error connecting $InstanceName"
    return
}

<#
# Check if SQL Agent is stopped / manual
if (!($(Get-DbaInstanceProperty -SqlInstance $Server -InstanceProperty  Edition).value -Match "Express")){
	$AgentServiceName = (Get-DbaService -computername $InstanceName -type Agent).ServiceName
	Set-Service $AgentServiceName -startuptype automatic
	Start-Service $AgentServiceName
}
#>


#region alter default backup folder
#$Server.BackupDirectory
    <#
    
    $Server.BackupDirectory = "\\xxxxxxxx\yyyyy"
    $Server.alter()

    if ($Server.ConnectionContext -match "User ID") {
        $Server = Connect-DbaInstance -SqlInstance $InstanceName -SqlCredential $cred
    } else {
        $Server = Connect-DbaInstance -SqlInstance $InstanceName
    }
    
    $Server  | Select-Object DomainInstanceName,VersionMajor,DatabaseEngineEdition
    Log "Backup folder updated to $($Server.BackupDirectory) "
    #>
#endregion

<#
#region TempDB configuration

    $TempDBLogPath = split-path (Get-DbaDBFile -SqlInstance $Server -Database TempDB | Where-Object {$_.ID -eq 2}).PhysicalName -Parent
    $TempDBDataPath = split-path (Get-DbaDBFile -SqlInstance $Server -Database TempDB | Where-Object {$_.ID -eq 1}).PhysicalName -Parent

    $TempDBDataFileCount = $(Get-DbaInstanceProperty -SqlInstance $Server  -InstanceProperty  Processors).value
    $TempDBDataFileSizeMB = $TempDBDataFileCount * 1024 

    Set-DbaTempDbConfig -SqlInstance $Server -DataFileCount $TempDBDataFileCount `
        -DataPath $TempDBDataPath -LogPath $TempDBLogPath -DataFileSize $TempDBDataFileSizeMB 

#endregion
#>

#region SQL Server properties configuration

    Log "Updating SQL Server configuration"
    Set-DbaErrorLogConfig -SqlInstance $Server -LogCount 99                             | Out-Null
    Set-DbaSpConfigure -SqlInstance $Server -name ShowAdvancedOptions         -Value 1  | Out-Null
    Set-DbaSpConfigure -SqlInstance $Server -name RemoteDacConnectionsEnabled -value 1  | Out-Null
    Set-DbaSpConfigure -SqlInstance $Server -name OptimizeAdhocWorkloads      -value 1  | Out-Null
    Set-DbaSpConfigure -SqlInstance $Server -name CostThresholdForParallelism -value 35 | Out-Null
    Set-DbaSpConfigure -SqlInstance $Server -name DefaultBackupCompression    -value 1  | Out-Null
    Set-DbaSpConfigure -SqlInstance $Server -name BlockedProcessThreshold     -value 1  | Out-Null
    Set-DbaSpConfigure -SqlInstance $Server -name ContainmentEnabled          -value 1  | Out-Null

    # Adjust memory setting ?
    if ($AdjustMaxMemory) {
        Log "Checking Max Server memory"
        $DbaMaxMemory = Test-DbaMaxMemory -SqlInstance $Server
        if ($DbaMaxMemory.MaxValue -gt $DbaMaxMemory.Total) {
            Log "Max SQL memory set to higher than the total memory"
            Log "Ajusting Max Memory Setting according Jonathan Kehayias's recommendation"
            Log " https://www.sqlskills.com/blogs/jonathan/wow-an-online-calculator-to-misconfigure-your-sql-server-memory/ "
            $DbaMaxMemory
            Set-DbaMaxMemory -SqlInstance $Server | Out-Null
        } else {
            Log "Max Server memory might have been set during setup : MaxValue $($DbaMaxMemory.MaxValue) MB | Total $($DbaMaxMemory.Total) MB"
            Log ""
        }
    }
    
    if ($(Get-DbaInstanceProperty -SqlInstance $Server -InstanceProperty  versionMajor).value -le 14) {

        # Change the retention settings for system_health Extended Events session
        Stop-DbaXESession -SqlInstance $Server -Session "system_health"  | Out-Null
        Invoke-DbaQuery -SqlInstance $Server -Database "master" -Query "
            ALTER EVENT SESSION [system_health] ON SERVER
            DROP TARGET package0.event_file;
            GO
            ALTER EVENT SESSION [system_health] ON SERVER
            ADD TARGET package0.event_file
                (SET filename=N'system_health.xel',
                    max_file_size=(100),
                    max_rollover_files=(10)
                )
        " | Out-Null
        Start-DbaXESession -SqlInstance $Server -Session "system_health" | Out-Null


        # Change the retention settings for AlwaysOn_health Extended Events session
        $XEStatus = (Get-DbaXESession -SqlInstance $Server -Session "AlwaysOn_health").Status
        If ($XEStatus -eq "Started"){
            Stop-DbaXESession -SqlInstance $Server -Session "AlwaysOn_health" | Out-Null
        }
        Invoke-DbaQuery -SqlInstance $Server -Database "master" -Query "
            ALTER EVENT SESSION [AlwaysOn_health] ON SERVER
            DROP TARGET package0.event_file;
            GO
            ALTER EVENT SESSION [AlwaysOn_health] ON SERVER
            ADD TARGET package0.event_file
                (SET filename=N'AlwaysOn_health.xel',
                    max_file_size=(100),
                    max_rollover_files=(10)
                )

        " | Out-Null
        If ($XEStatus -eq "Started"){
            Start-DbaXESession -SqlInstance $Server -Session "AlwaysOn_health" | Out-Null
        }
    }
        
    if ($(Get-DbaInstanceProperty -SqlInstance $Server -InstanceProperty  versionMajor).value -ge 11) {

        # Stop collecting noise events
        # https://www.sqlskills.com/blogs/erin/the-security_error_ring_buffer_recorded-event-and-why-you-dont-need-it/
        Invoke-DbaQuery -SqlInstance $Server -Database "master" -Query "
            ALTER EVENT SESSION [system_health] ON SERVER
            DROP EVENT sqlserver.security_error_ring_buffer_recorded;
        " | Out-Null

        
        Invoke-DbaQuery -SqlInstance $Server -Database "master" -Query "
            CREATE EVENT SESSION [PerformanceIssues] ON SERVER 
                ADD EVENT sqlserver.rpc_completed(SET collect_statement=(1)
                    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.database_name,
                        sqlserver.query_hash,sqlserver.session_id,sqlserver.sql_text,sqlserver.username,sqlserver.transaction_id)
                    WHERE ([package0].[greater_than_equal_uint64]([duration],(250000)))),
                ADD EVENT sqlserver.sql_batch_completed(
                    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.database_name,
                        sqlserver.query_hash,sqlserver.session_id,sqlserver.sql_text,sqlserver.username,sqlserver.transaction_id)
                    WHERE ([package0].[greater_than_equal_uint64]([duration],(250000)))),
                ADD EVENT sqlserver.blocked_process_report(
                    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.database_name,
                        sqlserver.query_hash,sqlserver.session_id,sqlserver.sql_text,sqlserver.username,sqlserver.transaction_id)),
                ADD EVENT sqlserver.xml_deadlock_report(
                    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.database_name,
                        sqlserver.query_hash,sqlserver.session_id,sqlserver.sql_text,sqlserver.username,sqlserver.transaction_id))
                ADD TARGET package0.event_file(SET filename=N'PerformanceIssues',max_file_size=(100),max_rollover_files=(10))
                    WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,
                        MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=ON,STARTUP_STATE=ON);
        " | Out-Null
        Start-DbaXESession -SqlInstance $Server -Session "PerformanceIssues"| Out-Null

        <#
        # maybe remove the event from system_health
        Invoke-DbaQuery -SqlInstance $Server -Database "master" -Query "
            ALTER EVENT SESSION [system_health] ON SERVER
            DROP EVENT sqlserver.xml_deadlock_report;
        " | Out-Null
        #>

        # TempDB autogrowth
        Invoke-DbaQuery -SqlInstance $Server -Database "master" -Query "
			CREATE EVENT SESSION [TempDBAutogrowth] ON SERVER 
			ADD EVENT sqlserver.database_file_size_change(
				ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,
					   sqlserver.database_name,sqlserver.session_id,sqlserver.sql_text,sqlserver.transaction_id)
				WHERE ([database_id]=(2) AND [session_id]>(50))),
			ADD EVENT sqlserver.databases_log_file_size_changed(
				ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,
					   sqlserver.database_name,sqlserver.session_id,sqlserver.sql_text,sqlserver.transaction_id)
				WHERE ([database_id]=(2) AND [session_id]>(50))),
			ADD EVENT sqlserver.error_reported(
				ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.plan_handle,
					   sqlserver.session_id,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
				WHERE ([database_id]=(2) AND [session_id]>(50) AND ([error_number]=(1101) OR [error_number]=(1105))))
			ADD TARGET package0.event_file(SET filename=N'TempDBAutogrowth',max_file_size=(10),max_rollover_files=(5))
			WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,
				  MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=ON,STARTUP_STATE=ON)
        " | Out-Null
        Start-DbaXESession -SqlInstance $Server -Session "TempDBAutogrowth" | Out-Null

		# UserDB Log Autogrowth
		Invoke-DbaQuery -SqlInstance $Server -Database "master" -Query "
            CREATE EVENT SESSION [UserDBLogAutogrowth] ON SERVER 
            ADD EVENT sqlserver.databases_log_file_size_changed(
                ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,
					   sqlserver.database_name,sqlserver.session_id,sqlserver.sql_text,sqlserver.transaction_id)
                WHERE ([database_id]>(4) AND [session_id]>(50)))
            ADD TARGET package0.event_file(SET filename=N'UserDBLogAutogrowth',max_file_size=(10),max_rollover_files=(5))
            WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,
				  MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=ON,STARTUP_STATE=ON)
		" | Out-Null

		Start-DbaXESession -SqlInstance $Server -Session "UserDBLogAutogrowth"| Out-Null


        # Audit SA activity
        Invoke-DbaQuery -SqlInstance $server -Database "master" -Query "
            CREATE EVENT SESSION [AuditLoginSA] ON SERVER 
            ADD EVENT sqlserver.login(
                ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,
                    sqlserver.database_id,sqlserver.database_name,
                    sqlserver.session_id,sqlserver.sql_text,sqlserver.username)
                WHERE ([sqlserver].[username]=N'sa'))
            ADD TARGET package0.event_file(SET filename=N'AuditLoginSA',max_file_size=(20))
            WITH (STARTUP_STATE=ON)
        " | Out-Null
        Start-DbaXESession -SqlInstance $server -Session "AuditLoginSA"  | Out-Null

        # DDL audit
        $cmd = "
            CREATE SERVER AUDIT [Audit-DDL]
            TO FILE (	
                FILEPATH = N'$($server.ErrorLogPath)'	
                ,MAXSIZE = 100 MB
                ,MAX_ROLLOVER_FILES = 10
                ,RESERVE_DISK_SPACE = OFF
            )
            WITH
            (	QUEUE_DELAY = 1000
                ,ON_FAILURE = CONTINUE
            ) 
            WHERE     ([Object_Name]<>'telemetry_xevents' and [server_principal_name] not like '%SQLTELEMETRY%')
              AND NOT (class_type = 19267 AND action_id = 8278);

            ALTER SERVER AUDIT [Audit-DDL] WITH (STATE = ON) 
        "
        Invoke-DbaQuery -SqlInstance $server -Query $cmd  | Out-Null


        $cmd = "
            CREATE SERVER AUDIT SPECIFICATION [AuditSpecification-DDL]
            FOR SERVER AUDIT [Audit-DDL]
                ADD (DATABASE_OBJECT_CHANGE_GROUP),            
                ADD (DATABASE_OBJECT_OWNERSHIP_CHANGE_GROUP),  
                ADD (DATABASE_OBJECT_PERMISSION_CHANGE_GROUP), 
                ADD (DATABASE_OWNERSHIP_CHANGE_GROUP),         
                ADD (DATABASE_PERMISSION_CHANGE_GROUP),        
                ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),         
                ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),       
                ADD (LOGIN_CHANGE_PASSWORD_GROUP),             
                ADD (SERVER_OBJECT_CHANGE_GROUP),              
                ADD (SERVER_OBJECT_OWNERSHIP_CHANGE_GROUP),    
                ADD (SERVER_OBJECT_PERMISSION_CHANGE_GROUP),   
                ADD (SERVER_PERMISSION_CHANGE_GROUP),          
                ADD (SERVER_PRINCIPAL_CHANGE_GROUP),           
                ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP)          
            WITH (STATE=ON)
        "
        Invoke-DbaQuery -SqlInstance $server -Query $cmd | Out-Null


    }
    
    
    if (!($(Get-DbaInstanceProperty -SqlInstance $Server -InstanceProperty  Edition).value -Match "Express")){

        Log "Updating SQL Server Agent configuration"
        # increase SQL Agent default retention
        Set-DbaAgentServer -SqlInstance $Server -MaximumHistoryRows 999999 -MaximumJobHistoryRows 999999 | Out-Null

        # add syspolicy_purge_history to Database Maintenance Category
        Set-DbaAgentJob -SqlInstance $Server -Job "syspolicy_purge_history" -Category "Database Maintenance"  | Out-Null

    }

#endregion


# Create DBA database if needed
if (!(Get-DbaDatabase -SqlInstance $Server -Database $dbaDatabase )){
    New-DbaDatabase -SqlInstance $Server -Name $dbaDatabase -Owner sa -RecoveryModel Simple | Out-Null
    Log "[$dbaDatabase] database created"
} else {
    Log "[$dbaDatabase] database already exists"
}

#region SQL Server community rocks !!!

    # Install sp_whoisactive stored procedure, by Adam Machanic 
    # GitHub : https://github.com/amachanic/sp_whoisactive
    # -LocalFile "c:\temp\who_is_active_v12_00.sql"
    Install-DbaWhoIsActive -SqlInstance $Server -Database $dbaDatabase | Out-Null


    # Install sp_whoisactive stored procedure, by Brent Ozar 
    # GitHub : https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit
    # -LocalFile "c:\temp\Install-All-Scripts.sql"
    Install-DbaFirstResponderKit -SqlInstance $Server -Database $dbaDatabase | Out-Null

#endregion


#region Database maintenance setup

    Log "Log Deploying Ola Hallengren maintenance solution ( https://ola.hallengren.com/ )"

	# Install Maintenance Solution by Ola Hallengren https://ola.hallengren.com/
	# GitHub : https://github.com/olahallengren/sql-server-maintenance-solution
	# -LocalFile "c:\temp\sql-server-maintenance-solution-master.zip"
    Install-DbaMaintenanceSolution -SqlInstance $Server -Database $dbaDatabase -CleanupTime $BackupCleanupTime `
                                   -InstallJobs -LogToTable -ReplaceExisting -Force | out-null

    $tSQL = "
        CREATE PROCEDURE dbo.sp_sp_start_job_wait
        (
            @job_name SYSNAME,
            @WaitTime DATETIME = '00:00:30', -- this is parameter for check frequency
            @JobCompletionStatus INT = null OUTPUT
        )
        AS
        BEGIN
            -- https://www.mssqltips.com/sqlservertip/2167/custom-spstartjob-to-delay-next-task-until-sql-agent-job-has-completed/

            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
            SET NOCOUNT ON

            -- DECLARE @job_name sysname
            DECLARE @job_id UNIQUEIDENTIFIER
            DECLARE @job_owner sysname

            --Createing TEMP TABLE
            CREATE TABLE #xp_results (	job_id UNIQUEIDENTIFIER NOT NULL,
                                        last_run_date INT NOT NULL,
                                        last_run_time INT NOT NULL,
                                        next_run_date INT NOT NULL,
                                        next_run_time INT NOT NULL,
                                        next_run_schedule_id INT NOT NULL,
                                        requested_to_run INT NOT NULL, -- BOOL
                                        request_source INT NOT NULL,
                                        request_source_id sysname COLLATE database_default NULL,
                                        running INT NOT NULL, -- BOOL
                                        current_step INT NOT NULL,
                                        current_retry_attempt INT NOT NULL,
                                        job_state INT NOT NULL
                                    )

            SELECT @job_id = job_id FROM msdb.dbo.sysjobs
            WHERE name = @job_name

            SELECT @job_owner = SUSER_SNAME()

            INSERT INTO #xp_results
            EXECUTE master.dbo.xp_sqlagent_enum_jobs 1, @job_owner, @job_id 

            -- Start the job if the job is not running
            IF NOT EXISTS(SELECT TOP 1 * FROM #xp_results WHERE running = 1)
                EXEC msdb.dbo.sp_start_job @job_name = @job_name

            -- Give 5 sec for think time.
            WAITFOR DELAY '00:00:05'

            DELETE FROM #xp_results
            INSERT INTO #xp_results
            EXECUTE master.dbo.xp_sqlagent_enum_jobs 1, @job_owner, @job_id 

            WHILE EXISTS(SELECT TOP 1 * FROM #xp_results WHERE running = 1)
            BEGIN

                WAITFOR DELAY @WaitTime

                -- Information 
                -- raiserror('JOB IS RUNNING', 0, 1 ) WITH NOWAIT 

                DELETE FROM #xp_results

                INSERT INTO #xp_results
                EXECUTE master.dbo.xp_sqlagent_enum_jobs 1, @job_owner, @job_id 

            END

            SELECT TOP 1 @JobCompletionStatus = run_status 
            FROM msdb.dbo.sysjobhistory
            WHERE job_id = @job_id
            AND step_id = 0
            ORDER BY run_date DESC, run_time DESC

            IF @JobCompletionStatus <> 1
            BEGIN
                RAISERROR ('[ERROR]:%s job is either failed, cancelled or not in good state. Please check',16, 1, @job_name) WITH LOG
            END

            RETURN @JobCompletionStatus
        END
    "
    Invoke-DbaQuery -SqlInstance $Server -Database $dbaDatabase -Query $tSQL  | Out-Null

    Log "Updating IndexOptimize default parameters"
    try {
        $tSQL = Get-DbaDbStoredProcedure -SqlInstance $server -Database $dbaDatabase -Name "IndexOptimize" | Export-DbaScript -Passthru 
        $tSQL = $tSQL.Replace("CREATE PROCEDURE", "ALTER PROCEDURE")
        $tSQL = $tSQL.Replace("@OnlyModifiedStatistics nvarchar(max) = 'N'", "@OnlyModifiedStatistics nvarchar(max) = 'Y'")
        $tSQL = $tSQL.Replace("@UpdateStatistics nvarchar(max) = NULL", "@UpdateStatistics nvarchar(max) = 'ALL'")
        $tSQL = $tSQL.Replace("@StatisticsSample int = NULL", "@StatisticsSample int = 100")
        $tSQL = $tSQL.Replace("@LockTimeout int = NULL", "@LockTimeout int = 1")
        $tSQL = $tSQL.Replace("@LockMessageSeverity int = 16", "@LockMessageSeverity int = 10")
        $tSQL = $tSQL.Replace("@TimeLimit int = NULL", "@TimeLimit int = $TimeLimit")
        $tSQL = $tSQL.Replace("@LogToTable nvarchar(max) = 'N'", "@LogToTable nvarchar(max) = 'Y'")

        #$tSQL = $tSQL.Replace("@FragmentationMedium nvarchar(max) = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE'", "@FragmentationMedium nvarchar(max) = NULL")
        #$tSQL = $tSQL.Replace("@FragmentationLevel2 int = 30", "@FragmentationLevel2 int = 50")
        
        Invoke-DbaQuery -SqlInstance $server -Database $dbaDatabase -Query $(-join $tSQL) 
    } catch {
        Log "Updating IndexOptimize procedure failed !!"
    }

#endregion



#region Housekeeping

    Log "Scheduling Housekeeping job"
    $job = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - HouseKeeping' -Category "Database Maintenance" -OwnerLogin sa

    New-DbaAgentSchedule -SqlInstance $Server -Schedule $job.name -Job $job.name `
                        -FrequencyType Daily -FrequencyInterval Everyday `
                        -FrequencySubdayType Time -FrequencySubDayinterval 0 `
                        -StartTime "000001" -EndTime "235959" -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "Cycle Errorlog" -Force `
                        -Database master -StepId 1 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC msdb.dbo.sp_cycle_errorlog" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseIntegrityCheck - SYSTEM_DATABASES" -Force `
                        -Database master -StepId 2 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='DatabaseIntegrityCheck - SYSTEM_DATABASES', @WaitTime = '00:01:00'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null             
                        
    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseBackup - SYSTEM_DATABASES - FULL" -Force `
                        -Database master -StepId 3 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='DatabaseBackup - SYSTEM_DATABASES - FULL', @WaitTime = '00:01:00'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null   

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "CommandLog Cleanup" -Force `
                        -Database master -StepId 4 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC msdb.dbo.sp_start_job 'CommandLog Cleanup'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null                        
        
    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "Output File Cleanup" -Force `
                        -Database master -StepId 5 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC msdb.dbo.sp_start_job 'Output File Cleanup'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null                        

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "sp_delete_backuphistory" -Force `
                        -Database master -StepId 6 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='sp_delete_backuphistory', @WaitTime = '00:01:00'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null                        

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "sp_purge_jobhistory" -Force `
                        -Database master -StepId 7  `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='sp_purge_jobhistory', @WaitTime = '00:01:00'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null                        

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseMail - Database Mail cleanup" -Force `
                        -Database master -StepId 8 `
                        -Subsystem "TransactSql" `
                        -Command "DECLARE @DeleteBeforeDate DateTime = (Select DATEADD(d,-30, GETDATE()))
                                EXEC msdb.dbo.sysmail_delete_mailitems_sp @sent_before = @DeleteBeforeDate
                                EXEC msdb.dbo.sysmail_delete_log_sp @logged_before = @DeleteBeforeDate" `
                        -OnSuccessAction QuitWithSuccess `
                        -OnFailAction QuitWithFailure | Out-Null             
                        
            
                        
#endregion


#region Database backup
    Log "Scheduling 'USER_DATABASES - FULL' job"
    $job = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - USER_DATABASES - FULL' -Category "Database Maintenance" -OwnerLogin sa

    if ($BackupStrategy -eq "FullDiffLog") {
        New-DbaAgentSchedule -SqlInstance $Server -Schedule $job.name -Job $job.name `
                            -FrequencyType Weekly -FrequencyInterval Sunday `
                            -FrequencySubdayType Time -FrequencySubDayinterval 0 -FrequencyRecurrenceFactor 1 `
                            -StartTime "010000" -EndTime "235959" -Force | Out-Null
    } else {
        New-DbaAgentSchedule -SqlInstance $Server -Schedule $job.name -Job $job.name `
                            -FrequencyType Daily -FrequencyInterval EveryDay `
                            -FrequencySubdayType Time -FrequencySubDayinterval 0 -FrequencyRecurrenceFactor 1 `
                            -StartTime "010000" -EndTime "235959" -Force | Out-Null
    }


    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseIntegrityCheck - USER_DATABASES" -Force `
                        -Database master -StepId 1 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='DatabaseIntegrityCheck - USER_DATABASES', @WaitTime = '00:01:00'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "IndexOptimize - USER_DATABASES" -Force `
                        -Database master -StepId 2 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='IndexOptimize - USER_DATABASES', @WaitTime = '00:01:00'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null                        
        
    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseBackup - USER_DATABASES - FULL" -Force `
                        -Database master -StepId 3 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='DatabaseBackup - USER_DATABASES - FULL', @WaitTime = '00:01:00'" `
                        -OnSuccessAction QuitWithSuccess `
                        -OnFailAction QuitWithFailure | Out-Null                        
                            
#endregion

#region Diff backup
    Log "Scheduling 'USER_DATABASES - DIFF' job"
    $job = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - USER_DATABASES - DIFF' -Category "Database Maintenance" -OwnerLogin sa

    if ($BackupStrategy -eq "FullLog") {
        $job | Set-DbaAgentJob -Disabled
    }

    New-DbaAgentSchedule -SqlInstance $Server -Schedule $job.name -Job $job.name `
                        -FrequencyType Weekly -FrequencyInterval Monday,Tuesday,Wednesday,Thursday,Friday,Saturday `
                        -FrequencySubdayType Time -FrequencySubDayinterval 0 -FrequencyRecurrenceFactor 1 `
                        -StartTime "010000" -EndTime "235959" -Force | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseIntegrityCheck - USER_DATABASES" -Force `
                        -Database master -StepId 1 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='DatabaseIntegrityCheck - USER_DATABASES', @WaitTime = '00:01:00'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null

    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "IndexOptimize - USER_DATABASES" -Force `
                        -Database master -StepId 2 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='IndexOptimize - USER_DATABASES', @WaitTime = '00:01:00'" `
                        -OnSuccessAction GoToNextStep `
                        -OnFailAction GoToNextStep | Out-Null                        
        
    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseBackup - USER_DATABASES - DIFF" -Force `
                        -Database master -StepId 3 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC [$dbaDatabase].[dbo].sp_sp_start_job_wait @job_name='DatabaseBackup - USER_DATABASES - DIFF', @WaitTime = '00:01:00'" `
                        -OnSuccessAction QuitWithSuccess `
                        -OnFailAction QuitWithFailure | Out-Null                       

#endregion

#region Log backup
    Log "Scheduling 'USER_DATABASES - LOG' job"
    $job = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - USER_DATABASES - LOG' -Category "Database Maintenance" -OwnerLogin sa 
                            
    New-DbaAgentSchedule -SqlInstance $Server -Schedule $job.name -Job $job.name `
                        -FrequencyType Daily -FrequencyInterval EveryDay `
                        -FrequencySubdayType Minutes -FrequencySubDayinterval 30 `
                        -StartTime "001500" -EndTime "235959" -Force | Out-Null

                        
    New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseBackup - USER_DATABASES - LOG" -Force `
                        -Database master -StepId 1 `
                        -Subsystem "TransactSql" `
                        -Command "EXEC msdb.dbo.sp_start_job 'DatabaseBackup - USER_DATABASES - LOG'" `
                        -OnSuccessAction QuitWithSuccess `
                        -OnFailAction QuitWithFailure | Out-Null

<#
New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "DatabaseBackup - SYSTEM_DATABASES - LOG" -Force `
                    -Database master -StepId 2 `
                    -Subsystem "TransactSql" `
                    -Command "EXECUTE [$dbaDatabase].[dbo].[DatabaseBackup]
                                @Databases = 'SYSTEM_DATABASES',
                                @Directory = N'$defaultbackuplocation',
                                @BackupType = 'LOG',
                                @Verify = 'Y',
                                @CleanupTime = $BackupCleanupTime,
                                @CheckSum = 'Y',
                                @LogToTable = 'Y' " `
                    -OnSuccessAction QuitWithSuccess `
                    -OnFailAction QuitWithFailure | Out-Null                 
#>

#endregion



#region Monitoring SQL Server
    if ($IncludeMonitoring) {

        Log "Adding basic instance monitoring"
        $tSQL = "
            CREATE TABLE [dbo].[TlogUsage](
                [CollectTime] [datetime] NOT NULL,
                [Instance] [nvarchar](128) NULL,
                [Database Name] [sysname] NOT NULL,
                [Recovery Model] [nvarchar](60) NULL,
                [LogReuseWaitDescription] [nvarchar](60) NULL,
                [LogSize(MB)] [decimal](18, 2) NULL,
                [LogUsed(MB)] [decimal](18, 2) NULL,
                [LogUsed%] [decimal](22, 2) NULL,
                INDEX  [CI_TlogUsage_CollectTime] CLUSTERED ([CollectTime])
            );
            CREATE TABLE TempDBUsage (
                [CollectTime] [datetime] NOT NULL,
                [usr_obj_kb] INT NULL,
                [internal_obj_kb] INT NULL,
                [version_store_kb] INT NULL,
                [freespace_kb] INT NULL,
                [mixedextent_kb] INT NULL,
                INDEX  [CI_TempDBUsage_CollectTime] CLUSTERED ([CollectTime] )
            );        "
        Invoke-DbaQuery -SqlInstance $Server -Database $dbaDatabase -Query $tSQL  | Out-Null

        $job = New-DbaAgentJob -SqlInstance $Server -Job '_DBA - Instance Monitoring' -Category "Monitoring" -OwnerLogin sa -Force

        New-DbaAgentSchedule -SqlInstance $Server -Schedule $job.name -Job $job.name `
                            -FrequencyType Daily -FrequencyInterval Everyday `
                            -FrequencySubdayType Minutes -FrequencySubDayinterval $MonitoringInterval `
                            -StartTime "000100" -EndTime "235959" -Force | Out-Null

        New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "_DBA - TempDBUsage" -Force `
                            -Database master -StepId 1 `
                            -Subsystem "TransactSql" `
                            -Command "
                INSERT INTO $dbaDatabase.dbo.TempDBUsage
                SELECT  getdate() as CollectTime,
                        SUM (user_object_reserved_page_count)*8 as usr_obj_kb,
                        SUM (internal_object_reserved_page_count)*8 as internal_obj_kb,
                        SUM (version_store_reserved_page_count)*8 as version_store_kb,
                        SUM (unallocated_extent_page_count)*8 as freespace_kb,
                        SUM (mixed_extent_page_count)*8 as mixedextent_kb
                FROM tempdb.sys.dm_db_file_space_usage;

                DELETE FROM $dbaDatabase.dbo.TempDBUsage 
                WHERE CollectTime < DATEADD(DAY,-$MonitoringCleanupTime,getdate());
                            " `
                            -OnSuccessAction GoToNextStep `
                            -OnFailAction GoToNextStep | Out-Null

        New-DbaAgentJobStep -SqlInstance $Server -Job $job.name -StepName "_DBA - Log TLog Reuse Wait" -Force `
                            -Database master -StepId 2 `
                            -Subsystem "TransactSql" `
                            -Command "
                INSERT INTO $dbaDatabase.dbo.TlogUsage
                SELECT  getdate() as CollectTime,@@servername AS Instance,db.[name] AS [Database Name], 
                        db.recovery_model_desc AS [Recovery Model], db.log_reuse_wait_desc AS [LogReuseWaitDescription], 
                        CONVERT(DECIMAL(18,2), ls.cntr_value/1024.0) AS [Log Size (MB)], CONVERT(DECIMAL(18,2), 
                        lu.cntr_value/1024.0) AS [Log Used (MB)],
                        CAST(CAST(lu.cntr_value AS FLOAT) / CAST(ls.cntr_value AS FLOAT)AS DECIMAL(18,2)) * 100 AS [LogUsed%]
                FROM sys.databases AS db WITH (NOLOCK)
                INNER JOIN sys.dm_os_performance_counters AS lu WITH (NOLOCK) ON db.name = lu.instance_name
                INNER JOIN sys.dm_os_performance_counters AS ls WITH (NOLOCK) ON db.name = ls.instance_name
                WHERE lu.counter_name LIKE N'Log File(s) Used Size (KB)%' 
                AND ls.counter_name LIKE N'Log File(s) Size (KB)%'
                AND ls.cntr_value > 0 
                AND db.database_id > 4;

                DELETE FROM $dbaDatabase.dbo.TlogUsage 
                WHERE CollectTime < DATEADD(DAY,-$MonitoringCleanupTime,getdate());
                            " `
                            -OnSuccessAction QuitWithSuccess `
                            -OnFailAction QuitWithFailure | Out-Null

    }
#endregion

#region Final checks


    if ($Server.ConnectionContext -match "User ID") {
        $Server = Connect-DbaInstance -SqlInstance $InstanceName -SqlCredential $cred
    } else {
        $Server = Connect-DbaInstance -SqlInstance $InstanceName
    }
  
    Log "Checking SQL Server nertwork latency"  
    Test-DbaNetworkLatency -SqlInstance $server -Count 10 -Query "select @@servername,@@version" | Format-List 


    $MaintenanceJobs = Get-DbaAgentJob -SqlInstance $server -Category "Database Maintenance"
    $AgentSchedules = Get-DbaAgentSchedule -SqlInstance $server

    Log "Display maintenance jobs scheduling"
    Log "'_DBA' Agent jobs call Ola Hallengren maintenance jobs in a relative smart order"

    $JoinedData = @()
    foreach ($MaintenanceJob in $MaintenanceJobs) {
        $AgentSchedule = $AgentSchedules | Where-Object {$_.ScheduleName -eq $MaintenanceJob.JobSchedules[0]}
        $obj = New-Object -TypeName PSObject -Property @{
            JobName = $MaintenanceJob.Name
            JobCategory = $MaintenanceJob.Category
            NextRunDate = $MaintenanceJob.NextRunDate
            ScheduleName = $AgentSchedule.ScheduleName
            FrequencyTypes = $AgentSchedule.FrequencyTypes
            Description = $AgentSchedule.Description
        }
        $JoinedData += $obj
    }
    $JoinedData | Select-object JobName,NextRunDate,Description | Format-Table -AutoSize

    if ($Server.HostPlatform -eq "Windows") {

        Log "Checking Kerberos configuration"
        $tSQL = "select @@SERVERNAME AS ServerName,client_net_address,client_tcp_port,local_net_address,local_tcp_port
                    ,net_transport,auth_scheme,es.nt_domain,es.nt_user_name
                from sys.dm_exec_connections ec
                inner join sys.dm_exec_sessions es on es.session_id = ec.session_id
                where ec.session_id = @@spid"
        $result = Invoke-DbaQuery -SqlInstance $Server -Query $tSQL

        if ($result.auth_scheme -eq "NTLM") {

            Log "NTLM detected, generating SPNs Registration"
            try {
                Write-Host
                $TCPPort = Get-DbaTcpPort -SqlInstance $Server
                $NetworkName = Resolve-DbaNetworkName -ComputerName $($server.ComputerName) -Turbo
                $ServiceAccount = $Server.ServiceAccount
                if ($ServiceAccount -match "NT Service") {
                    $ServiceAccount = "$($result.nt_domain)`\$($server.ComputerName)`$"
                }
                if ($server.ServiceName -eq "MSSQLSERVER") {
                    Write-Host "SetSPN -s ""MSSQLSvc/$($NetworkName.ComputerName):$($TCPPort.Port)"" ""$ServiceAccount"""
                    Write-Host "SetSPN -s ""MSSQLSvc/$($NetworkName.DNSHostEntry):$($TCPPort.Port)"" ""$ServiceAccount"""
                } else {
                    Write-Host "SetSPN -s ""MSSQLSvc/$($NetworkName.ComputerName):$($TCPPort.Port)"" ""$ServiceAccount"""
                    Write-Host "SetSPN -s ""MSSQLSvc/$($NetworkName.ComputerName):$($server.ServiceName)"" ""$ServiceAccount"""
                    Write-Host "SetSPN -s ""MSSQLSvc/$($NetworkName.DNSHostEntry):$($TCPPort.Port)"" ""$ServiceAccount"""
                    Write-Host "SetSPN -s ""MSSQLSvc/$($NetworkName.DNSHostEntry):$($server.ServiceName)"" ""$ServiceAccount"""
                }
            } catch {
            "An error occurred on $($_.ServerName) "
            }
            Write-Host
        }
    }

    
    Log "ConnectionString " 
    Write-Host 
    Write-Host  $($Server | New-DbaConnectionString)
    Write-Host 
    
#endregion


Log "End"

<#

    Start-DbaAgentJob -SqlInstance $Server -Job "_DBA - HouseKeeping"
    Start-DbaAgentJob -SqlInstance $Server -Job "_DBA - USER_DATABASES - FULL"

#>


<#

    #region Cleanup

        $Server = Connect-DbaInstance -SqlInstance $InstanceName
        #$cred = Get-Credential
        #$Server = Connect-DbaInstance -SqlInstance $InstanceName -SqlCredential $cred

        # Remove Jobs
        Get-DbaAgentJob -SqlInstance $Server -Category "Database Maintenance" `
                        | Where-Object {$_.Name -ne "syspolicy_purge_history"} `
                        | Remove-DbaAgentJob -Confirm:$false | Out-Null
        Get-DbaAgentJob -SqlInstance $Server -Category "Monitoring" | Remove-DbaAgentJob -Confirm:$false | Out-Null

        # Remove _DBA Database
        Remove-DbaDatabase -SqlInstance $Server -Database $dbaDatabase -Confirm:$false | Out-Null

        # Remove xEvents
        Remove-DbaXESession -SqlInstance $Server  -Confirm:$false `
                            -Session AuditLoginSA,PerformanceIssues,TempDBAutogrowth,UserDBLogAutogrowth | Out-Null

        # Remove Audits
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query "ALTER SERVER AUDIT SPECIFICATION [AuditSpecification-DDL] WITH (STATE = OFF)" | Out-Null
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query "ALTER SERVER AUDIT [Audit-DDL] WITH (STATE = OFF)" | Out-Null
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query "DROP SERVER AUDIT SPECIFICATION [AuditSpecification-DDL]"  | Out-Null
        Invoke-DbaQuery -SqlInstance $Server -Database master -Query "DROP SERVER AUDIT [Audit-DDL]"  | Out-Null

        Invoke-DbaQuery -SqlInstance $Server -Database "master" -Query "
            ALTER EVENT SESSION [system_health] ON SERVER
            ADD EVENT sqlserver.security_error_ring_buffer_recorded;
        " | Out-Null

    #endregion

#>


