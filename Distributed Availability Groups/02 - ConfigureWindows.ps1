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

cls


$VmName   = "DC1-AD1"
$Username = 'Administrator'
$Password = 'Password1'

Enable-VMIntegrationService -Name 'Guest Service Interface' -VMName $VmName

#Copy-VMFile -Name $VmName -SourcePath 'C:\sources\SSMS-Setup-ENU.exe' -DestinationPath 'C:\sources\SSMS-Setup-ENU.exe' -FileSource Host -CreateFullPath
#Copy-VMFile -Name $VmName -SourcePath 'C:\sources\VSCodeSetup-1.7.1.exe' -DestinationPath 'C:\sources\VSCodeSetup-1.7.1.exe' -FileSource Host -CreateFullPath
    


function SetPowerPlan([string]$PreferredPlan) 
{ 
    Write-Host "Setting Powerplan to $PreferredPlan" 
    $guid = (Get-WmiObject -Class win32_powerplan -Namespace root\cimv2\power -Filter "ElementName='$PreferredPlan'").InstanceID.tostring() 
    $regex = [regex]"{(.*?)}$" 
    $newpowerVal = $regex.Match($guid).groups[1].value 

    powercfg -S  $newpowerVal 
}


function WindowsConfiguration ([string]$NewName) 
{

    # Setup things inside a VM
    $hostname = hostname
    write-host "Old machine name $hostname"

    # disable open server manager at logon
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name DoNotOpenServerManagerAtLogon -Value 1
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\ServerManager' -Name CheckedUnattendLaunchSetting  -Value 0
 
    # RDP
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
    
    # Firewall
    Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Enabled True
    New-NetFirewallRule -DisplayName "SQL Server default port 1433" -Direction Inbound  -Protocol TCP -LocalPort 1433 -Action Allow
    New-NetFirewallRule -DisplayName "SQL Server DAC port 1434"     -Direction Inbound  -Protocol TCP -LocalPort 1434 -Action Allow
    New-NetFirewallRule -DisplayName "SQL Server Browser UDP 1434"  -Direction Inbound  -Protocol UDP -LocalPort 1434 -Action Allow
    
    # Specific rules for AlwaysOn Availability Groups / DBM : TCP Port 5022
    New-NetFirewallRule -DisplayName "SQL Server AG 5022 IN"  -Direction Inbound   -Protocol TCP -LocalPort 5022 -Action Allow
    New-NetFirewallRule -DisplayName "SQL Server AG 5022 OUT" -Direction Outbound  -Protocol TCP -LocalPort 5022 -Action Allow

    #Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

    #configuring the page file size
  	
 
    # adjust for best performance
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    try {
        $s = (Get-ItemProperty -ErrorAction stop -Name visualfxsetting -Path $path).visualfxsetting 
        if ($s -ne 2) {
            Set-ItemProperty -Path $path -Name 'VisualFXSetting' -Value 2  
        }
    }
    catch {
        New-ItemProperty -Path $path -Name 'VisualFXSetting' -Value 2 -PropertyType 'DWORD'
    }

    # Disable IO priority ??
    # https://blogs.technet.microsoft.com/yongrhee/2015/04/22/storage-optimization-io-priorities-registry-key-idleprioritysupported/
    # 4D36E967-E325-11CE-BFC1-08002BE10318 : Hyper-V disk inside VM
    $path = 'HKLM:\\System\CurrentControlSet\Control\DeviceClasses\{4D36E967-E325-11CE-BFC1-08002BE10318}\DeviceParameters\Classpnp'
    try {
        $s = (Get-ItemProperty -ErrorAction stop -Name IdlePrioritySupported -Path $path).IdlePrioritySupported 
        if ($s -ne 0) {
            Set-ItemProperty -Path $path -Name 'IdlePrioritySupported' -Value 0  
        }
    }
    catch {
        New-ItemProperty -Path $path -Name 'IdlePrioritySupported' -Value 0 -PropertyType 'DWORD'
    }


    #This parameter controls the maximum port number that is used when a program requests any available user port from the system
    $path = 'HKLM:\\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    try {
        $s = (Get-ItemProperty -ErrorAction stop -Name MaxUserPort -Path $path).MaxUserPort 
        if ($s -ne 65534) {
            Set-ItemProperty -Path $path -Name 'MaxUserPort' -Value 65534  
        }
    }
    catch {
        New-ItemProperty -Path $path -Name 'MaxUserPort' -Value 65534 -PropertyType 'DWORD'
    }

  


    write-host "New machine name $NewName"
    Rename-Computer -NewName $NewName 

}


