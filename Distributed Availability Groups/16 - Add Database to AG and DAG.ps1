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
$Database = "DemoDB05"
$tSQL = "
CREATE DATABASE [$Database];
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"


# Dummy backup not enough
# because we need to manually deploy the database to secondary site
$tSQL = "
BACKUP DATABASE [$Database] TO DISK = '$Database.bak' WITH INIT,FORMAT;
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"

$tSQL = "
BACKUP LOG [$Database] TO DISK = '$Database.trn' WITH INIT,FORMAT;
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"



$tSQL = "
ALTER AVAILABILITY GROUP [DC1-AG]
ADD DATABASE [$Database];
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"






Copy-Item E:\MSSQL\Backup\$Database.bak  \\DC2-SQL3\E$\MSSQL\Backup\$Database.bak 
Copy-Item E:\MSSQL\Backup\$Database.trn  \\DC2-SQL3\E$\MSSQL\Backup\$Database.trn 
Copy-Item E:\MSSQL\Backup\$Database.bak  \\DC2-SQL4\E$\MSSQL\Backup\$Database.bak 
Copy-Item E:\MSSQL\Backup\$Database.trn  \\DC2-SQL4\E$\MSSQL\Backup\$Database.trn


$tSQL = "
RESTORE DATABASE [$Database] FROM DISK = '$Database.bak' WITH NORECOVERY;
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

$tSQL = "
RESTORE LOG [$Database] FROM DISK = '$Database.trn' WITH NORECOVERY;
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"



#$tSQL = "
#ALTER AVAILABILITY GROUP [distributedag]
#ADD DATABASE [$Database];
#"
#Write-Host $tSQL 
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"


$tSQL = "
ALTER DATABASE [$Database] SET HADR AVAILABILITY GROUP = [distributedag];
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"


$tSQL = "
ALTER DATABASE [$Database] SET HADR AVAILABILITY GROUP = [DC2-AG];
"
Write-Host $tSQL 
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

