$headers = @{ "Content-Type" = "application/json" }

Write-Host "--- TEST REVISION REQUIRED ---"
$getRes = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals" -Method GET
if ($getRes.pending_opportunities.Count -gt 0) {
    $targetOpp = $getRes.pending_opportunities[0]
    Write-Host "Target for Revision:" $targetOpp.inquiry_id
    $revPayload = @{
        inquiry_id = $targetOpp.inquiry_id
        decision = "Revision Required"
        approver_name = "Hoàng Minh Trí (Trưởng phòng Kinh doanh)"
        note = "Yêu cầu đàm phán giảm chiết khấu xuống tối đa 8%."
    } | ConvertTo-Json
    $revRes = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals/decide" -Method POST -Headers $headers -Body $revPayload
    Write-Host "Revision success:" $revRes.success "New Status:" $revRes.updated_opportunity.status
}

Write-Host "`n--- TEST REJECTED ---"
$getRes2 = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals" -Method GET
if ($getRes2.pending_opportunities.Count -gt 0) {
    $targetOpp2 = $getRes2.pending_opportunities[0]
    Write-Host "Target for Reject:" $targetOpp2.inquiry_id
    $rejPayload = @{
        inquiry_id = $targetOpp2.inquiry_id
        decision = "Rejected"
        approver_name = "Hoàng Minh Trí (Trưởng phòng Kinh doanh)"
        note = "Khách hàng nợ xấu hoặc điều khoản không phù hợp."
    } | ConvertTo-Json
    $rejRes = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals/decide" -Method POST -Headers $headers -Body $rejPayload
    Write-Host "Reject success:" $rejRes.success "New Status:" $rejRes.updated_opportunity.status
}

Write-Host "`n--- FINAL VERIFY PENDING APPROVALS ---"
$finalGet = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals" -Method GET
Write-Host "Remaining Pending count:" $finalGet.pending_opportunities.Count
Write-Host "Total History count:" $finalGet.approval_history.Count

