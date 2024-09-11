
# disable open server manager at logon
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name DoNotOpenServerManagerAtLogon -Value 1
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\ServerManager' -Name CheckedUnattendLaunchSetting  -Value 0

# enable RDP
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
$SystemInfo = Get-WmiObject -Class Win32_ComputerSystem -EnableAllPrivileges
$SystemInfo.AutomaticManagedPageFile = $false
[Void]$SystemInfo.Put()  		

$DL = "C:"
$PageFile = Get-WmiObject -Class Win32_PageFileSetting -Filter "SettingID='pagefile.sys @ $DL'"


If($PageFile -ne $null)
{
  $PageFile.Delete()
}

Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{name="$DL\pagefile.sys"; InitialSize = 0; MaximumSize = 0} -EnableAllPrivileges | Out-Null
    
$PageFile = Get-WmiObject Win32_PageFileSetting -Filter "SettingID='pagefile.sys @ $DL'"
    
$PageFile.InitialSize = 4096
$PageFile.MaximumSize = 4096
[Void]$PageFile.Put()
			


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



# SMB TimeOut
# Prevent errors during backup like : The operating system returned the error '1359' 
# while attempting 'DiskChangeFileSize
$path = 'HKLM:\\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
try {
    $s = (Get-ItemProperty -ErrorAction stop -Name SessTimeout -Path $path).SessTimeout 
    if ($s -ne 65534) {
        Set-ItemProperty -Path $path -Name 'SessTimeout' -Value 65534  
    }
}


    catch {
        New-ItemProperty -Path $path -Name 'SessTimeout' -Value 65534 -PropertyType 'DWORD'
    }

