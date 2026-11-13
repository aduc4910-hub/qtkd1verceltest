# Test scenario for "Chờ duyệt" (HITL) and "Cần bổ sung"
$ErrorActionPreference = "Stop"

Write-Host "--- Test Scenario A: Large Order (HITL Approval Required) ---"
$hitlPayload = @{
    inquiry_id = "REQ-TEST-HITL-01"
    title = "Gói trang bị Trung tâm dữ liệu An Thịnh"
    customer_name = "Tập đoàn An Thịnh"
    contact_email = "procurement@anthinh.vn"
    raw_text = "Cần mua 8 Máy chủ HPE DL380 và 10 Switch Cisco. Ngân sách 800 triệu, chiết khấu 10%, giao trong 25 ngày."
    extracted_data = @{
        customer_name = "Tập đoàn An Thịnh"
        contact_email = "procurement@anthinh.vn"
        items = @(
            @{ product_id = "PROD-002"; product_name = "Máy chủ HPE ProLiant DL380 Gen10"; quantity = 8 },
            @{ product_id = "PROD-003"; product_name = "Cisco Catalyst Switch 24-Port"; quantity = 10 }
        )
        budget = 800000000
        deadline_days = 25
        requested_discount_rate = 0.10
    }
} | ConvertTo-Json -Depth 6

$resHitl = Invoke-WebRequest -Uri "http://localhost:8080/api/inquiries" -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($hitlPayload)) -ContentType "application/json; charset=utf-8" -UseBasicParsing
$dataHitl = $resHitl.Content | ConvertFrom-Json
Write-Host "HITL Success: $($dataHitl.success)"
Write-Host "Inquiry ID: $($dataHitl.inquiry_id)"
Write-Host "Opportunity Status: $($dataHitl.opportunity.status)"
Write-Host "Final Total: $($dataHitl.opportunity.final_total)"
Write-Host "Has Approval Ticket: $(-not [string]::IsNullOrEmpty($dataHitl.opportunity.approval_ticket))"

# Check /api/approvals
$resApp = Invoke-WebRequest -Uri "http://localhost:8080/api/approvals" -Method GET -UseBasicParsing
$dataApp = $resApp.Content | ConvertFrom-Json
$foundApp = $dataApp.pending_opportunities | Where-Object { $_.inquiry_id -eq "REQ-TEST-HITL-01" }
if ($foundApp) {
    Write-Host "SUCCESS: REQ-TEST-HITL-01 is present in Pending Approvals list!"
} else {
    Write-Host "ERROR: REQ-TEST-HITL-01 not in pending approvals!"
}

# Check /api/audit-logs
$resLogs = Invoke-WebRequest -Uri "http://localhost:8080/api/audit-logs" -Method GET -UseBasicParsing
$dataLogs = $resLogs.Content | ConvertFrom-Json
$logsCount = ($dataLogs | Where-Object { $_.inquiry_id -eq "REQ-TEST-HITL-01" }).Count
Write-Host "SUCCESS: Audit Logs for REQ-TEST-HITL-01: $logsCount entries recorded!"