function FormatVolumes () 
{

		
	# Online disks
	Get-Disk | Where-Object IsOffline –Eq $True | Set-Disk –IsOffline $False

	# select all row disks
	$DiskList = Get-Disk | Where partitionstyle -eq "raw"   
	#| Where NumberOfPartitions -eq 0
	#| Where partitionstyle -eq "raw" 


	ForEach ($CurrentDisk in $DiskList)
	{
		
		switch ($CurrentDisk.Number) 
		{ 
			1 {$DiskLabel = "SQLData"} 
			2 {$DiskLabel = "SQLLog"} 
			3 {$DiskLabel = "SQLTempDBData"} 
			4 {$DiskLabel = "SQLTempDBLog"}
			default {"Not found"}
		}
			

		# formatting disk
		# GPT, NTFS, 64KB, Disable 8.3

		Get-Disk $CurrentDisk.Number | Initialize-Disk -PartitionStyle GPT
		$Part = Get-Disk $CurrentDisk.Number | new-Partition -UseMaximumSize -AssignDriveLetter 
		$Part | Format-volume  -FileSystem NTFS -AllocationUnitSize 65536 -ShortFileNameSupport:$false -Confirm:$false -NewFileSystemLabel $DiskLabel | Out-Null

	}

		

	# for each drive, disable indexing
	$DriveList = Get-WmiObject -Class Win32_Volume  | WHERE Label -Like '*SQL*' 
	ForEach ($CurrentDrive in $DriveList) 
	{
		$indexing = $CurrentDrive.IndexingEnabled
		if ("$indexing" -eq $True)
		{
			$CurrentDrive | Set-WmiInstance -Arguments @{IndexingEnabled=$False} | Out-Null
		}
	}

	Get-WmiObject -Class Win32_Volume | select Name,Label,IndexingEnabled,BlockSize,FileSystem | WHERE Label -Like '*SQL*' | ft -AutoSize

}


function RestartComputer () 
{
    write-host "Rebooting computer now ..."
    Restart-Computer -Force
}


function SetRDPPort([int] $port) {
 
    Write-host "Old RDP TCP Port " (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-TCP\").PortNumber
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-TCP\" -Name PortNumber -Value $port
    Write-host "New RDP TCP Port " (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-TCP\").PortNumber
     
    # create a rule for the new port
    New-NetFirewallRule -DisplayName "Custom RDP port $port" -Direction Inbound  -Protocol TCP -LocalPort $port -Action Allow -Profile Domain,Public,Private

    # disable all rules for the old one
    Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Enabled False
    
    # Restart the service to finalize the changes
    # Use -Force as it has dependant services
    Restart-Service -Name TermService -Force
}


$FunctionDefs = "function SetRDPPort { ${function:SetRDPPort} }; function WindowsConfiguration { ${function:WindowsConfiguration} }; function SetPowerPlan { ${function:SetPowerPlan} }; function FormatVolumes { ${function:FormatVolumes}}; function RestartComputer { ${function:RestartComputer}} "


$pass = ConvertTo-SecureString -AsPlainText $Password -Force
$Cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username,$pass



Invoke-Command -Credential $Cred -VMName $VmName { 

        . ([ScriptBlock]::Create($Using:FunctionDefs))

        
        SetPowerPlan "High performance"
        
        FormatVolumes

        WindowsConfiguration $Using:VmName

        #Set-RDPPort 31620
		
        #RestartComputer

}






# https://blogs.msdn.microsoft.com/virtual_pc_guy/2016/09/16/scaling-out-powershell-with-powershell-direct/
# https://msdn.microsoft.com/powershell/gallery/readme
# https://www.powershellgallery.com/packages/xSQLServer/1.8.0.0

