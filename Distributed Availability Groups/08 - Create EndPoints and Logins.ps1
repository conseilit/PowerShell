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

# create the endpoints on SQL Server for DBM and AG
$endpoint = New-SqlHadrEndpoint MirroringEndpoint -Port 5022 -Path SQLSERVER:\SQL\DC1-SQL1\DEFAULT
Set-SqlHadrEndpoint -InputObject $endpoint -State "Started"

$endpoint = New-SqlHadrEndpoint MirroringEndpoint -Port 5022 -Path SQLSERVER:\SQL\DC1-SQL2\DEFAULT
Set-SqlHadrEndpoint -InputObject $endpoint -State "Started" 

$endpoint = New-SqlHadrEndpoint MirroringEndpoint -Port 5022 -Path SQLSERVER:\SQL\DC2-SQL3\DEFAULT
Set-SqlHadrEndpoint -InputObject $endpoint -State "Started"

$endpoint = New-SqlHadrEndpoint MirroringEndpoint -Port 5022 -Path SQLSERVER:\SQL\DC2-SQL4\DEFAULT
Set-SqlHadrEndpoint -InputObject $endpoint -State "Started" 



# create the login and grant the service account on the endpoints
$tSQL = "CREATE LOGIN [demo\DC1-SQL1$] FROM WINDOWS;"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

$tSQL = "CREATE LOGIN [demo\DC1-SQL2$] FROM WINDOWS;"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

$tSQL = "CREATE LOGIN [demo\DC2-SQL3$] FROM WINDOWS;"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

$tSQL = "CREATE LOGIN [demo\DC2-SQL4$] FROM WINDOWS;"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"


$tSQL = "GRANT CONNECT ON ENDPOINT::[MirroringEndpoint] TO [demo\DC1-SQL1$];"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

$tSQL = "GRANT CONNECT ON ENDPOINT::[MirroringEndpoint] TO [demo\DC1-SQL2$];"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

$tSQL = "GRANT CONNECT ON ENDPOINT::[MirroringEndpoint] TO [demo\DC2-SQL3$];"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"

$tSQL = "GRANT CONNECT ON ENDPOINT::[MirroringEndpoint] TO [demo\DC2-SQL4$];"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL1"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC1-SQL2"
Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL3"
#Invoke-SqlCmd -Query $tSQL -Serverinstance "DC2-SQL4"






