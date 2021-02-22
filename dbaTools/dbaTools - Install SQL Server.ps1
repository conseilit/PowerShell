# SQL Server restore scripts based on dbaTools commands
# Thanks to Chrissy LeMaire (@cl | https://blog.netnerds.net/ )
#          , Row Sewell (@SQLDBAWithBeard | https://sqldbawithabeard.com/)
#          , and all SQL Server community members
# http://dbatools.io

# Source reporsitory configuration
Set-DbatoolsConfig -Name Path.SQLServerSetup -Value '\\rebond\sources'

# my super secure sa password for demos
$Username = 'sa'
$Password = 'Password1!'
$pass = ConvertTo-SecureString -AsPlainText $Password -Force
$saCred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username,$pass

# the credential used to install SQL Server on the remote computers
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$InstallCred = Get-Credential -Message "Enter current user and password to connect remote computer" -UserName $CurrentUser

# some configuration stuffs
$config = @{
    AGTSVCSTARTUPTYPE = "Automatic"
    SQLCOLLATION = "Latin1_General_CI_AS"
    BROWSERSVCSTARTUPTYPE = "Manual"
    FILESTREAMLEVEL = 1
    INSTALLSQLDATADIR="G:" 
    SQLBACKUPDIR="G:\MSSQL15.MSSQLSERVER\Backup" 
    SQLUSERDBDIR="G:\MSSQL15.MSSQLSERVER\MSSQL\Data" 
    SQLUSERDBLOGDIR="H:\MSSQL15.MSSQLSERVER\Log" 
    SQLTEMPDBDIR="T:\MSSQL15.MSSQLSERVER\Data" 
    SQLTEMPDBLOGDIR="U:\MSSQL15.MSSQLSERVER\Log" 
}

# Perform the installation
Install-DbaInstance -SqlInstance SQL15AG1,SQL15AG2 `
                    -Credential $InstallCred `
                    -Version 2019 `
                    -Feature Engine,Replication,FullText,IntegrationServices `
                    -AuthenticationMode Mixed `
                    -AdminAccount $CurrentUser `
                    -SaCredential $saCred `
                    -PerformVolumeMaintenanceTasks `
                    -SaveConfiguration C:\InstallScripts `
                    -Configuration $config `
                    -Confirm:$false


# Connect using Windows authentication
$Servers = Connect-DbaInstance -SqlInstance SQL15AG1,SQL15AG2
$Servers | Select-Object DomainInstanceName,VersionMajor,Edition


# Connect using SQL authentication
$Servers = Connect-DbaInstance -SqlInstance SQL15AG1,SQL15AG2 -SqlCredential $saCred
$Servers | get-dbaDatabase | format-table -autosize
