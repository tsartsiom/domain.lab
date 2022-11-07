[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()

$updatescope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
$updatescope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::Declined
$notapproved = [Microsoft.UpdateServices.Administration.UpdateApprovalAction]::NotApproved
$computergroup = $wsus.GetComputerTargetGroup("b73ca6ed-5727-47f3-84de-015e03f6a88a")
$count = $wsus.GetUpdateCount($updatescope)

Write-Progress "Getting updates..."
$updates = $wsus.GetUpdates()

$i = 1

foreach ($update in $updates) {
  if ($update.IsDeclined) {
    $percent = [math]::Round($i/$count*100,2)
    Write-Progress -Activity "Restoring updates..." -Status "$percent% Complete:" -PercentComplete $percent
    $update.Approve($notapproved,$computergroup) | Out-Null
    $i++
  }
}