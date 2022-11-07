# Настройка exchange

## Базовые настройки после установки операционной системы

Установка сетевых параметров, имени компьютера, включение в домен

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.69.5 -PrefixLength 24 -DefaultGateway 192.168.69.254
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses ("192.168.69.1","192.168.69.2")
New-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\" -Name "DisabledComponents" -Value 0xffffffff -PropertyType "DWord"
slmgr.vbs -ipk VDYBN-27WPP-V4HQT-9VMD4-VMK7H
Add-Computer -NewName "EXCHANGE" -DomainName "domain.lab" -OUPath "OU=Domain Servers,DC=domain,DC=lab" -Credential "Администратор@domain.lab" -Restart -Force
```

## Установка Exchange Server 2019

#### Установка компонентов Windows для Server Core

```powershell
Install-WindowsFeature Server-Media-Foundation, NET-Framework-45-Features, RPC-over-HTTP-proxy, RSAT-Clustering, RSAT-Clustering-CmdInterface, RSAT-Clustering-PowerShell, WAS-Process-Model, Web-Asp-Net45, Web-Basic-Auth, Web-Client-Auth, Web-Digest-Auth, Web-Dir-Browsing, Web-Dyn-Compression, Web-Http-Errors, Web-Http-Logging, Web-Http-Redirect, Web-Http-Tracing, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Metabase, Web-Mgmt-Service, Web-Net-Ext45, Web-Request-Monitor, Web-Server, Web-Stat-Compression, Web-Static-Content, Web-Windows-Auth, Web-WMI, RSAT-ADDS
```

#### Предварительные требования для установки Exchange 2019

1. **[.NET Framework 4.8](https://download.visualstudio.microsoft.com/download/pr/014120d7-d689-4305-befd-3cb711108212/0fd66638cde16859462a6243a4629a50/ndp48-x86-x64-allos-enu.exe)**
2. **[Распространяемый пакет Visual C++ для Visual Studio 2012](https://www.microsoft.com/download/details.aspx?id=30679)**
3. **[Распространяемый пакет Visual C++ для Visual Studio 2013](https://support.microsoft.com/help/4032938/update-for-visual-c-2013-redistributable-package)**
4. **[Модуль перезаписи URL-адресов IIS](https://www.iis.net/downloads/microsoft/url-rewrite)**
5. **Unified Communications Managed API 4.0**. Этот пакет находится в папке `\UCMARedist` на носителе Exchange Server.

Устанавливаем:

```powershell
.\ndp48-x86-x64-allos-enu.exe /q
.\vcredist_x64_2012.exe
.\vcredist_x64_2013.exe
& 'E:\UCMARedist\Setup.exe'
.\rewrite_amd64_ru-RU.msi
```

#### Подготовка AD

```powershell
.\Setup.exe /PrepareSchema /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF
.\Setup.exe /PrepareAD /OrganizationName:"domain lab" /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF
.\Setup.exe /PrepareAllDomains /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF
```

#### Установка Exchange

```powershell
.\Setup.exe
```

## Настройка Exchange Server 2019

#### Переименование и перемещение базы данных

```powershell
Get-MailboxDatabase | Set-MailboxDatabase -Name "DB2019" -CircularLoggingEnabled $True
mkdir -p "D:\ExchangeDB\DB2019\Logs"
Move-DatabasePath -Identity "DB2019" -EdbFilePath "D:\ExchangeDB\DB2019\DB2019.edb" -LogFolderPath "D:\ExchangeDB\DB2019\Logs"
Get-MailboxDatabase | Format-List EdbFilePath,LogFolderPath
```

#### Создание коннектора отправки

```powershell
New-SendConnector -Custom -Name "External Send Connector" -AddressSpaces *
```

#### Установка размера журнала сообщений и места его хранения (1 год)

```powershell
mkdir -p "D:\MessageTrackingLog"
Set-TransportService EXCHANGE -MessageTrackingLogPath "D:\MessageTrackingLog" -MessageTrackingLogMaxFileSize 20MB -MessageTrackingLogMaxDirectorySize 15GB -MessageTrackingLogMaxAge 365.00:00:00
```

#### Настройка лимитов по размеру сообщений (100 Мб)

```powershell
Set-TransportConfig -MaxReceiveSize 100MB -MaxSendSize 100MB
Get-ReceiveConnector | Set-ReceiveConnector -MaxMessageSize 100MB
Get-SendConnector | Set-SendConnector -MaxMessageSize 100MB
```

#### Настройка политики адресов электронной почты `фамилия.имя@domain.lab`

Могут быть проблемы если *Имя* и *Фамилию* пользователей писать на русском. Поэтому эту настройку можно пропустить.

```powershell
Set-EmailAddressPolicy -Identity "Default Policy" -EnabledEmailAddressTemplates "SMTP: %s.%g@domain.lab"
Get-EmailAddressPolicy | Update-EmailAddressPolicy
```

Переменная  |  Значение
:---: |  ---
%g  |  Имя
%s  |  Фамилия
%i  |  Буква отчества
%d  |  Отображаемое имя
%m  |  Псевдоним Exchange
%r*xy*  |  Замена всех случаев x на y
%r*xx*  |  Удаление всех случаев x
%*n*g  |  Первые буквы n от имени. Например, `%2g` использует  первые две буквы имени.
%*n*s  |  Первые буквы n с фамилией. Например, `%2s` использует первые две буквы фамилии.

#### Настройка внешних и внутренних ссылок `exchange.domain.lab`

```powershell
$fqdn = "exchange.domain.lab"
Get-OutlookAnywhere | Set-OutlookAnywhere -InternalHostname $fqdn -ExternalHostname $fqdn -ExternalClientsRequireSsl $true -InternalClientsRequireSsl $true -InternalClientAuthenticationMethod negotiate -ExternalClientAuthenticationMethod negotiate
Get-ClientAccessService | Set-ClientAccessService -AutoDiscoverServiceInternalUri "https://$fqdn/Autodiscover/Autodiscover.xml"
Get-MapiVirtualDirectory | Set-MapiVirtualDirectory -InternalUrl "https://$fqdn/mapi" -ExternalUrl "https://$fqdn/mapi"
Get-OabVirtualDirectory | Set-OabVirtualDirectory -InternalUrl "https://$fqdn/OAB" -ExternalUrl "https://$fqdn/OAB"
Get-WebServicesVirtualDirectory | Set-WebServicesVirtualDirectory -InternalUrl "https://$fqdn/EWS/Exchange.asmx" -ExternalUrl "https://$fqdn/EWS/Exchange.asmx"
Get-ActiveSyncVirtualDirectory | Set-ActiveSyncVirtualDirectory -InternalUrl "https://$fqdn/Microsoft-Server-ActiveSync" -ExternalUrl "https://$fqdn/Microsoft-Server-ActiveSync"
Get-PowerShellVirtualDirectory | Set-PowerShellVirtualDirectory -InternalUrl "http://$fqdn/powershell" -ExternalUrl "http://$fqdn/powershell"
Get-OwaVirtualDirectory | Set-OwaVirtualDirectory -InternalUrl "https://$fqdn/owa" -ExternalUrl "https://$fqdn/owa"
Get-EcpVirtualDirectory | Set-EcpVirtualDirectory -InternalUrl "https://$fqdn/ecp" -ExternalUrl "https://$fqdn/ecp"
```

#### Запрос нового сертификата (файл *.req)

```powershell
$txtrequest = New-ExchangeCertificate -PrivateKeyExportable $True -GenerateRequest -FriendlyName "domain.lab Exchange Certificate" -SubjectName "C=BY,CN=exchange.domain.lab" -DomainName "exchange.domain.lab","autodiscover.domain.lab","mail.domain.lab"
[System.IO.File]::WriteAllBytes('\\DC1\C$\GPO\exchange.req', [System.Text.Encoding]::Unicode.GetBytes($txtrequest))
```

#### Установка подписанного сертификата (файл *.cer)

```powershell
Import-ExchangeCertificate -FileData ([System.IO.File]::ReadAllBytes('\\DC1\C$\GPO\exchange.cer'))
Get-ExchangeCertificate | Where-Object {$_.Status -eq "Valid" -and $_.IsSelfSigned -eq $false} | Format-List FriendlyName,Subject,CertificateDomains,Thumbprint
Enable-ExchangeCertificate -Thumbprint "ОТПЕЧАТОК" -Services IIS
```

#### Установка сертификата в случае его наличия в *.pfx файле с закрытым ключем

```powershell
# пароль к *.pfx файлу
$password = "Password1234@!" | ConvertTo-SecureString -AsPlainText -Force
Import-PfxCertificate -FilePath "D:\exchange.pfx" -CertStoreLocation "Cert:\LocalMachine\My" -Password $password
Get-ExchangeCertificate | Where-Object {$_.Status -eq "Valid" -and $_.IsSelfSigned -eq $false} | Format-List FriendlyName,Subject,CertificateDomains,Thumbprint
Enable-ExchangeCertificate -Thumbprint "ОТПЕЧАТОК" -Services IIS
```
После всех операций со ссылками и сертификатами необходимо перезагрузить IIS сервер командой **`iisreset`**

#### Активация Exchange Server

```powershell
LaunchEMS
Get-ExchangeServer | Set-ExchangeServer -ProductKey "КЛЮЧ"
Restart-Service MSExchangeIS
```

#### Создание ящиков пользователей

```powershell
# Отдельный пользователь
Get-User ivanov | Enable-Mailbox
# Все пользователи
Get-User -OrganizationalUnit "Domain Users" | Where-Object {$_.RecipientType -eq "User"} | Enable-Mailbox
# Список ящиков
Get-Mailbox | Format-Table Name,WindowsEmailAddress
```

#### Создание политики хранения сообщений в ящиках пользователей (1 год)

```powershell
# Создание тегов хранения
New-RetentionPolicyTag 'Удалить письма старше 30 дней' -Type 'DeletedItems' -AgeLimitForRetention 30 -RetentionAction 'DeleteAndAllowRecovery' -RetentionEnabled $true
New-RetentionPolicyTag 'Удалить письма старше 365 дней' -Type 'All' -AgeLimitForRetention 365 -RetentionAction 'DeleteAndAllowRecovery' -RetentionEnabled $true
New-RetentionPolicyTag 'Не удалять контакты' -Type 'Contacts' -RetentionAction 'DeleteAndAllowRecovery' -RetentionEnabled $false
# Создание политики хранения
New-RetentionPolicy "Политика хранения domain.lab" -RetentionPolicyTagLinks "Не удалять контакты","Удалить письма старше 365 дней","Удалить письма старше 30 дней"
# Применение политики хранения к ящикам без политик
Get-Mailbox -OrganizationalUnit "OU=Domain Users,DC=domain,DC=lab" | Where-Object {$_.RetentionPolicy -like ""} | Set-Mailbox -RetentionPolicy "Политика хранения domain.lab"
```

#### Добавление логотипа организации пользователям

```powershell
# Всем пользователям
$image = "D:\Logo.jpg"
Get-ADUser -Filter * -SearchBase "OU=Domain Users,DC=domain,DC=lab" -Properties * | Where-Object { $_.thumbnailPhoto -like "" -and $_.EmailAddress -notlike "" } | ForEach-Object { Import-RecipientDataProperty -Identity $_.DistinguishedName -Picture -FileData ([Byte[]]$(Get-Content -Path $image -Encoding Byte -ReadCount 0)) }
# Конкретному пользователю
$user = "ivanov"
$image = "D:\Logo.jpg"
Import-RecipientDataProperty -Identity $user -Picture -FileData ([Byte[]]$(Get-Content -Path $image -Encoding Byte -ReadCount 0))
```

## Диагностика Exchange Server

#### Проверка служб и БД

```powershell
Test-ServiceHealth
Test-MAPIConnectivity
```

#### Показать лог сообщений

```powershell
Get-MessageTrackingLog -Start (Get-Date "26.01.2022 00:00") -ResultSize Unlimited | Sort-Object Timestamp
```

#### Просмотр всех ящиков леса

```powershell
Set-ADServerSettings -ViewEntireForest $true
Get-Mailbox | Format-Table Name,ServerName,Database,AdminDisplayVersion,ProhibitSendQuota
Get-Mailbox -AuditLog | Format-Table Name,ServerName,Database,AdminDisplayVersion,ProhibitSendQuota
Get-Mailbox -Arbitration | Format-Table Name,ServerName,Database,AdminDisplayVersion,ProhibitSendQuota
Get-Mailbox -PublicFolder | Format-Table Name,ServerName,Database,AdminDisplayVersion,ProhibitSendQuota
Get-Mailbox -Archive | Format-Table Name,ServerName,Database,AdminDisplayVersion,ProhibitSendQuota
```

#### Посмотреть транспорт (в т.ч. антиспам фильтры)

```powershell
Get-TransportAgent
```

#### Посмотреть лимиты размеров сообщений

Значения по умолчанию после установки:
- TransportConfig: `MaxReceiveSize` = `10 MB`, `MaxSendSize` = `10 MB`
- ReceiveConnector: `MaxMessageSize` = `36 MB`
- SendConnector: `MaxMessageSize` = `10 MB`

```powershell
# Лимиты на уровне организации
Get-TransportConfig | Format-List MaxReceiveSize,MaxSendSize,MaxRecipientEnvelopeLimit
Get-TransportRule | Where-Object { ($_.MessageSizeOver -ne $null) -or ($_.AttachmentSizeOver -ne $null) } | Format-Table Name,MessageSizeOver,AttachmentSizeOver
# Лимиты на уровне коннекторов
Get-ReceiveConnector | Format-Table Name,Max*Size,MaxRecipientsPerMessage
Get-SendConnector | Format-Table Name,MaxMessageSize
Get-AdSiteLink | Format-Table Name,MaxMessageSize
Get-DeliveryAgentConnector | Format-Table Name,MaxMessageSize
Get-ForeignConnector | Format-Table Name,MaxMessageSize
# Лимиты на уровне получателей
$mb = Get-Mailbox -ResultSize unlimited; $mb | Where-Object {$_.RecipientTypeDetails -eq 'UserMailbox'} | Format-Table Name,MaxReceiveSize,MaxSendSize,RecipientLimits
```

#### Пример миграции ящиков между базами

```powershell
Get-Mailbox -Database "DB2016" | New-MoveRequest -TargetDatabase "DB2019" -BatchName "DB2016-to-DB2019"
Get-Mailbox -Arbitration -Database "DB2016" | New-MoveRequest -TargetDatabase "DB2019" -BatchName "DB2016-to-DB2019-arbitration"
```

#### Подключиться к удаленной сессии Exchange с другого сервера

```powershell
$UserCred = Get-Credential -Credential "DOMAIN\Администратор"
$ExSession = New-PSSession -ConfigurationName Microsoft.Exchange –Name ExchangeSession -ConnectionUri "http://exchange.domain.lab/powershell" -Credential $UserCred -Authentication Kerberos
Import-PSSession $ExSession
```