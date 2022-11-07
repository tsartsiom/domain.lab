# Настройка fs1

## Базовые настройки после установки операционной системы

Установка сетевых параметров, имени компьютера, включение в домен

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.69.4 -PrefixLength 24 -DefaultGateway 192.168.69.254
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses ("192.168.69.1","192.168.69.2")
New-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\" -Name "DisabledComponents" -Value 0xffffffff -PropertyType "DWord"
slmgr.vbs -ipk VDYBN-27WPP-V4HQT-9VMD4-VMK7H
Add-Computer -NewName "FS1" -DomainName "domain.lab" -OUPath "OU=Domain Servers,DC=domain,DC=lab" -Credential "Администратор@domain.lab" -Restart -Force
```

## Настройка файлового сервера

#### Установка компонентов Windows

```powershell
Install-WindowsFeature -Name FS-Data-Deduplication,FS-Resource-Manager,RSAT-ADDS -IncludeManagementTools
```

#### Создание общих папок

1. Создаем корневые папки
	- Устанавливаем права на корневые папки (`Администраторы`, `Прошедшие проверку`)
	- Устанавливаем аудит на корневые папки (`Все`)
3. Создаем папки подразделений
	- Устанавливаем права на папки подразделений (`Администраторы`, *`Подразделение`*)
4. Создаем папки пользователей
	- Устанавливаем права на папки пользователей (`Администраторы`, *`Пользователь`*)

#### Входные данные

- Группа администраторов: `Администраторы`
- Общая папка: `D:\Общий`
- Папка подразделений `D:\Подразделения`
- Папка пользователей `D:\Пользователи`

```powershell
$adminGroup = "Администраторы"
$commonFolder = "D:\Общий"
$divisionFolder = "D:\Подразделения"
$userFolder = "D:\Пользователи"
```

#### Создание корневых папок

```powershell
# Корневые папки
$rootFolders = @(
  $commonFolder,
  $divisionFolder,
  $userFolder
)

foreach ($folder in $rootFolders) {
  New-Item -Type Directory -Path $folder

  # Выключаем наследование
  $acl = Get-Acl $folder
  $acl.SetAccessRuleProtection($true,$false)

  # Access admins (Для этой папки, ее подпапок и файлов)
  $permission = $adminGroup,"FullControl","ContainerInherit,ObjectInherit","None","Allow"
  $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
  $acl.AddAccessRule($accessRule)
  # Access All (Для этой папки, ее подпапок и файлов)
  $permission = "Прошедшие проверку","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow"
  $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
  $acl.AddAccessRule($accessRule)

  # Audit Successful reads (Только для файлов)
  $permission = "Все","ReadData","ObjectInherit","InheritOnly","Success"
  $auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule $permission
  $acl.AddAuditRule($auditRule)
  # Audit Successful changes (Для этой папки, ее подпапок и файлов)
  $permission = "Все","WriteData,AppendData,WriteExtendedAttributes,DeleteSubdirectoriesAndFiles,Delete,ChangePermissions,TakeOwnership","ContainerInherit,ObjectInherit","None","Success"
  $auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule $permission
  $acl.AddAuditRule($auditRule)
  # Audit Failed read and change attempts (Для этой папки, ее подпапок и файлов)
  $permission = "Все","ReadData,WriteData,AppendData,WriteExtendedAttributes,DeleteSubdirectoriesAndFiles,Delete,ChangePermissions,TakeOwnership","ContainerInherit,ObjectInherit","None","Failure"
  $auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule $permission
  $acl.AddAuditRule($auditRule)

  # Сохраняем результат
  Set-Acl $folder $acl
}
```

#### Создание папок подразделений

```powershell
# Папки подразделений подразделений и соответствующие группы в домене
$divFolders = @(
  @{ Name="$divisionFolder\1 Отдел"; Group="DOMAIN\1 Отдел" },
  @{ Name="$divisionFolder\2 Отдел"; Group="DOMAIN\2 Отдел" },
  @{ Name="$divisionFolder\3 Отдел"; Group="DOMAIN\3 Отдел" }
)

