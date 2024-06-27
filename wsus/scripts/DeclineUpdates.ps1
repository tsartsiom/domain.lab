[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | out-null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, "8530")

$excludeArray = @(
  "ARM64",
  "Windows 10 Version Next",
  "Windows Server Next",
  "Windows 10 Version 21H1", # End of servicing 2022-12-13
  "Windows 10 Version 20H2", # End of servicing 2023-05-09
  "Windows 10 Version 2004", # End of servicing 2021-12-14
  "Windows 10 Version 1909", # End of servicing 2022-05-10
  "Windows 10 Version 1903", # End of servicing 2020-12-08
  "Windows 10 Version 1803", # End of servicing 2021-05-11
  "Windows 10 Version 1709", # End of servicing 2020-10-13
  "Windows 10 Version 1703", # End of servicing 2019-10-08
  "Windows 10 Version 1511", # End of servicing 2018-04-10
  "Security Only Quality",
  "Internet Explorer",
  "SharePoint",
  "farm-deployment",
  "Publisher",
  "Online Server",
  "OneDrive for Business",
  "OneNote",
  "Microsoft Project",
  "Skype for Business",
  "Exchange Server (2010 (Service Pack [12])|2010 \()",
  "Exchange Server (2016 (RTM|CU(?!23))|2016 \()",
  "Exchange Server (2019 (RTM|CU(?!14))|2019 \()"
)

Write-Host ""
Write-Host "Getting All Updates..."
$allUpdates = $wsus.GetUpdates()
Write-Host "Decline Superseded Updates..."
Write-Host ""

$countSuperseded = 0

foreach ($update in $allUpdates) {
  if (!$update.IsDeclined -and $update.IsSuperseded) {
    $countSuperseded++
    $update.Decline()
  }
}

Write-Host "Declined" $countSuperseded "Superseded Updates."
Write-Host ""


Write-Host "Decline Excluded Updates..."
$allUpdates = $wsus.GetUpdates()
Write-Host ""

$countExcluded = 0

foreach($exclude in $excludeArray) {
  $updates = $allUpdates | Where-Object {$_.Title -match "$exclude"}
  $count = 0
  foreach($update in $updates) {
    if (!$update.IsDeclined){
      $countExcluded++
      $count++
      $update.Decline()
    }   
  }
  Write-Host $exclude "=" $count
}

Write-Host ""
Write-Host "Declined" $countExcluded "Excluded Updates."
Write-Host ""
$total = $countExcluded+$countSuperseded
Write-Host "TOTAL Declined" $total "Updates."
Write-Host ""