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

$VmName   = "DC1-SQL2"
$Username = 'demo\Administrator'
$Password = 'Password1'
$SQLServerISO  = "C:\Sources\en_sql_server_2016_developer_with_service_pack_1_x64_dvd_9548071.iso"	

# attach iso to VM
Set-VMDvdDrive -VMName $VmName -Path $SQLServerISO

function SetupSQL() 
{ 
    

		$HostName = Hostname
		D:\Setup.exe /ACTION=Install /FEATURES=SQLEngine,Replication,IS,Conn,FullText  `
					/INSTANCENAME=MSSQLSERVER `
					/SQLSVCACCOUNT="NT Service\MSSQLServer" `
					/AGTSVCACCOUNT="NT Service\SQLServerAgent" `
					/FTSVCACCOUNT="NT Service\MSSQLFDLauncher" `
					/ISSVCACCOUNT="NT Service\MsDtsServer130" `
                    /AGTSVCSTARTUPTYPE="Automatic" `
					/TCPENABLED="1" `
                    /FILESTREAMLEVEL="3" `
                    /FILESTREAMSHARENAME="MSSQLSERVER" `
                    /INSTALLSQLDATADIR="E:" `
                    /SQLBACKUPDIR="E:\MSSQL\Backup" `
                    /SQLUSERDBDIR="E:\MSSQL\Data" `
                    /SQLUSERDBLOGDIR="E:\MSSQL\Log" `
					/SQLTEMPDBFILECOUNT=4  `
					/UpdateEnabled=FALSE `
					/SECURITYMODE=SQL /SAPWD="Password1" /SQLSYSADMINACCOUNTS="demo\Administrator" `
					/SQLUSERDBDIR="E:\MSSQLServer\Data" `
					/SQLUSERDBLOGDIR="E:\MSSQLServer\Log" `
					/SQLTEMPDBDIR="E:\MSSQLServer\Data" `
					/SQLTEMPDBLOGDIR="E:\MSSQLServer\Log" `
					/SQLTEMPDBFILESIZE=256 `
					/SQLTEMPDBFILEGROWTH=64 `
					/SQLTEMPDBLOGFILESIZE=256 `
					/SQLTEMPDBLOGFILEGROWTH=256 `
					/HELP="False" /INDICATEPROGRESS="False" /QUIET="True" /QUIETSIMPLE="False" `
					/X86="False" /ENU="True" /ERRORREPORTING="False" /SQMREPORTING="False" `
					/SQLSVCINSTANTFILEINIT=TRUE `
					/IACCEPTSQLSERVERLICENSETERMS 
	
	
}


function RestartComputer () 
{
    write-host "Rebooting computer now ..." -ForegroundColor Red
    Restart-Computer -Force
}


$FunctionDefs = "function SetupSQL { ${function:SetupSQL} }; function RestartComputer { ${function:RestartComputer}} "


$pass = ConvertTo-SecureString -AsPlainText $Password -Force
$Cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username,$pass



Invoke-Command -Credential $Cred -VMName $VmName { 

        . ([ScriptBlock]::Create($Using:FunctionDefs))

        SetupSQL 
        
        RestartComputer
}

