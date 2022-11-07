function Test-FileInDir {
  param ($file,$dirs)
  $filepath = Split-Path $file
  $result = $false
  foreach ($dir in $dirs) {
    if ( $filepath -like "$dir*" ) {
      $result = $true
      break
    }
  }
  return $result
}

# Где удаляем
$ClearPaths = @(
  "D:\Общий",
  "D:\Подразделения"
)

# Исключение из удаления (ВАЖНО: не ставить слеш "\" в конце пути)
$ExcludeDirs = @(
  "D:\Общий\_Информация",
  "D:\Общий\Install",
  "D:\Подразделения\1 Отдел\_Информация",
  "D:\Подразделения\2 Отдел\_Информация",
  "D:\Подразделения\3 Отдел\_Информация"
)

# Куда пишем лог-файл
$log = "D:\Install\Clear_log\clear_$(Get-Date -f yyyy-MM-dd)"

# Удаление старше одного часа
$date = (Get-Date).AddHours(-1)
foreach ($path in $ClearPaths) {
  $files = Get-ChildItem -Path $path -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $date) -and !(Test-FileInDir $_.FullName $ExcludeDirs) }
  $files | Select-Object CreationTime,@{Name="DeleteTime";Expression={(Get-date)}},FullName | Out-File $log -Append
  $files | Remove-Item -ErrorAction SilentlyContinue -Force
}