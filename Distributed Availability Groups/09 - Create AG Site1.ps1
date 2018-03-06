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

# AG on site 1
$tSQL = "
CREATE AVAILABILITY GROUP [DC1-AG]
FOR REPLICA ON 
'DC1-SQL1' 
    WITH (   ENDPOINT_URL = 'TCP://DC1-SQL1.demo.local:5022', 
             AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, 
             FAILOVER_MODE = AUTOMATIC,
             SEEDING_MODE = AUTOMATIC  ),
'DC1-SQL2' 
    WITH (   ENDPOINT_URL = 'TCP://DC1-SQL2.demo.local:5022', 
             AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, 
             FAILOVER_MODE = AUTOMATIC,
             SEEDING_MODE = AUTOMATIC )
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"

# grant the AG to create a database
$tSQL = "ALTER AVAILABILITY GROUP [DC1-AG] GRANT CREATE ANY DATABASE"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"


# join the seconday node and also grant create database
$tSQL = "
ALTER AVAILABILITY GROUP [DC1-AG] JOIN
ALTER AVAILABILITY GROUP [DC1-AG] GRANT CREATE ANY DATABASE
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"

New-SqlAvailabilityGroupListener -Name "DC1-AG-VIP" -StaticIp "10.0.1.30/255.0.0.0" -Path "SQLSERVER:\Sql\DC1-SQL1\DEFAULT\AvailabilityGroups\DC1-AG"


