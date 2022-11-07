# Настройка dc1

## Базовые настройки после установки операционной системы

Установка сетевых параметров, имени компьютера

```powershell
Rename-Computer DC1
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.69.1 -PrefixLength 24 -DefaultGateway 192.168.69.254
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 127.0.0.1
New-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\" -Name "DisabledComponents" -Value 0xffffffff -PropertyType "DWord"
slmgr.vbs -ipk VDYBN-27WPP-V4HQT-9VMD4-VMK7H
Restart-Computer
```
## Настройка AD

#### Установка компонентов AD и автоматическая перезагрузка

```powershell
$password = "Password1234@!" | ConvertTo-SecureString -AsPlainText -Force
Install-WindowsFeature -Name AD-Domain-Services,RSAT-ADCS-Mgmt -IncludeAllSubFeature -IncludeManagementTools
Install-ADDSForest -DomainName "domain.lab" -InstallDns -SafeModeAdministratorPassword $password -Force
```

#### Настройка DNS, установка и настройка DHCP

```powershell
# DNS reverse lookup zone
Add-DnsServerPrimaryZone -NetworkID "192.168.69.0/24" -ReplicationScope Forest
# DHCP
Install-WindowsFeature -Name DHCP -IncludeManagementTools
netsh dhcp add securitygroups
Restart-Service DHCPServer
Add-DhcpServerInDC "dc1.domain.lab" 192.168.69.1
Set-ItemProperty -Path "registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2
Add-DhcpServerv4Scope -Name "domain.lab" -StartRange 192.168.69.31 -EndRange 192.168.69.249 -SubnetMask 255.255.255.0 -Description "domain.lab" -State "Active"
Set-DhcpServerv4OptionValue -ScopeId 192.168.69.0 -DnsDomain "domain.lab" -Router 192.168.69.254 -DnsServer 192.168.69.1
```
#### Создание OU в AD

```powershell
# OU
New-ADOrganizationalUnit -Name "Domain Users" -Path "DC=domain,DC=lab"
New-ADOrganizationalUnit -Name "Domain Computers" -Path "DC=domain,DC=lab"
New-ADOrganizationalUnit -Name "Domain Servers" -Path "DC=domain,DC=lab"
# перенаправление новых компов в OU Domain Computers
redircmp "OU=Domain Computers,DC=domain,DC=lab"
```
#### Копируем папку `GPO` на `dc1` и настраиваем групповые политики

