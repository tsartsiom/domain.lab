# Настройка dc2

## Базовые настройки после установки операционной системы

Установка сетевых параметров, имени компьютера

```powershell
Rename-Computer DC2
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.69.2 -PrefixLength 24 -DefaultGateway 192.168.69.254
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 192.168.69.1
New-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\" -Name "DisabledComponents" -Value 0xffffffff -PropertyType "DWord"
# GLVK ключ для Windows Server 2022 Standard
slmgr.vbs -ipk VDYBN-27WPP-V4HQT-9VMD4-VMK7H
# GLVK ключ для Windows Server 2022 Datacenter
#slmgr.vbs -ipk WX4NM-KYWYW-QJJR4-XV3QB-6VM33
Restart-Computer -Confirm
```
## Настройка AD

#### Установка компонентов AD и автоматическая перезагрузка

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools
$cred = Get-Credential "DOMAIN\Администратор"
Install-ADDSDomainController -InstallDns -DomainName "domain.lab" -Credential $cred
```
#### Настройка DNS, установка и настройка DHCP

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses ("127.0.0.1","192.168.69.1")
# DCHP Failover
Install-WindowsFeature -Name DHCP -IncludeManagementTools
netsh dhcp add securitygroups
Restart-Service DHCPServer
Add-DhcpServerInDC "dc2.domain.lab" 192.168.69.2
Set-ItemProperty -Path "registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2
Add-DhcpServerv4Failover -ComputerName "dc1.domain.lab" -Name "DC1-DC2-Failover" -PartnerServer "dc2.domain.lab" -ScopeId 192.168.69.0 -SharedSecret "DHCP_secret" -Force
```
