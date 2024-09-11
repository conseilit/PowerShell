  
# Set disks Online 
Get-Disk | Where-Object IsOffline –Eq $True | Set-Disk –IsOffline $False

# select all raw disks
$DiskList = Get-Disk | Where-Object partitionstyle -eq "raw"   

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
  # GPT, NTFS, 64KB, Disable 8.3, LargeFRS

  Get-Disk $CurrentDisk.Number | Initialize-Disk -PartitionStyle GPT
  $Part = Get-Disk $CurrentDisk.Number | new-Partition -UseMaximumSize -AssignDriveLetter 
  $Part | Format-volume  -FileSystem NTFS -AllocationUnitSize 65536 -ShortFileNameSupport:$false -Confirm:$false -NewFileSystemLabel $DiskLabel -UseLargeFRS | Out-Null

}

  

# for each drive, disable indexing
$DriveList = Get-WmiObject -Class Win32_Volume  | Where-Object Label -Like '*SQL*' 
ForEach ($CurrentDrive in $DriveList) 
{
  $indexing = $CurrentDrive.IndexingEnabled
  if ("$indexing" -eq $True)
  {
    $CurrentDrive | Set-WmiInstance -Arguments @{IndexingEnabled=$False} | Out-Null
  }

      # Create a text file to identify volume
      $filename = $CurrentDrive.Name + ($CurrentDrive.DriveLetter).Substring(0,1) + ".txt"
      New-Item $filename -type file -Force
      $CurrentDrive.Label | Set-Content $filename 

  }

Get-WmiObject -Class Win32_Volume | Select-Object Name,Label,IndexingEnabled,BlockSize,FileSystem | Where-Object Label -Like '*SQL*' | Format-Table -AutoSize