# Создание папок подразделений и устновка их настроек
foreach ($folder in $divFolders) {
  New-Item -Type Directory -Path $folder.Name
  
  # Выключаем наследование
  $acl = Get-Acl $folder.Name -Audit
  $acl.SetAccessRuleProtection($true,$false)
  
  # Access admins (Для этой папки, ее подпапок и файлов)
  $permission  = $adminGroup,"FullControl","ContainerInherit,ObjectInherit","None","Allow"
  $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
  $acl.AddAccessRule($accessRule)
  # Access Group (Только для подпапок и файлов)
  $permission = $folder.Group,"Modify","ContainerInherit,ObjectInherit","InheritOnly","Allow" 
  $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
  $acl.AddAccessRule($accessRule)
  # Access Group (Только для этой папки)
  $permission = $folder.Group,"ReadAndExecute,Write","None","None","Allow"
  $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
  $acl.AddAccessRule($accessRule)

  # Сохраняем результат
  Set-Acl $folder.Name $acl
}
```

#### Создание папок пользователей

```powershell
# Получение списка пользователей
$users = Get-ADUser -Filter * -SearchBase "OU=Domain Users,DC=domain,DC=lab"

foreach ($user in $users) {
  $folder = Join-Path -Path $userFolder -ChildPath $user.Name
  New-Item -Type Directory -Path $folder
  
  # Выключаем наследование
  $acl = Get-Acl $folder -Audit
  $acl.SetAccessRuleProtection($true,$false)
  
  # Access admins (Для этой папки, ее подпапок и файлов)
  $permission  = $adminGroup,"FullControl","ContainerInherit,ObjectInherit","None","Allow"
  $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
  $acl.AddAccessRule($accessRule)
  # Access User (Только для подпапок и файлов)
  $permission = $user.UserPrincipalName,"Modify","ContainerInherit,ObjectInherit","InheritOnly","Allow" 
  $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
  $acl.AddAccessRule($accessRule)
  # Access User (Только для этой папки)
  $permission = $user.UserPrincipalName,"ReadAndExecute,Write","None","None","Allow"
  $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
  $acl.AddAccessRule($accessRule)

  # Сохраняем результат
  Set-Acl $folder $acl
}
```

#### Информация по разрешениям

```
$permission = IdentityReference, FileSystemRights, InheritanceFlags, PropagationFlags, AccessControlType
╔═════════════╦═════════════╦═══════════════════════════════╦════════════════════════╦══════════════════╦═══════════════════════╦═════════════╦═════════════╗
║             ║ folder only ║ folder, sub-folders and files ║ folder and sub-folders ║ folder and files ║ sub-folders and files ║ sub-folders ║    files    ║
╠═════════════╬═════════════╬═══════════════════════════════╬════════════════════════╬══════════════════╬═══════════════════════╬═════════════╬═════════════╣
║ Propagation ║ none        ║ none                          ║ none                   ║ none             ║ InheritOnly           ║ InheritOnly ║ InheritOnly ║
║ Inheritance ║ none        ║ Container|Object              ║ Container              ║ Object           ║ Container|Object      ║ Container   ║ Object      ║
╚═════════════╩═════════════╩═══════════════════════════════╩════════════════════════╩══════════════════╩═══════════════════════╩═════════════╩═════════════╝
```
Документация [FileSystemRights](https://docs.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.filesystemrights)

#### Расшаривание папок

```powershell
New-SmbShare -Name "Общий" -Path $commonFolder -FullAccess "Прошедшие Проверку"
New-SmbShare -Name "Подразделения" -Path $divisionFolder -FullAccess "Прошедшие Проверку" -FolderEnumerationMode AccessBased
New-SmbShare -Name "Пользователи" -Path $userFolder -FullAccess "Прошедшие Проверку" -FolderEnumerationMode AccessBased
```

#### Включение дедупликации на диске `D:\`

```powershell
Enable-DedupVolume -Volume "D:"
```

#### Скрипт для удаления информации

Скрипт `Clean-Folders.ps1` удаляет файлы старше одного часа из указанных папок с исключениями. Указанный скрипт необходимо поместить в планировщик заданий (запуск каждые 10 минут).
