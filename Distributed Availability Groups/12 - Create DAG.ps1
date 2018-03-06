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

# Create DAG
$tSQL = "
CREATE AVAILABILITY GROUP [distributedag]  
   WITH (DISTRIBUTED)   
   AVAILABILITY GROUP ON  
      'DC1-AG' WITH    
      (   
         LISTENER_URL = 'tcp://DC1-AG-VIP.demo.local:5022',    
         AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,   
         FAILOVER_MODE = MANUAL,   
         SEEDING_MODE = AUTOMATIC   
      ),   
      'DC2-AG' WITH    
      (   
         LISTENER_URL = 'tcp://DC2-AG-VIP.demo.local:5022',   
         AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,   
         FAILOVER_MODE = MANUAL,   
         SEEDING_MODE = AUTOMATIC   
      );    
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"



# wait for total synchronisation
$tSQL = "
SELECT   ar.replica_server_name
       , ag.name as availabilitygroup_name
       , ag.is_distributed
       , DB_NAME(drs.database_id) As database_name
       --, drs.group_id
       --, drs.replica_id
       , drs.is_primary_replica
       , drs.synchronization_state_desc
       , drs.synchronization_health_desc
       , drs.log_send_queue_size
       , drs.redo_queue_size
       , drs.end_of_log_lsn 
       , drs.last_sent_lsn
       , drs.last_received_lsn
       , drs.last_hardened_lsn
       , drs.last_redone_lsn
       , drs.secondary_lag_seconds
FROM sys.dm_hadr_database_replica_states drs 
INNER JOIN sys.availability_groups ag ON drs.group_id = ag.group_id
inner join sys.availability_replicas ar on ar.replica_id = drs.replica_id

"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1" | Out-GridView

#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"



# Join DAG
$tSQL = "
ALTER AVAILABILITY GROUP [distributedag]   
   JOIN   
   AVAILABILITY GROUP ON  
      'DC1-AG' WITH    
      (   
         LISTENER_URL = 'tcp://DC1-AG-VIP.demo.local:5022',    
         AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,   
         FAILOVER_MODE = MANUAL,   
         SEEDING_MODE = AUTOMATIC   
      ),   
      'DC2-AG' WITH    
      (   
         LISTENER_URL = 'tcp://DC2-AG-VIP.demo.local:5022',   
         AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,   
         FAILOVER_MODE = MANUAL,   
         SEEDING_MODE = AUTOMATIC   
      );    
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"


<#
$tSQL = "
DROP AVAILABILITY GROUP [distributedag]  
   ;    
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"



#>
