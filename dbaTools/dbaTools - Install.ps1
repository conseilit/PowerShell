# SQL Server restore scripts based on dbaTools commands
# Thanks to Chrissy LeMaire (@cl | https://blog.netnerds.net/ )
#          , Row Sewell (@SQLDBAWithBeard | https://sqldbawithabeard.com/)
#          , and all SQL Server community members
# http://dbatools.io

Set-ExecutionPolicy Unrestricted

# Simplest way to install
Install-Module dbatools 

# Manual installation
Invoke-WebRequest "https://github.com/sqlcollaborative/dbatools/archive/master.zip" -OutFile "C:\sources\dbatools.zip"
Expand-Archive -Path "C:\sources\dbatools.zip" -DestinationPath "C:\Program Files\WindowsPowerShell\Modules"
Rename-Item "C:\Program Files\WindowsPowerShell\Modules\dbatools-master"  "C:\Program Files\WindowsPowerShell\Modules\dbatools" 
Get-ChildItem -Recurse "C:\Program Files\WindowsPowerShell\Modules\dbatools" | Unblock-File 
import-module dbatools


# check everything is fine
$Server = Connect-DbaInstance -SqlInstance SQL2019
$Server | Select-Object DomainInstanceName,VersionMajor,DatabaseEngineEdition



<#
    # issue when updating dbatools : TLS support
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#>

