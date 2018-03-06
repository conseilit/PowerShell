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

# DC1
Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\DC1-SQL1\DEFAULT -Force
Restart-Service -InputObject $(Get-Service -Computer DC1-SQL1 -Name "MSSQLSERVER") -Force

Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\DC1-SQL2\DEFAULT -Force
Restart-Service -InputObject $(Get-Service -Computer DC1-SQL2 -Name "MSSQLSERVER") -force

# DC2
Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\DC2-SQL3\DEFAULT -Force
Restart-Service -InputObject $(Get-Service -Computer DC2-SQL3 -Name "MSSQLSERVER") -Force

Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\DC2-SQL4\DEFAULT -Force
Restart-Service -InputObject $(Get-Service -Computer DC2-SQL4 -Name "MSSQLSERVER") -force


