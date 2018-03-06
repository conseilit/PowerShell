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


$StartDate=(Get-Date)

# Variables
$VmName      = "DC1-SQL2"
$VmMemory    = 4GB				               
$VhdPath     = "D:\Hyper-V\Virtual Hard Disks"			       

$NetworkSwitch = "Public"	
$WindowsISO    = "C:\Sources\en_windows_server_2016_x64_dvd_9327751.iso"	

try
{
    
    # Create the Virtual Machine
    New-VM -Name $VmName  `
            -MemoryStartupBytes $VmMemory `
            -NewVHDPath $VhdPath\$VmName-OS.vhdx `
            –NewVHDSizeBytes 60000000000 `
            -SwitchName $NetworkSwitch `
            -Generation 2


    # Change VM Configuration
    Set-VMProcessor -VMName $VmName  -Count 4
    Add-VMDvdDrive  -VMName $VmName  -Path $WindowsISO
    Enable-VMIntegrationService -VMName $VmName  -Name "Guest Service Interface"
 
    Write-Host "Adding fixed size drives for best performance"

    # Add a specific controller for data drives
    # Add 4 data files
    Add-VMScsiController –VMName $VmName 
    Write-Host "Controller 1 added to $VmName "

    New-VHD  -Path $VhdPath"\$VmName-Data.vhdx" -SizeBytes 50GB
    Add-VMHardDiskDrive  -VMName $VmName  -Path $VhdPath"\$VmName-Data.vhdx" –ControllerType SCSI -ControllerNumber 1
    Write-Host "Disk $VhdPath\$VmName -Data.vhdx Added to $VmName  "

<#   

    # Add a specific controller for the log drive
    Add-VMScsiController –VMName $VmName 
    Write-Host "Controller 2 added to $VmName "

    New-VHD -Fixed -Path $VhdPath"\$VmName-Log.vhdx" -SizeBytes 8GB
    Add-VMHardDiskDrive  -VMName $VmName  -Path $VhdPath"\$VmName-Log.vhdx" –ControllerType SCSI -ControllerNumber 2
    Write-Host "Disk $VhdPath\$VmName -Log.vhdx Added to $VmName  "


    # Add a specific controller for TempDB drives
    Add-VMScsiController –VMName $VmName 
    Write-Host "Controller 3 added to $VmName "

    New-VHD -Fixed -Path $VhdPath"\$VmName-TempDBData.vhdx" -SizeBytes 2048MB
    Add-VMHardDiskDrive  -VMName $VmName  -Path $VhdPath"\$VmName-TempDBData.vhdx" –ControllerType SCSI -ControllerNumber 3
    Write-Host "Disk $VhdPath\$VmName -TempDBData.vhdx Added to $VmName  "

    New-VHD -Fixed -Path $VhdPath"\$VmName-TempDBLog.vhdx" -SizeBytes 2048MB
    Add-VMHardDiskDrive  -VMName $VmName  -Path $VhdPath"\$VmName-TempDBLog.vhdx" –ControllerType SCSI -ControllerNumber 3
    Write-Host "Disk $VhdPath\$VmName -TempDBLog.vhdx Added to $VmName  "
#>

    Write-Host "VM " $VmName  " created" 

    $gen2r2 = Get-VMFirmware $VmName
    $gen2r2.BootOrder 
    $genNet  = $gen2r2.BootOrder[1]
    $genHD   = $gen2r2.BootOrder[0]
    $genDVD  = $gen2r2.BootOrder[2] 


    Set-VMFirmware -VMName $VmName -BootOrder $genDVD ,$genHD,$genNet
    Get-VMFirmware $VmName 

     
    # strats the WM ... take care, press any key quickly to boot on DVD drive
    Start-VM -Name $VmName

    Write-Host "VM " $VmName  " started" 
}
catch [System.Net.WebException],[System.Exception]
{
    Write-Host "Error ..."
    Exit
}
finally
{
    $EndDate=(Get-Date)
    Write-Host "Elapsed time " ($EndDate - $StartDate).TotalMilliseconds " milliseconds"
}


Get-VM -Name $VmName | Select -ExpandProperty NetworkAdapters | Select VMName, IPAddresses, Status


$computer = hostname
vmconnect.exe $computer $VmName 



Get-VM -Name $VmName | Select -ExpandProperty NetworkAdapters | Select VMName, IPAddresses, Status

# get all VMs Ip addresses
#Get-VM | ?{$_.ReplicationMode -ne “Replica”} | Select -ExpandProperty NetworkAdapters | Select VMName, IPAddresses, Status

