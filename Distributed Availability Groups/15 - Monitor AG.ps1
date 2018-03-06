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

$Listener_AG1 = "DC2-AG-VIP"
$Listener_AG2 = "DC1-AG-VIP"

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
$ServerSite1 = New-Object -TypeName  Microsoft.SQLServer.Management.Smo.Server($Listener_AG1)
$ServerSite2 = New-Object -TypeName  Microsoft.SQLServer.Management.Smo.Server($Listener_AG2)

cls

# recherche du réplica principal (un AG) du DAG
$PrimaryReplicaDAG = $ServerSite1.AvailabilityGroups | where-object IsDistributedAvailabilityGroup -eq $true | where-object LocalReplicaRole -EQ "Primary" | select Name,LocalReplicaRole,IsDistributedAvailabilityGroup,PrimaryReplicaServerName
if (!($PrimaryReplicaDAG)) {
    $PrimaryReplicaDAG = $ServerSite2.AvailabilityGroups | where-object IsDistributedAvailabilityGroup -eq $true | where-object LocalReplicaRole -EQ "Primary" | select Name,LocalReplicaRole,IsDistributedAvailabilityGroup,PrimaryReplicaServerName
}
#$PrimaryReplicaDAG
write-host "DAG Name : "$PrimaryReplicaDAG.Name
Write-Host "         |->  " $PrimaryReplicaDAG.PrimaryReplicaServerName " ("$PrimaryReplicaDAG.LocalReplicaRole")"




    # recherche réplica secondaire de l'AG du réplica primaire du DAG
    $ServerSite1.AvailabilityGroups | where-object IsDistributedAvailabilityGroup -eq $false | ForEach-Object {
        if ($_.Name -eq $PrimaryReplicaDAG.PrimaryReplicaServerName) {
            #$_.AvailabilityReplicas | select Name,Role
            $_.AvailabilityReplicas | ForEach-Object {
                 Write-Host "             |->  " $_.Name " ("$_.Role")"
            }
        }
    }
    $ServerSite2.AvailabilityGroups | where-object IsDistributedAvailabilityGroup -eq $false | ForEach-Object {
        if ($_.Name -eq $PrimaryReplicaDAG.PrimaryReplicaServerName) {
            $_.AvailabilityReplicas | ForEach-Object {
                 Write-Host "             |->  " $_.Name " ("$_.Role")"
            } 
        }
    }



# réplica secondaire du DAG
$SecondaryReplicaDAGList = $ServerSite1.AvailabilityGroups  | where-object IsDistributedAvailabilityGroup -eq $true | where-object LocalReplicaRole -EQ "Secondary" | select AvailabilityReplicas
if (!($SecondaryReplicaDAGList)) {
    $SecondaryReplicaDAGList = $ServerSite2.AvailabilityGroups | where-object IsDistributedAvailabilityGroup -eq $true | where-object LocalReplicaRole -EQ "Secondary" | select AvailabilityReplicas
}

$SecondaryReplicaDAGList.AvailabilityReplicas | ForEach-object  {
    if ($_.Role -eq "Secondary"  ) {
        #$_
        Write-Host "         |->  " $_.Name " ("$_.Role")"
        $SecondaryReplicaDAG = $_.Name
    }
}



    # recherche réplica secondaire de l'AG du réplica primaire du DAG
    $ServerSite1.AvailabilityGroups | where-object IsDistributedAvailabilityGroup -eq $false | ForEach-Object {
        if ($_.Name -eq $SecondaryReplicaDAG) {
            #$_.AvailabilityReplicas | select Name,Role
            $_.AvailabilityReplicas | ForEach-Object {
                 Write-Host "             |->  " $_.Name " ("$_.Role")"
            }
        }
    }
    $ServerSite2.AvailabilityGroups | where-object IsDistributedAvailabilityGroup -eq $false | ForEach-Object {
        if ($_.Name -eq $SecondaryReplicaDAG) {
            $_.AvailabilityReplicas | ForEach-Object {
                 Write-Host "             |->  " $_.Name " ("$_.Role")"
            } 
        }
    }