```powershell
$gpoDir = "C:\GPO"
$domain = "domain.lab"
$sysvol = "C:\Windows\SYSVOL\sysvol\$domain"
Copy-Item "$gpoDir\PolicyDefinitions" -Destination "$sysvol\Policies\" -Recurse
Copy-Item "$gpoDir\PSModules\*" -Destination "C:\Program Files\WindowsPowerShell\Modules" -Recurse -Force
# WMI фильтры
Import-Module -Name GPWmiFilter
New-GPWmiFilter -Name 'Only x64 OS' -Expression 'SELECT * FROM Win32_OperatingSystem WHERE OSArchitecture LIKE "64%"'
New-GPWmiFilter -Name 'Only x86 OS' -Expression 'SELECT * FROM Win32_OperatingSystem WHERE NOT OSArchitecture LIKE "64%"'
New-GPWmiFilter -Name 'Windows 7-8 and Servers 2008-2012' -Expression 'SELECT * FROM Win32_OperatingSystem WHERE Version LIKE "6.1%" OR Version LIKE "6.2%"'
New-GPWmiFilter -Name 'Windows 7-10 ' -Expression 'SELECT * FROM Win32_OperatingSystem WHERE (Version LIKE "10.0%" OR Version LIKE "6.3%" OR Version LIKE "6.2%" OR Version LIKE "6.1%") AND ProductType = 1'
# MSFT GPOs
Import-GPO -BackupId "{DD304A7D-15A7-42B7-AB52-2338F4ECE2C7}" -Path "$gpoDir\MSFT" -TargetName "MSFT Windows 10 21H2 - Computer" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{4B6589C2-0290-4764-8058-9825B56B4169}" -Path "$gpoDir\MSFT" -TargetName "MSFT Windows 10 21H2 - User" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{E2B8214C-729F-4324-A876-F067E58B740B}" -Path "$gpoDir\MSFT" -TargetName "MSFT Windows Server 2022 - Domain Controller" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{AAC7C960-51D3-4BEE-89BD-7FB10361AA16}" -Path "$gpoDir\MSFT" -TargetName "MSFT Windows Server 2022 - Domain Security" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{20FAD6FB-7C6D-496E-801C-0434769847FF}" -Path "$gpoDir\MSFT" -TargetName "MSFT Windows Server 2022 - Member Server" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{02B7D8F9-E7A7-470B-B16B-FED032FFD9CB}" -Path "$gpoDir\MSFT" -TargetName "MSFT SMB v1 client for pre-Win8.1/2012R2" -CreateIfNeeded | Out-Null
# DOMAIN SPECIFIC
Import-GPO -BackupId "{58818EE0-E49D-4B43-BAEC-EC7E7F2FEB68}" -Path "$gpoDir\Domain" -TargetName "$domain - Разрешить запись CD/DVD" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{7CF733B4-9615-4873-ADA5-048D52A443DE}" -Path "$gpoDir\Domain" -TargetName "$domain - Отключение соединения с Интернетом" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{39279DBB-E09B-41DB-BB5D-543D373D290D}" -Path "$gpoDir\Domain" -TargetName "$domain - Server" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{54B825EA-04CD-4D93-818A-8A61E56A6677}" -Path "$gpoDir\Domain" -TargetName "$domain - User" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{B39206B4-164D-468C-A75B-C0DEFE063C79}" -Path "$gpoDir\Domain" -TargetName "$domain - Computer" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{E6980432-EC0F-48C7-8687-F740714D30EC}" -Path "$gpoDir\Domain" -TargetName "$domain - Сетевые диски" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{B52C5A99-1449-4DDE-8765-D14295EC3FC6}" -Path "$gpoDir\Domain" -TargetName "WSUS - Настройка сервера обновлений" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{F88E4011-66FE-48EF-A6D9-ACAAB6F7B62B}" -Path "$gpoDir\Domain" -TargetName "WSUS - Настройка серверов" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{3FFDE1CB-5DBD-46E2-82C9-3EC2C998EDBB}" -Path "$gpoDir\Domain" -TargetName "WSUS - Настройка клиентских ПК" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{47F97955-EDBE-4D61-BAC1-A8EFBC2E921C}" -Path "$gpoDir\Domain" -TargetName "WSUS - Обновление Office 2021" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{A9E45958-9722-4E45-B14F-45D6B8F36E92}" -Path "$gpoDir\Domain" -TargetName "Audit - Настройки DC для Netwrix" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{7EE57ACB-2181-41FF-A140-93ADCF1FD60D}" -Path "$gpoDir\Domain" -TargetName "Audit - Настройки FS для Netwrix" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{DB7998E8-09A2-4856-8DA7-6AAD1A524E24}" -Path "$gpoDir\Domain" -TargetName "Audit - Сбор журналов печати" -CreateIfNeeded | Out-Null
Import-GPO -BackupId "{4C790A8F-920C-4404-960B-F788E38FA620}" -Path "$gpoDir\Domain" -TargetName "WinRM - Включить службу" -CreateIfNeeded | Out-Null
# NEW GPO
(New-GPO -Name "LAPS - Установка x86").GpoStatus = "UserSettingsDisabled"
(New-GPO -Name "LAPS - Установка x64").GpoStatus = "UserSettingsDisabled"
# Применение WMI фильтров к GPO
Get-GPO -Name "LAPS - Установка x86" | Set-GPWmiFilterAssignment -Filter "Only x86 OS"
Get-GPO -Name "LAPS - Установка x64" | Set-GPWmiFilterAssignment -Filter "Only x64 OS"
Get-GPO -Name "MSFT SMB v1 client for pre-Win8.1/2012R2" | Set-GPWmiFilterAssignment -Filter "Windows 7-8 and Servers 2008-2012"
```
#### Подготавливаем схему AD для LAPS

