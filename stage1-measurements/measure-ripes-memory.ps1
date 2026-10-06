function Measure-RipesWorkingSet($src) {
    $args = @(
        "--mode", "cli",
        "--src", $src,
        "-t", "asm",
        "--proc", "RV32_ISS",
        "--timeout", "120000"
    )

    $p = Start-Process `
        -FilePath ".\Ripes.exe" `
        -ArgumentList $args `
        -PassThru

    Start-Sleep -Seconds 3
    $p.Refresh()

    if ($p.HasExited) {
        throw "Ripes exited before measurement: $src"
    }

    $working = $p.WorkingSet64
    Stop-Process -Id $p.Id -Force

    [PSCustomObject]@{
        Source = $src
        WorkingBytes = $working
        WorkingMiB = [math]::Round($working / 1MB, 2)
    }
}

$small = Measure-RipesWorkingSet ".\probe-mem-small.s"
$large = Measure-RipesWorkingSet ".\probe-mem-large.s"

$small
$large

$guestDifference = 262144 - 4096
$hostDifference = $large.WorkingBytes - $small.WorkingBytes
$ratio = $hostDifference / $guestDifference

Write-Host ""
Write-Host "Host difference: $hostDifference bytes"
Write-Host "Guest difference: $guestDifference bytes"
Write-Host "Ratio: $ratio host bytes / guest byte"
