[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | out-null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, "8530")
$wsus.GetUpdateCategories("$((Get-Date).AddDays(-60))","$(Get-Date)") | Select-Object Title, Description, Releasenotes, arrivaldate