```powershell
Import-module AdmPwd.PS
Update-AdmPwdADSchema
Set-AdmPwdComputerSelfPermission -OrgUnit "Domain Computers"
Set-AdmPwdComputerSelfPermission -OrgUnit "Domain Servers"
```

#### Привязываем созданные GPO к OU

```powershell
# DOMAIN
New-GPLink -Name "WSUS - Настройка сервера обновлений" -Target "DC=domain,DC=lab" | Set-GPLink -Order 1 | Out-Null
New-GPLink -Name "$domain - Отключение соединения с Интернетом" -Target "DC=domain,DC=lab" | Set-GPLink -Order 2 | Out-Null
New-GPLink -Name "MSFT Windows Server 2022 - Domain Security" -Target "DC=domain,DC=lab" | Set-GPLink -Order 3 | Out-Null
# DOMAIN CONTROLLERS
New-GPLink -Name "Audit - Настройки DC для Netwrix" -Target "OU=Domain Controllers,DC=domain,DC=lab" | Set-GPLink -Order 1 | Out-Null
New-GPLink -Name "MSFT Windows Server 2022 - Domain Controller" -Target "OU=Domain Controllers,DC=domain,DC=lab" | Set-GPLink -Order 2 | Out-Null # Внимание на Exchange Servers!
# DOMAIN SERVERS
New-GPLink -Name "$domain - Server" -Target "OU=Domain Servers,DC=domain,DC=lab" | Set-GPLink -Order 1 | Out-Null
New-GPLink -Name "Audit - Сбор журналов печати" -Target "OU=Domain Servers,DC=domain,DC=lab" | Set-GPLink -Order 2 | Out-Null
New-GPLink -Name "Audit - Настройки FS для Netwrix" -Target "OU=Domain Servers,DC=domain,DC=lab" | Set-GPLink -Order 3 | Out-Null # Указать только для FS!
New-GPLink -Name "WSUS - Настройка серверов" -Target "OU=Domain Servers,DC=domain,DC=lab" | Set-GPLink -Order 4 | Out-Null
New-GPLink -Name "LAPS - Установка x64" -Target "OU=Domain Servers,DC=domain,DC=lab" | Set-GPLink -Order 5 | Out-Null
New-GPLink -Name "MSFT Windows Server 2022 - Member Server" -Target "OU=Domain Servers,DC=domain,DC=lab" | Set-GPLink -Order 6 | Out-Null
# DOMAIN COMPUTERS
New-GPLink -Name "$domain - Computer" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 1 | Out-Null
New-GPLink -Name "WinRM - Включить службу" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 2 | Out-Null
New-GPLink -Name "Audit - Сбор журналов печати" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 3 | Out-Null
New-GPLink -Name "WSUS - Обновление Office 2021" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 4 | Out-Null
New-GPLink -Name "WSUS - Настройка клиентских ПК" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 5 | Out-Null
New-GPLink -Name "LAPS - Установка x86" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 6 | Out-Null
New-GPLink -Name "LAPS - Установка x64" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 7 | Out-Null
New-GPLink -Name "MSFT SMB v1 client for pre-Win8.1/2012R2" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 8 | Out-Null
New-GPLink -Name "MSFT Windows 10 21H2 - Computer" -Target "OU=Domain Computers,DC=domain,DC=lab" | Set-GPLink -Order 9 | Out-Null
# DOMAIN USERS
New-GPLink -Name "$domain - Разрешить запись CD/DVD" -Target "OU=Domain Users,DC=domain,DC=lab" | Set-GPLink -Order 1 | Out-Null # Указать только отдельных пользователей!
New-GPLink -Name "$domain - Сетевые диски" -Target "OU=Domain Users,DC=domain,DC=lab" | Set-GPLink -Order 2 | Out-Null
New-GPLink -Name "$domain - User" -Target "OU=Domain Users,DC=domain,DC=lab" | Set-GPLink -Order 3 | Out-Null
New-GPLink -Name "MSFT Windows 10 21H2 - User" -Target "OU=Domain Users,DC=domain,DC=lab" | Set-GPLink -Order 4 | Out-Null
```
## Создание учетных записей

