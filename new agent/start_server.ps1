# Native Windows Localhost Server cho Hệ thống AI Agent Minh An (AI301 - Đề 01)
# Sử dụng TcpListener thuần .NET (không phụ thuộc http.sys hay quyền Admin)
# Khởi chạy Web App + REST API tại http://localhost:8080/

param(
    [int]$Port = 8080
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load API & Business Logic Engine
$EnginePath = Join-Path $PSScriptRoot "src\api_engine.ps1"
if (Test-Path $EnginePath) {
    . $EnginePath
    Init-DatabaseIfEmpty
}

New-Item -ItemType Directory -Force -Path "outputs\dossiers", "outputs\drafts", "outputs\logs" | Out-Null

$Endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $Port)
$Listener = New-Object System.Net.Sockets.TcpListener($Endpoint)

try {
    $Listener.Start()
} catch {
    Write-Host "[LỖI] Không thể mở cổng $Port`: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  🚀 MINH AN B2B AI AGENT REST API SERVER ĐANG CHẠY!" -ForegroundColor Green
Write-Host "  🌐 Web App & API: http://localhost:$Port/" -ForegroundColor Yellow
Write-Host "  📂 Cơ sở dữ liệu: $PWD\data\db\" -ForegroundColor Gray
Write-Host "  📂 Thư mục xuất:  $PWD\outputs\" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan

while ($true) {
    $Client = $Listener.AcceptTcpClient()
    try {
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

        $StatusCode = "200 OK"
        $ContentType = "text/html; charset=utf-8"
        $BodyBytes = [byte[]]@()

        # Handle CORS Preflight
        if ($Method -eq "OPTIONS") {
            $StatusCode = "204 No Content"
            $BodyBytes = [byte[]]@()
        }
        # 1. Web App Entry
        elseif ($Path -eq "/" -or $Path -eq "/index.html") {
            $HtmlPath = Join-Path $PWD "web\index.html"
            $BodyBytes = [System.IO.File]::ReadAllBytes($HtmlPath)
            $ContentType = "text/html; charset=utf-8"
        }
        # 1.1 Static Assets (Images, Icons, CSS, JS)
        elseif ($Path.StartsWith("/assets/") -or $Path.EndsWith(".jpg") -or $Path.EndsWith(".png") -or $Path.EndsWith(".svg") -or $Path.EndsWith(".css") -or $Path.EndsWith(".js")) {
            $rel = $Path.TrimStart("/").Replace("/", "\")
            $filePath = Join-Path (Join-Path $PWD "web") $rel
            if (Test-Path $filePath) {
                $BodyBytes = [System.IO.File]::ReadAllBytes($filePath)
                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                if ($ext -eq ".jpg" -or $ext -eq ".jpeg") { $ContentType = "image/jpeg" }
                elseif ($ext -eq ".png") { $ContentType = "image/png" }
                elseif ($ext -eq ".svg") { $ContentType = "image/svg+xml" }
                elseif ($ext -eq ".css") { $ContentType = "text/css; charset=utf-8" }
                elseif ($ext -eq ".js") { $ContentType = "application/javascript; charset=utf-8" }
                else { $ContentType = "application/octet-stream" }
            } else {
                $StatusCode = "404 Not Found"
                $ContentType = "text/plain"
                $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes("File not found")
            }
        }
        # 2. API Status
        elseif ($Path -eq "/api/status") {
            $StatusJson = @{
                status = "online"
                server = "Minh An B2B AI Agent Engine"
                port = $Port
                timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            } | ConvertTo-Json -Compress
            $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($StatusJson)
            $ContentType = "application/json; charset=utf-8"
        }
        # 3. API Dashboard Stats (Tính riêng biệt Có thể tiếp tục và Chờ duyệt)
        elseif ($Path -eq "/api/dashboard") {
            $dash = Get-DashboardSummary
            $json = $dash | ConvertTo-Json -Depth 6
            $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $ContentType = "application/json; charset=utf-8"
        }
        # 4. API Products & Inventory
        elseif ($Path -eq "/api/products") {
            if ($Method -eq "GET") {
                $prods = Read-DbTable "products" @()
                $json = $prods | ConvertTo-Json -Depth 5
                $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $ContentType = "application/json; charset=utf-8"
            } elseif ($Method -eq "POST") {
                try {
                    $item = $BodyText | ConvertFrom-Json
                    $prods = [System.Collections.Generic.List[object]](Read-DbTable "products" @())
                    $found = $false
                    for ($i = 0; $i -lt $prods.Count; $i++) {
                        if ($prods[$i].id -eq $item.id) {
                            if ($null -ne $item.available_stock) { $prods[$i].available_stock = [int]$item.available_stock }
                            if ($null -ne $item.list_price) { $prods[$i].list_price = [double]$item.list_price }
                            $found = $true
                            break
                        }
                    }
                    if (-not $found) { $prods.Add($item) }
                    Save-DbTable "products" $prods
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":true}')
                } catch {
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":false,"error":"' + $_.Exception.Message + '"}')
                }
                $ContentType = "application/json; charset=utf-8"
            }
        }
        # 5. API Policies & Approval Authority
        elseif ($Path -eq "/api/policies") {
            $pol = Read-DbTable "policies" @{}
            $json = $pol | ConvertTo-Json -Depth 6
            $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $ContentType = "application/json; charset=utf-8"
        }
        # 6. API Inquiries (Get list or Ingest new)
        elseif ($Path -eq "/api/inquiries") {
            if ($Method -eq "GET") {
                $inqs = Read-DbTable "inquiries" @()
                $json = $inqs | ConvertTo-Json -Depth 5
                $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $ContentType = "application/json; charset=utf-8"
            } elseif ($Method -eq "POST") {
                try {
                    $payload = if ($BodyText) { $BodyText | ConvertFrom-Json } else { @{} }
                    $currentInqs = [System.Collections.Generic.List[object]](Read-DbTable "inquiries" @())

                    $newItems = @()
                    if ($payload -is [System.Array]) {
                        $newItems = $payload
                    } elseif ($payload.inquiries) {
                        $newItems = $payload.inquiries
                    } else {
                        $newItems = @($payload)
                    }

                    if ($newItems.Count -eq 0) {
                        throw "Dữ liệu yêu cầu rỗng."
                    }

                    # Validate required fields
                    foreach ($chk in $newItems) {
                        if (-not $chk.customer_name -or [string]::IsNullOrWhiteSpace($chk.customer_name)) {
                            throw "Tên khách hàng / doanh nghiệp không được để trống."
                        }
                        if (-not $chk.contact_email -or [string]::IsNullOrWhiteSpace($chk.contact_email)) {
                            throw "Email liên hệ không được để trống."
                        }
                        if ($chk.contact_email -notmatch "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$") {
                            throw "Email liên hệ không đúng định dạng (VD: contact@company.com)."
                        }
                    }

                    $addedCount = 0
                    $pipelineResults = @()
                    foreach ($inq in $newItems) {
                        # Auto ID if missing
                        if (-not $inq.inquiry_id) {
                            $rnd = Get-Random -Minimum 100 -Maximum 999
                            $inq | Add-Member -MemberType NoteProperty -Name "inquiry_id" -Value ("REQ-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + "-$rnd") -Force
                        }
                        # Check duplicate
                        $dup = $false
                        for ($j = 0; $j -lt $currentInqs.Count; $j++) {
                            if ($currentInqs[$j].inquiry_id -eq $inq.inquiry_id) {
                                $currentInqs[$j] = $inq
                                $dup = $true
                                break
                            }
                        }
                        if (-not $dup) {
                            $currentInqs.Add($inq)
                        }
                        $addedCount++

                        # Auto-process via 3-skill AI Agent Pipeline!
                        $res = Invoke-AgentPipeline $inq.inquiry_id $inq
                        $pipelineResults += $res
                    }
                    Save-DbTable "inquiries" $currentInqs

                    # Get updated states
                    $dash = Get-DashboardSummary
                    $allOpps = Read-DbTable "opportunities" @()
                    $targetId = $newItems[0].inquiry_id
                    $latestOpp = $allOpps | Where-Object { $_.inquiry_id -eq $targetId } | Select-Object -Last 1
                    $allLogs = Read-DbTable "audit_logs" @()
                    $inqLogs = $allLogs | Where-Object { $_.inquiry_id -eq $targetId }

                    $resp = @{
                        success = $true
                        message = "Tiếp nhận và AI Agent xử lý thành công hồ sơ $targetId!"
                        inquiry_id = $targetId
                        added_count = $addedCount
                        total = $currentInqs.Count
                        inquiry = $newItems[0]
                        opportunity = $latestOpp
                        dashboard = $dash
                        results = $pipelineResults
                        trace_logs = $inqLogs
                    } | ConvertTo-Json -Depth 6
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
                } catch {
                    $StatusCode = "400 Bad Request"
                    $errJson = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($errJson)
                }
                $ContentType = "application/json; charset=utf-8"
            }
        }
        # 7. API Opportunities (Hồ sơ cơ hội)
        elseif ($Path -eq "/api/opportunities") {
            $opps = Read-DbTable "opportunities" @()
            $json = $opps | ConvertTo-Json -Depth 6
            $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $ContentType = "application/json; charset=utf-8"
        }
        # 8. API Run AI Agent (Kích hoạt 3 Skills)
        elseif ($Path -eq "/api/agent/run" -and $Method -eq "POST") {
            try {
                $req = if ($BodyText) { $BodyText | ConvertFrom-Json } else { @{} }
                $inqId = $req.inquiry_id
                $runAll = $req.run_all

                if ($runAll) {
                    $inquiries = Read-DbTable "inquiries" @()
                    $processed = @()
                    foreach ($inq in $inquiries) {
                        $res = Invoke-AgentPipeline $inq.inquiry_id $inq
                        $processed += $res
                    }
                    $dash = Get-DashboardSummary
                    $resp = @{ success = $true; processed_count = $processed.Count; dashboard = $dash; results = $processed } | ConvertTo-Json -Depth 6
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
                } elseif ($req.inquiry) {
                    # Custom inquiry passed in body
                    $res = Invoke-AgentPipeline $req.inquiry.inquiry_id $req.inquiry
                    $resp = @{ success = $true; result = $res } | ConvertTo-Json -Depth 6
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
                } else {
                    $res = Invoke-AgentPipeline $inqId
                    $resp = @{ success = $true; result = $res } | ConvertTo-Json -Depth 6
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
                }
            } catch {
                $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":false,"error":"' + $_.Exception.Message + '"}')
            }
            $ContentType = "application/json; charset=utf-8"
        }
        # 9. API Approvals (Phê duyệt HITL)
        elseif ($Path -eq "/api/approvals" -or $Path -eq "/api/approvals/decide") {
            if ($Method -eq "GET") {
                $opps = Read-DbTable "opportunities" @()
                $history = Read-DbTable "approvals" @()
                $pending = $opps | Where-Object { 
                    $_.status -like "*Chờ duyệt*" -and 
                    $_.status -notlike "*Đã phê duyệt*" -and 
                    $_.status -notlike "*Từ chối duyệt*" 
                }
                $resp = @{ pending_opportunities = $pending; approval_history = $history } | ConvertTo-Json -Depth 6
                $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
                $ContentType = "application/json; charset=utf-8"
            } elseif ($Method -eq "POST") {
                try {
                    $dec = $BodyText | ConvertFrom-Json
                    $targetId = if ($dec.inquiry_id) { "$($dec.inquiry_id)" } elseif ($dec.opportunity_id) { "$($dec.opportunity_id)" } else { "" }
                    if (-not $targetId) {
                        throw "Thiếu mã yêu cầu / cơ hội (inquiry_id hoặc opportunity_id)."
                    }

                    $rawDecision = if ($dec.decision) { "$($dec.decision)".Trim() } else { "Approved" }
                    $decisionType = "REVISION"
                    if ($rawDecision -match "(?i)(approve|đồng ý|chấp thuận)") {
                        $decisionType = "APPROVED"
                    } elseif ($rawDecision -match "(?i)(reject|từ chối|bác bỏ)") {
                        $decisionType = "REJECTED"
                    } else {
                        $decisionType = "REVISION"
                    }

                    $approverName = if ($dec.approver_name) { "$($dec.approver_name)" } else { "Hoàng Minh Trí (Trưởng phòng Kinh doanh)" }
                    $approverRole = if ($dec.approver_role) { "$($dec.approver_role)" } else { "Trưởng phòng Kinh doanh" }
                    $approvalNote = if ($dec.note) { "$($dec.note)".Trim() } else { "Đã xem xét và phê duyệt theo thẩm quyền" }
                    $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

                    $record = [PSCustomObject]@{
                        decision_id = "DEC-" + (Get-Date).ToString("yyyyMMdd-HHmmss")
                        opportunity_id = $targetId
                        inquiry_id = $targetId
                        decision = $rawDecision
                        decision_type = $decisionType
                        approver_name = $approverName
                        approver_role = $approverRole
                        note = $approvalNote
                        decided_at = $nowStr
                        timestamp = $nowStr
                    }

                    # Update opportunity status
                    $allOpps = [System.Collections.Generic.List[object]](Read-DbTable "opportunities" @())
                    $foundOpp = $null
                    for ($i = 0; $i -lt $allOpps.Count; $i++) {
                        if ($allOpps[$i].inquiry_id -eq $targetId) {
                            $decisionMsg = ""
                            if ($decisionType -eq "APPROVED") {
                                $allOpps[$i].status = "Có thể tiếp tục (Đã phê duyệt)"
                                $decisionMsg = "Đã duyệt bởi $approverName"
                                if ($approvalNote) { $decisionMsg += " - Ghi chú: $approvalNote" }
                            } elseif ($decisionType -eq "REJECTED") {
                                $allOpps[$i].status = "Chưa đáp ứng (Từ chối duyệt)"
                                $decisionMsg = "Từ chối bởi $approverName"
                                if ($approvalNote) { $decisionMsg += " - Lý do: $approvalNote" }
                            } else {
                                $allOpps[$i].status = "Cần bổ sung (Yêu cầu đàm phán lại)"
                                $decisionMsg = "Yêu cầu chỉnh sửa bởi $approverName"
                                if ($approvalNote) { $decisionMsg += ": $approvalNote" }
                            }
                            $allOpps[$i] | Add-Member -MemberType NoteProperty -Name "approval_decision" -Value $decisionMsg -Force
                            $foundOpp = $allOpps[$i]
                            break
                        }
                    }
                    if ($null -ne $foundOpp) {
                        Save-DbTable "opportunities" $allOpps
                    }

                    # Save to approvals.json
                    $approvals = [System.Collections.Generic.List[object]](Read-DbTable "approvals" @())
                    $approvals.Add($record)
                    Save-DbTable "approvals" $approvals

                    $newOppStatus = if ($null -ne $foundOpp) { "$($foundOpp.status)" } else { "Unknown" }

                    # Log to audit_logs
                    $allLogs = [System.Collections.Generic.List[object]](Read-DbTable "audit_logs" @())
                    $allLogs.Add([PSCustomObject]@{
                        inquiry_id = $targetId
                        timestamp = $nowStr
                        step_name = "4. Phê duyệt Ngoại lệ (Human-in-the-Loop)"
                        skill_called = "HITL_approval"
                        tool_called = "manager_decision_action"
                        tool_input = @{
                            inquiry_id = $targetId
                            decision = $rawDecision
                            decision_type = $decisionType
                            approver = $approverName
                            note = $approvalNote
                        }
                        tool_output = @{
                            status = "Thành công"
                            decision_id = $record.decision_id
                            new_opportunity_status = $newOppStatus
                        }
                        rules_applied = "Chính sách thẩm quyền phê duyệt B2B: Chiết khấu > 5% hoặc Giá trị > 200.000.000 VND"
                        decision = "Trưởng phòng ($approverName) ra quyết định [$rawDecision] cho hồ sơ $targetId. Ghi chú: $approvalNote"
                        execution_time_ms = 15
                    })
                    Save-DbTable "audit_logs" $allLogs

                    $respObj = @{
                        success = $true
                        message = "Quyết định phê duyệt đã được lưu thành công"
                        record = $record
                        updated_opportunity = $foundOpp
                    }
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($respObj | ConvertTo-Json -Depth 5))
                    $ContentType = "application/json; charset=utf-8"
                } catch {
                    $StatusCode = "400 Bad Request"
                    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":false,"error":"' + $_.Exception.Message + '"}')
                    $ContentType = "application/json; charset=utf-8"
                }
            }
        }
        # 10. API Audit Logs
        elseif ($Path -eq "/api/audit-logs") {
            $logs = Read-DbTable "audit_logs" @()
            $json = $logs | ConvertTo-Json -Depth 6
            $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $ContentType = "application/json; charset=utf-8"
        }
        # 11. API Automated Test Suite
        elseif ($Path -eq "/api/test/run" -and $Method -eq "POST") {
            try {
                $examData = Read-DbTable "inquiries" @()
                $testResults = @()
                foreach ($inq in $examData) {
                    $r = Invoke-AgentPipeline $inq.inquiry_id $inq
                    $testResults += [PSCustomObject]@{
                        id = $inq.inquiry_id
                        customer = $inq.customer_name
                        status = $r.status
                        total = $r.final_total
                        lead_time = $r.max_lead_time_days
                        approval = $r.approval_required
                    }
                }
                $dash = Get-DashboardSummary
                $resp = @{
                    success = $true
                    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    total_tested = $testResults.Count
                    results = $testResults
                    dashboard = $dash
                } | ConvertTo-Json -Depth 6
                $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
            } catch {
                $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"success":false,"error":"' + $_.Exception.Message + '"}')
            }
            $ContentType = "application/json; charset=utf-8"
        }
        # 12. Legacy save-batch
        elseif ($Path -eq "/api/save-batch" -and $Method -eq "POST") {
            $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"saved":true}')
            $ContentType = "application/json; charset=utf-8"
        }
        else {
            $StatusCode = "404 Not Found"
            $ContentType = "text/plain; charset=utf-8"
            $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
        }

        $HeaderStr = "HTTP/1.1 $StatusCode`r`nContent-Type: $ContentType`r`nContent-Length: $($BodyBytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nConnection: close`r`n`r`n"
        $HeaderBytes = [System.Text.Encoding]::ASCII.GetBytes($HeaderStr)

        $Stream.Write($HeaderBytes, 0, $HeaderBytes.Length)
        if ($BodyBytes.Length -gt 0) {
            $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
        }
        $Stream.Flush()
    } catch {
        # Client disconnect or timeout
    } finally {
        $Client.Close()
    }
}
