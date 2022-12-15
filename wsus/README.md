# Настройка wsus

## Базовые настройки после установки операционной системы

Установка сетевых параметров, имени компьютера, включение в домен

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.69.8 -PrefixLength 24 -DefaultGateway 192.168.69.254
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses ("192.168.69.1","192.168.69.2")
New-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\" -Name "DisabledComponents" -Value 0xffffffff -PropertyType "DWord"
# GLVK ключ для Windows Server 2022 Standard
slmgr.vbs -ipk VDYBN-27WPP-V4HQT-9VMD4-VMK7H
Add-Computer -NewName "WSUS" -DomainName "domain.lab" -OUPath "OU=Domain Servers,DC=domain,DC=lab" -Credential "Администратор@domain.lab" -Restart -Force
```

## Настройка WSUS

#### Дополнительное ПО 

- Устанавливаем роль `Службы Windows Server Update Services` (все по-умолчанию, путь хранения указываем `D:\WSUS`)
- Устанавливаем [Microsoft SQLSysCLRTypes](https://www.microsoft.com/en-us/download/details.aspx?id=100451)
- Устанавливаем [Microsoft Report Viewer](https://www.microsoft.com/en-us/download/details.aspx?id=35747)
- Устанавливаем [SQL Server Management Studio](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-ver16)

В связи с непонятным переводом на русский язык, на сервере с Интернетом рекомендуется устанавливать **английскую** версию Windows Server 2022.

#### Параметры сервера

В настройках сервера, подключенного к Интернету, необходимо в параметрах указать `Продукты`, `Классы` и `Языки` обновлений. 
На сервере без Интернета настраивать ничего не нужно. На нем будет производиться только импорт из сервера с Интернетом.

**Продукты**
```
Windows 10
Windows 10 LTSB
Windows 10, version 1903 and later
Windows 11
Windows 7
Windows 8.1
Windows Server 2008 R2
Windows Server 2012 R2
Windows Server 2012
Windows Server 2016
Windows Server 2019
Windows Server 2022 (Microsoft Server operating system-21H2)
Windows Admin Center
Exchange Server 2010
Exchange Server 2016
Exchange Server 2019
Office 2016
```

**Классы обновлений**
```
Critical Updates
Definition Updates
Security Updates
Service Packs
Tools
Update Rollups
Updates
```
**Языки**
```
Русский
Английский
```

## Экспорт и импорт обновлений

На сервере с Интернетом после синхронизации обновлений, отклоняем ненужные обновления скриптом `DeclineUpdates.ps1`, утверждаем для установки для любой группы компьютеров обновления. Начнется загрузка обновлений (**~35 Гб** для указанных выше настроек). Обновления скачиваются в папку `D:\WSUS\WsusContent`. 
Если при установке роли указали не такую папку, ее путь можно изменить:
```powershell
& 'C:\Program Files\Update Services\Tools\WsusUtil.exe' movecontent D:\WSUS D:\WSUS\movecontent.log
```
Делаем экспорт метаданных обновлений:
```powershell
& 'C:\Program Files\Update Services\Tools\WsusUtil.exe' export D:\WSUS\Metadata\export.xml.gz D:\WSUS\Metadata\export.log
```

В `Options` запускаем `Server Cleanup Wizard` для удаления старых обновлений.
После загрузки и экспорта метаданных всех обновлений, копируем файл `export.xml.gz` и папку `D:\WSUS\WsusContent` на съемный носитель. 

На сервере без Интернета делаем копируем папку `WsusContent` и делаем импорт метаданных обновлений из файла `export.xml.gz`:
```powershell
& 'C:\Program Files\Update Services\Tools\WsusUtil.exe' import D:\WSUS\Metadata\export.xml.gz D:\WSUS\Metadata\import.log
```

После импорта обновления можно утверждать для установки (например, сначала для тестовой группы, а потом для остальных)

## Оптимизация базы данных WSUS

В целях повышения производительности необходимо [оптимизировать базу данных WSUS](https://learn.microsoft.com/en-GB/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide).
Для этого запускаем `SQL Server Management Studio` от имени администратора и подключаемся по адресу `\\.\pipe\MICROSOFT##WID\tsql\query`. 
1. Выполняем запрос `Create custom indexes WSUS Database.sql` для создания индексов
2. Выполняем запрос `Re-index WSUS database.sql` для реиндексации БД

## Скрипты WSUS

- `DeclineUpdates.ps1` - отклонение замененных обновлений и тех, что нам не нужны
- `GetConfig.ps1` - вывод настроек сервера
- `GetLastProducts.ps1` - показать новые продукты за 2 месяца
- `DeleteUpdates.ps1` - удалить из базы данных обновления определенных продуктов
- `CalculateSize.ps1` - примерно посчитать размер обновлений, основываясь **только** данных из БД
- `UnDeclineUpdates.ps1` - перевод всех _отмененных_ обновлений в статус _неутверждено_