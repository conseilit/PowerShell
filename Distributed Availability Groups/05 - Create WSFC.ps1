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

Install-WindowsFeature -Name Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools -ComputerName DC1-SQL1
Install-WindowsFeature -Name Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools -ComputerName DC1-SQL2
Install-WindowsFeature -Name Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools -ComputerName DC2-SQL3
Install-WindowsFeature -Name Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools -ComputerName DC2-SQL4


Test-Cluster -Node DC1-SQL1,DC1-SQL2

New-Cluster -Name DC1-WSFC -Node DC1-SQL1,DC1-SQL2 -NoStorage -StaticAddress 10.0.1.20



# droits sur le share
Get-Cluster  | Set-ClusterQuorum -FileShareWitness "\\DC1-AD1\FSW" 


Test-Cluster -Node DC2-SQL3,DC2-SQL4

New-Cluster -Name DC2-WSFC -Node DC2-SQL3,DC2-SQL4 -NoStorage -StaticAddress 10.0.2.20



# droits sur le share
Get-Cluster  | Set-ClusterQuorum -FileShareWitness "\\DC2-AD2\FSW" 


# create child objects