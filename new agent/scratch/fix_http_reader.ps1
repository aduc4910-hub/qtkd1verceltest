# Update start_server.ps1 with exact byte-level HTTP reader
$serverPath = "c:\Users\Lenovo\OneDrive\Tài liệu\new agent\start_server.ps1"
$serverText = [System.IO.File]::ReadAllText($serverPath, [System.Text.Encoding]::UTF8)

$oldHttpRead = @'
        $Stream = $Client.GetStream()
        $Stream.ReadTimeout = 4000
        $Reader = New-Object System.IO.StreamReader($Stream, [System.Text.Encoding]::UTF8)

        $RequestLine = $Reader.ReadLine()
        if (-not $RequestLine) {
            $Client.Close()
            continue
        }

        $Parts = $RequestLine -split " "
        $Method = $Parts[0].ToUpper()
        $FullPath = if ($Parts.Count -gt 1) { $Parts[1] } else { "/" }
        $Path = ($FullPath -split "\?")[0]

        # Đọc HTTP Headers
        $ContentLength = 0
        while ($true) {
            $HeaderLine = $Reader.ReadLine()
            if ([string]::IsNullOrEmpty($HeaderLine)) { break }
            if ($HeaderLine -match "^Content-Length:\s*(\d+)") {
                $ContentLength = [int]$Matches[1]
            }
        }

        # Đọc HTTP Body nếu có
        $BodyText = ""
        if ($ContentLength -gt 0) {
            $Buffer = New-Object char[] $ContentLength
            $ReadCount = 0
            while ($ReadCount -lt $ContentLength) {
                $r = $Reader.Read($Buffer, $ReadCount, $ContentLength - $ReadCount)
                if ($r -le 0) { break }
                $ReadCount += $r
            }
            $BodyText = -join $Buffer
        }
'@

$newHttpRead = @'
        $Stream = $Client.GetStream()
        $Stream.ReadTimeout = 5000

        # Đọc HTTP Header từng byte chính xác đến chuỗi ngắt \r\n\r\n
        $headerBytesList = New-Object System.Collections.Generic.List[byte]
        $matchState = 0
        while ($true) {
            $b = $Stream.ReadByte()
            if ($b -lt 0) { break }
            $headerBytesList.Add([byte]$b)
            if ($matchState -eq 0 -and $b -eq 13) { $matchState = 1 }
            elseif ($matchState -eq 1 -and $b -eq 10) { $matchState = 2 }
            elseif ($matchState -eq 2 -and $b -eq 13) { $matchState = 3 }
            elseif ($matchState -eq 3 -and $b -eq 10) { break }
            else { $matchState = if ($b -eq 13) { 1 } else { 0 } }
        }

        if ($headerBytesList.Count -eq 0) {
            $Client.Close()
            continue
        }

        $headerText = [System.Text.Encoding]::UTF8.GetString($headerBytesList.ToArray())
        $headerLines = $headerText -split "\r?\n"
        $RequestLine = $headerLines[0]
        if (-not $RequestLine) {
            $Client.Close()
            continue
        }

        $Parts = $RequestLine -split " "
        $Method = $Parts[0].ToUpper()
        $FullPath = if ($Parts.Count -gt 1) { $Parts[1] } else { "/" }
        $Path = ($FullPath -split "\?")[0]

        # Trích xuất Content-Length
        $ContentLength = 0
        foreach ($hLine in $headerLines) {
            if ($hLine -match "^Content-Length:\s*(\d+)") {
                $ContentLength = [int]$Matches[1]
                break
            }
        }

        # Đọc HTTP Body đúng chính xác số bytes Content-Length (không bị lỗi ký tự đa byte tiếng Việt)
        $BodyText = ""
        if ($ContentLength -gt 0) {
            $BodyBuf = New-Object byte[] $ContentLength
            $BytesRead = 0
            while ($BytesRead -lt $ContentLength) {
                $read = $Stream.Read($BodyBuf, $BytesRead, $ContentLength - $BytesRead)
                if ($read -le 0) { break }
                $BytesRead += $read
            }
            $BodyText = [System.Text.Encoding]::UTF8.GetString($BodyBuf, 0, $BytesRead)
        }
'@

if ($serverText.Contains($oldHttpRead)) {
    $serverText = $serverText.Replace($oldHttpRead, $newHttpRead)
    Write-Host "Replaced HTTP reader with exact byte stream reader in start_server.ps1!"
} else {
    Write-Host "Warning: oldHttpRead not found!"
}

$utf8WithBOM = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($serverPath, $serverText, $utf8WithBOM)
Write-Host "Saved start_server.ps1 successfully."

