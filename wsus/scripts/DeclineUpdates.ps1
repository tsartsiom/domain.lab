[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | out-null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, "8530")

$excludeArray = @(
  "Itanium", 
  "IA64", 
  "ARM64", 
  "Windows 7 Beta", 
  "Windows Server 2008 R2 Beta", 
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
  "Preview of Monthly", 
  "Internet Explorer", 
  "SharePoint", 
  "farm-deployment", 
  "Groove", 
  "Business Productivity", 
  "Search Server", 
  "Project Server", 
  "Publisher", 
  "Web App", 
  "SkyDrive", 
  "Web Apps Server", 
  "Lync", 
  "Online Server", 
  "Social Connector", 
  "OneDrive for Business", 
  "InfoPath", 
  "OneNote", 
  "Microsoft Project", 
  "Web Applications", 
  "Skype for Business",
  "Exchange Server (2010 (Service Pack [12])|2010 \()",
  "Exchange Server (2016 (RTM|CU(?!22))|2016 \()",
  "Exchange Server (2019 (RTM|CU(?!11))|2019 \()",
  "Windows Admin Center 1809"
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

Write-Host "Restoring Windows 7 January 2020 Updates (KB4534310, KB4536952)..."
$restored = $allUpdates | Where-Object {($_.KnowledgebaseArticles -eq "4534310" -or $_.KnowledgebaseArticles -eq "4536952") -and $_.Title -notlike "*Itanium*"}
$restored | ForEach-Object { Get-WsusUpdate -UpdateServer $wsus -UpdateId $_.Id.UpdateID | Approve-WsusUpdate -Action NotApproved -TargetGroupName "Неназначенные компьютеры"}
Write-Host "Restored" $restored.Count "Windows 7 Updates."