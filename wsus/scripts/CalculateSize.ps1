[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, "8530")

$products = $wsus.GetSubscription().GetUpdateCategories().Title

Write-Host ""
Write-Host "Getting All Updates..."
$AllUpdates = $wsus.GetUpdates()
Write-Host ""
Write-Host "Calculating sizes..."
Write-Host ""

foreach ($product in $products) {
  $ProductUpdates = $AllUpdates | Where-Object {$_.ProductTitles -eq $product}
  $size = 0
  $numfiles = 0
  $numupdates = 0

  foreach ($update in $ProductUpdates) {
    if ($update.IsApproved) {
      $numupdates++
      $items = $update.GetInstallableItems()
      foreach ($item in $items){
        if ($item.languages -eq "en" -or $item.languages -eq "ru" -or $item.languages -eq "all") {
          foreach ($file in $item.files){
            if ($file.type -ne "Express") {
              $size += $file.totalbytes
              $numfiles++
            }
          }
        }
      }
    }
  }
  $size = [math]::Round($size/1MB,2)
  Write-Host $product "-" $size "Mb in" $numfiles "files of" $numupdates "updates."
}

$size = 0
$numfiles = 0
$numupdates = 0
$filestable = @{}
foreach ($update in $AllUpdates) {
  if ($update.IsApproved) {
    $numupdates++
    $items = $update.GetInstallableItems()
    foreach ($item in $items){
      if ($item.languages -eq "en" -or $item.languages -eq "ru" -or $item.languages -eq "all") {
        foreach ($file in $item.files){
          if ($file.type -ne "Express") {
            if (!$filestable.ContainsKey($file.FileUri)) {
              $filestable.Add($file.FileUri, $true)
              $size += $file.totalbytes
              $numfiles++
            }
          }
        }
      }
    }
  }
}
$size = [math]::Round($size/1MB,2)
Write-Host "TOTAL -" $size "Mb in" $numfiles "files of" $numupdates "updates."