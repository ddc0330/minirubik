$results = @()

foreach ($run in 1..5) {
    foreach ($processor in @("RV32_ISS", "RV32_5S")) {

        $output = "rate-latest.txt"
        Remove-Item $output -ErrorAction SilentlyContinue

        Start-Process -FilePath ".\Ripes.exe" `
            -ArgumentList @(
                "--mode", "cli",
                "--src", ".\probe-rate.s",
                "-t", "asm",
                "--proc", $processor,
                "--iret", "--exectime", "--runinfo",
                "--timeout", "120000",
                "--output", ".\$output"
            ) -Wait

        $content = Get-Content $output -Raw

        if ($content -notmatch '(?m)^===== instructions retired\r?\n(\d+)') {
            throw "Missing instruction count: $processor"
        }
        $retired = [long]$Matches[1]

        if ($content -notmatch '(?m)^===== wall-clock model execution time \(ms\)\r?\n(\d+)') {
            throw "Missing execution time: $processor"
        }
        $ms = [int]$Matches[1]

        if ($retired -ne 3000005 -or $ms -le 0) {
            throw "Invalid measurement: $processor"
        }

        $rate = $retired * 1000.0 / $ms

        $results += [PSCustomObject]@{
            Run = $run
            Processor = $processor
            RetiredInstructions = $retired
            ExecutionTimeMs = $ms
            InstructionsPerSecond = [math]::Round($rate, 2)
        }

        Write-Host "Run $run | $processor | $ms ms | $([math]::Round($rate, 2)) instr/s"
    }
}

$results | Export-Csv ".\instruction-rate-runs.csv" -NoTypeInformation -Encoding UTF8

Write-Host "`n===== Results ====="
$results | Format-Table -AutoSize

Write-Host "`n===== Average ====="
$results |
    Group-Object Processor |
    ForEach-Object {
        [PSCustomObject]@{
            Processor = $_.Name
            AverageTimeMs = [math]::Round(($_.Group | Measure-Object ExecutionTimeMs -Average).Average, 2)
            AverageInstructionsPerSecond = [math]::Round(($_.Group | Measure-Object InstructionsPerSecond -Average).Average, 2)
        }
    } | Format-Table -AutoSize
