# Test script for approvals API
$headers = @{ "Content-Type" = "application/json" }

Write-Host "--- TEST 1: GET /api/approvals ---"
$getRes = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals" -Method GET
Write-Host "Pending count:" $getRes.pending_opportunities.Count
Write-Host "History count:" $getRes.approval_history.Count
if ($getRes.pending_opportunities.Count -gt 0) {
    $targetOpp = $getRes.pending_opportunities[0]
    Write-Host "Found pending target:" $targetOpp.inquiry_id "Status:" $targetOpp.status
} else {
    Write-Host "No pending opp, will check existing opps"
    $opps = Get-Content -Path "data\db\opportunities.json" | ConvertFrom-Json
    $targetOpp = $opps[0]
}

Write-Host "`n--- TEST 2: POST /api/approvals/decide (Approve) ---"
$approvePayload = @{
    inquiry_id = $targetOpp.inquiry_id
    decision = "Approved"
    approver_name = "Hoàng Minh Trí (Trưởng phòng Kinh doanh)"
    note = "Đã xem xét và đồng ý chiết khấu đặc biệt theo thẩm quyền."
} | ConvertTo-Json

$postRes = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals/decide" -Method POST -Headers $headers -Body $approvePayload
Write-Host "POST result success:" $postRes.success
Write-Host "Decision ID:" $postRes.record.decision_id
Write-Host "Updated Opp Status:" $postRes.updated_opportunity.status

Write-Host "`n--- TEST 3: Verify in GET /api/approvals again ---"
$getRes2 = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals" -Method GET
Write-Host "New Pending count:" $getRes2.pending_opportunities.Count
Write-Host "New History count:" $getRes2.approval_history.Count
Write-Host "Last history record:" ($getRes2.approval_history | Select-Object -Last 1 | ConvertTo-Json -Compress)

Write-Host "`n--- TEST 4: Verify in GET /api/audit-logs ---"
$logsRes = Invoke-RestMethod -Uri "http://localhost:8080/api/audit-logs" -Method GET
$lastLog = $logsRes | Select-Object -Last 1
Write-Host "Last audit log step:" $lastLog.step_name "Decision:" $lastLog.decision

Write-Host "`n--- TEST 5: Verify in GET /api/dashboard ---"
$dashRes = Invoke-RestMethod -Uri "http://localhost:8080/api/dashboard" -Method GET
Write-Host "Status Counts:" ($dashRes.status_counts | ConvertTo-Json -Compress)
Write-Host "Total Eligible Value:" $dashRes.total_eligible_value
Write-Host "Total Pending Approval Value:" $dashRes.total_pending_approval_value

