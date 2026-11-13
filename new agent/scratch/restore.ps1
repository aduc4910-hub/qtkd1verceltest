$fullPath = 'C:\Users\Lenovo\.gemini\antigravity\brain\4526de78-8d77-4972-9ec6-78afced33c89\.system_generated\logs\transcript_full.jsonl'
$stream = [System.IO.File]::OpenRead($fullPath)
$reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)

$foundLine = $null
while (-not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    if ($line.Contains('"step_index":790,')) {
        $foundLine = $line
        break
    }
}
$reader.Close()
$stream.Close()

if ($foundLine) {
    $obj = $foundLine | ConvertFrom-Json
    $content = $obj.tool_calls[0].args.Content
    $utf8WithBOM = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText("c:\Users\Lenovo\OneDrive\Tài liệu\new agent\src\api_engine.ps1", $content, $utf8WithBOM)
    Write-Host "Success: restored api_engine.ps1! Length: $($content.Length)"
} else {
    Write-Host "Step 790 not found in transcript_full"
}
