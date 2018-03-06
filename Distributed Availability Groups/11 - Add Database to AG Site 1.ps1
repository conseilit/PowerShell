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

# add a database into the AG to verify all is working fine
$Database = "DemoDB01"
$tSQL = "
CREATE DATABASE [$Database];
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"


# Dummy backup to fake the controls for addinf a DB into an AG
# Do not run on a production environment
$tSQL = "
BACKUP DATABASE [$Database] TO DISK = 'NUL';
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"


$tSQL = "
ALTER AVAILABILITY GROUP [DC1-AG]
ADD DATABASE [$Database];
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"


