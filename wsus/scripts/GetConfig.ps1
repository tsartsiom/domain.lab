[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | out-null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, "8530")

$config = $wsus.GetConfiguration()
$subscription = $wsus.GetSubscription()
$products = $subscription.GetUpdateCategories()
$classifications = $subscription.GetUpdateClassifications()

Write-Host ""
Write-Host "Products:"
$products.Title

Write-Host ""
Write-Host "Classifications:"
$classifications.Title

Write-Host ""
Write-Host "Languages:"
$config.GetEnabledUpdateLanguages()

Write-Host ""