#### Импорт фейковых пользователей из файла `accounts.csv`

```powershell
Import-Csv -Path "C:\GPO\accounts.csv" | Select-Object `
  @{Name="Name";Expression={$_.Username}},
  @{Name="UserPrincipalName"; Expression={$_.Username +"@domain.lab"}},
  @{Name="SamAccountName"; Expression={$_.Username}},
  @{Name="GivenName";Expression={$_.GivenName}},
  @{Name="Surname";Expression={$_.Surname}},
  @{Name="Description"; Expression={$_.Surname + " " + $_.GivenName}},
  @{Name="DisplayName"; Expression={$_.Surname + " " + $_.GivenName}},
  @{Name="AccountPassword"; Expression={(Convertto-SecureString -Force -AsPlainText "Password1234@!")}},
  @{Name="Path"; Expression={"OU=Domain Users,DC=domain,DC=lab"}},
  @{Name="Enabled"; Expression={$true}},
  @{Name="ChangePasswordAtLogon"; Expression={$false}},
  @{Name="PasswordNeverExpires"; Expression={$true}} `
| ForEach-Object -Process { $_ | New-ADUser }
```
#### Создание отдельного пользователя через Powershell

```powershell
New-Object PSObject -Property @{
  Name                  = "Ivanov"
  UserPrincipalName     = "Ivanov@domain.lab"
  SamAccountName        = "Ivanov"
  GivenName             = "Иван"
  Surname               = "Иванов"
  Description           = "Иванов И.И."
  DisplayName           = "Иванов И.И."
  AccountPassword       = (ConvertTo-SecureString -Force -AsPlainText "Password1234@!")
  Path                  = "OU=Domain Users,DC=domain,DC=lab"
  Enabled               = $true
  ChangePasswordAtLogon = $false
  PasswordNeverExpires  = $true
} | New-ADUser
```

#### Создание учетки администратора домена `root`

```powershell

$password = "Password1234@!" | ConvertTo-SecureString -AsPlainText -Force
New-ADUser -Name root -UserPrincipalName "root@domain.lab" -AccountPassword $password -ChangePasswordAtLogon $false -Enabled $true -PasswordNeverExpires $true
Add-ADGroupMember "Администраторы домена" root
```

#### Создание групп отделов и добавление туда пользователей

```powershell
New-ADGroup -Name "1 Отдел" -SamAccountName "1 Отдел" -Path "OU=Domain Users,DC=domain,DC=lab" -GroupCategory "Security" -Description "1 Отдел" -GroupScope "Global" -PassThru
New-ADGroup -Name "2 Отдел" -SamAccountName "2 Отдел" -Path "OU=Domain Users,DC=domain,DC=lab" -GroupCategory "Security" -Description "2 Отдел" -GroupScope "Global" -PassThru
New-ADGroup -Name "3 Отдел" -SamAccountName "3 Отдел" -Path "OU=Domain Users,DC=domain,DC=lab" -GroupCategory "Security" -Description "3 Отдел" -GroupScope "Global" -PassThru
$users = Get-ADUser -Filter * -SearchBase "OU=Domain Users,DC=domain,DC=lab"
$users | Select-Object -First 15 | ForEach-Object { Add-ADGroupMember "1 Отдел" -Members $_ }
$users | Select-Object -First 15 -Skip 15 | ForEach-Object { Add-ADGroupMember "2 Отдел" -Members $_ }
$users | Select-Object -Skip 30 | ForEach-Object { Add-ADGroupMember "3 Отдел" -Members $_ }
```