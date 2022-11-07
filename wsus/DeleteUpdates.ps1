﻿[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | out-null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, "8530")

$AllUpdates = $wsus.GetUpdates()

$AllUpdates | Where-Object {$_.ProductTitles -eq 'Windows 10 Feature On Demand'} | ForEach-Object { $wsus.DeleteUpdate($_.Id.UpdateID); Write-Host $_.Title removed }
$AllUpdates | Where-Object {$_.ProductTitles -eq 'Office 2019'} | ForEach-Object { $wsus.DeleteUpdate($_.Id.UpdateID); Write-Host $_.Title removed }
$AllUpdates | Where-Object {$_.ProductTitles -eq 'Office 2013'} | ForEach-Object { $wsus.DeleteUpdate($_.Id.UpdateID); Write-Host $_.Title removed }
$AllUpdates | Where-Object {$_.ProductTitles -eq 'Office 2010'} | ForEach-Object { $wsus.DeleteUpdate($_.Id.UpdateID); Write-Host $_.Title removed }