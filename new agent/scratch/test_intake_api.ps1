# Test script for intake API
$ErrorActionPreference = "Stop"

# Test 1: Validation failure (missing customer name)
Write-Host "--- Test 1: Validation Error (Missing Customer Name) ---"
try {
    $badPayload = @{
        customer_name = ""
        contact_email = "test@abc.com"
    } | ConvertTo-Json
    $res1 = Invoke-WebRequest -Uri "http://localhost:8080/api/inquiries" -Method POST -Body $badPayload -ContentType "application/json; charset=utf-8" -UseBasicParsing
    Write-Host "Unexpected Success: $($res1.StatusCode)"
} catch {
    Write-Host "Expected Failure Caught: $($_.Exception.Message)"
}

# Test 2: Valid Inquiry Submission & AI Agent Processing
Write-Host "`n--- Test 2: Valid Inquiry Submission & Pipeline Execution ---"
$validPayload = @{
    inquiry_id = "REQ-TEST-AUTO-99"
    title = "Đơn hàng máy chủ & thiết bị mạng Viễn Đông"
    customer_name = "Công ty TNHH Viễn Đông Tech"
    contact_email = "procurement@viendong.vn"
    raw_text = "Cần mua 2 máy chủ HPE DL380 Gen10 và 1 Cisco Catalyst Switch 24-Port. Ngân sách 200 triệu, chiết khấu 4%, giao hàng trong 10 ngày."
    extracted_data = @{
        customer_name = "Công ty TNHH Viễn Đông Tech"
        contact_email = "procurement@viendong.vn"
        items = @(
            @{ product_id = "PROD-002"; product_name = "Máy chủ HPE ProLiant DL380 Gen10"; quantity = 2 },
            @{ product_id = "PROD-003"; product_name = "Cisco Catalyst Switch 24-Port"; quantity = 1 }
        )
        budget = 200000000
        deadline_days = 10
        requested_discount_rate = 0.04
    }
} | ConvertTo-Json -Depth 6

$res2 = Invoke-WebRequest -Uri "http://localhost:8080/api/inquiries" -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($validPayload)) -ContentType "application/json; charset=utf-8" -UseBasicParsing
Write-Host "Status Code: $($res2.StatusCode)"
$body2 = $res2.Content | ConvertFrom-Json
Write-Host "Success: $($body2.success)"
Write-Host "Inquiry ID: $($body2.inquiry_id)"
Write-Host "Opportunity Status: $($body2.opportunity.status)"
Write-Host "Final Total: $($body2.opportunity.final_total)"
Write-Host "Assigned Rep: $($body2.opportunity.assigned_rep.name)"
Write-Host "Trace Logs Count: $($body2.trace_logs.Count)"

# Test 3: Check Dashboard API
Write-Host "`n--- Test 3: Verify Dashboard API ---"
$resDash = Invoke-WebRequest -Uri "http://localhost:8080/api/dashboard" -Method GET -UseBasicParsing
$dash = $resDash.Content | ConvertFrom-Json
Write-Host "Total Inquiries in DB: $($dash.total_inquiries)"
Write-Host "Total Eligible VND: $($dash.total_eligible_value)"

# Test 4: Check Opportunities API
Write-Host "`n--- Test 4: Verify Opportunities API ---"
$resOpps = Invoke-WebRequest -Uri "http://localhost:8080/api/opportunities" -Method GET -UseBasicParsing
$opps = $resOpps.Content | ConvertFrom-Json
$found = $opps | Where-Object { $_.inquiry_id -eq "REQ-TEST-AUTO-99" }
if ($found) {
    Write-Host "SUCCESS: Found REQ-TEST-AUTO-99 in Opportunities DB!"
    Write-Host "Customer: $($found.customer_name)"
    Write-Host "Status: $($found.status)"
} else {
    Write-Host "ERROR: REQ-TEST-AUTO-99 not found in Opportunities DB!"
}

