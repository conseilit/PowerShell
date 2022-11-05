# SQL Server configuration Script based on dbaTools commands
# Thanks to Chrissy LeMaire (@cl | https://blog.netnerds.net/ )
#          , Rob Sewell (@SQLDBAWithBeard | https://sqldbawithabeard.com/)
#          , and all SQL Server community members
# http://dbatools.io


Clear-Host

$SQL1 = "FROGSQL1"
$SQL2 = "FROGSQL2"
$CNO = "WSFCFrog"
$FSW = "\\Formation\FSW"
$ADGroup = "ServeursSQL"
$Domain = "ConseilIT"
$AGName = "DataFrogsAG"
$Database = "Kermit"

#region WSFC

    Install-WindowsFeature -Name Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools -ComputerName $SQL1
    Install-WindowsFeature -Name Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools -ComputerName $SQL2

    Test-Cluster -Node $SQL1,$SQL2  -Ignore "Storage"
    New-Cluster -Name $CNO -Node $SQL1,$SQL2 -NoStorage

#endregion

#region Quorum
    <#
        # Fileshare on Formation computer
        New-Item -type directory -path "E:\FSW"
        New-SMBShare –Name “FSW” –Path "E:\FSW" –FullAccess "CONSEILIT\Domain Admins","CONSEILIT\ServeursSQL"
    #>

    # Check FSW folder share
    Get-SmbShare -Name "FSW" | Format-Table -AutoSize
    Get-SmbShareAccess -Name "FSW"  | Format-Table -AutoSize

    # Add the CNO to the 
    Get-ADGroupMember -Identity $ADGroup
    Add-ADGroupMember -Identity $ADGroup -Members "$($CNO)`$"
    Get-ADGroupMember -Identity $ADGroup

    # Adjust Quorum settings to use the FSW
    Get-Cluster -Name $CNO | Set-ClusterQuorum -FileShareWitness $FSW
#endregion

#region Cluster Settings

    Get-Cluster -Name $CNO | Format-List *subnet*

    # adjust cluster settings if necessary
    (Get-Cluster -Name $CNO).SameSubnetThreshold = 20 
    (Get-Cluster -Name $CNO).CrossSubnetThreshold = 20 
    (Get-Cluster -Name $CNO).RouteHistoryLength = 40 

    #(Get-Cluster -Name $CNO).SameSubnetDelay=2000

    (Get-Cluster -Name $CNO).ClusterLogSize
    Set-ClusterLog -Cluster $CNO -Size 2000
    (Get-Cluster -Name $CNO).ClusterLogSize

#endregion

#region Active Directory

    # create child objects pour le CNO 
    $ou = "AD:\" + (Get-ADObject -Filter 'Name -like "Computers"').DistinguishedName 
    $sid = (Get-ADComputer -Filter 'ObjectClass -eq "Computer"' | where-object name -eq "$CNO").SID
    $acl = get-acl -path $ou


    # $acl.access | Select-Object IdentityReference, ActiveDirectoryRights | Sort-Object –unique | Out-GridView  


    # Create a new access control entry to allow access to the OU
    $identity = [System.Security.Principal.IdentityReference] $sid
    $type = [System.Security.AccessControl.AccessControlType] "Allow"
    $inheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance] "All"
    $adRights = [System.DirectoryServices.ActiveDirectoryRights] "CreateChild"
    $ace1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule $identity,$adRights,$type,$inheritanceType
    $adRights = [System.DirectoryServices.ActiveDirectoryRights] "GenericRead"
    $ace2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule $identity,$adRights,$type,$inheritanceType


    # Add the ACE in the ACL and set the ACL on the object 
    $acl.AddAccessRule($ace1)
    $acl.AddAccessRule($ace2)
    set-acl -aclobject $acl $ou
#endregion

#region Enable HADRON

    Enable-DbaAgHadr -SqlInstance $SQL1,$SQL2 -Force

#endregion

#region Create Endpoints

    # Mirroring endpoint creation
    $ep = New-DbaEndpoint -SqlInstance $SQL1,$SQL2 -Name hadr_endpoint -Type DatabaseMirroring -Port 5022
    $ep | Start-DbaEndpoint

    # granting SQL Server service account on opposite endpoint
    New-DbaLogin -SqlInstance $SQL1 -Login "$Domain`\$SQL2`$" 
    Grant-DbaAgPermission -SqlInstance $SQL1 -Login "$Domain`\$SQL2`$"  -Type Endpoint -Permission Connect
    New-DbaLogin -SqlInstance $SQL2 -Login "$Domain`\$SQL1`$"
    Grant-DbaAgPermission -SqlInstance $SQL2 -Login "$Domain`\$SQL1`$" -Type Endpoint -Permission Connect

#endregion

#region create AG

    New-DbaAvailabilityGroup -Name $AGName `
                            -Primary $SQL1 -Secondary $SQL2 `
                            -FailoverMode Automatic -SeedingMode Automatic -AutomatedBackupPreference Primary  `
                            -EndpointUrl "TCP://$SQL1`.$Domain`.local:5022", "TCP://$SQL2`.$Domain`.local:5022" `
                            -confirm:$false

#endregion

#region Create Listener

    Add-DbaAgListener -SqlInstance $SQL1 -AvailabilityGroup $AGName -Dhcp -Port 1433

#endregion

#region Create Routing List
    
    $tSQL = "
        ALTER AVAILABILITY GROUP [$AGName]
        MODIFY REPLICA ON N'$SQL1' 
        WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY));

        ALTER AVAILABILITY GROUP [$AGName]
        MODIFY REPLICA ON N'$SQL1' 
        WITH (SECONDARY_ROLE (READ_ONLY_ROUTING_URL = N'TCP://$SQL1`.$Domain`.local:1433'));

        ALTER AVAILABILITY GROUP [$AGName]
        MODIFY REPLICA ON N'$SQL2' 
        WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY));

        ALTER AVAILABILITY GROUP [$AGName]
        MODIFY REPLICA ON N'$SQL2' 
        WITH (SECONDARY_ROLE (READ_ONLY_ROUTING_URL = N'TCP://$SQL1`.$Domain`.local:1433'));

        ALTER AVAILABILITY GROUP [$AGName] 
        MODIFY REPLICA ON N'$SQL1'
        WITH (PRIMARY_ROLE (READ_ONLY_ROUTING_LIST=('$SQL2','$SQL1')));

        ALTER AVAILABILITY GROUP [$AGName] 
        MODIFY REPLICA ON N'$SQL2' 
        WITH (PRIMARY_ROLE (READ_ONLY_ROUTING_LIST=('$SQL1','$SQL2')));
    "
    Invoke-SqlCmd -Query $tSQL -Serverinstance "$SQL1" 

#endregion

#region Add database to AG

    # sample database creation
    New-DbaDatabase -SqlInstance $SQL1 -Name $Database | Out-Null

    # automatic seeding still requires full database backup
    Backup-DbaDatabase  -SqlInstance $SQL1 -Database $Database
           
    # adding the databsae to the AG
    Add-DbaAgDatabase -SqlInstance $SQL1 -AvailabilityGroup $AGName -Database $Database -SeedingMode Automatic

#endregion

