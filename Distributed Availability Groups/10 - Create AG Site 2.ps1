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

# AG on site 2
$tSQL = "
CREATE AVAILABILITY GROUP [DC2-AG]
FOR REPLICA ON 
'DC2-SQL3' 
    WITH (   ENDPOINT_URL = 'TCP://DC2-SQL3.demo.local:5022', 
             AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, 
             FAILOVER_MODE = AUTOMATIC,
             SEEDING_MODE = AUTOMATIC  ),
'DC2-SQL4' 
    WITH (   ENDPOINT_URL = 'TCP://DC2-SQL4.demo.local:5022', 
             AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, 
             FAILOVER_MODE = AUTOMATIC,
             SEEDING_MODE = AUTOMATIC )
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"

# grant the AG to create a database
$tSQL = "ALTER AVAILABILITY GROUP [DC2-AG] GRANT CREATE ANY DATABASE"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"


# join the seconday node and also grant create database
$tSQL = "
ALTER AVAILABILITY GROUP [DC2-AG] JOIN
ALTER AVAILABILITY GROUP [DC2-AG] GRANT CREATE ANY DATABASE
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

New-SqlAvailabilityGroupListener -Name "DC2-AG-VIP" -StaticIp "10.0.2.30/255.0.0.0" -Path "SQLSERVER:\Sql\DC2-SQL3\DEFAULT\AvailabilityGroups\DC2-AG"


