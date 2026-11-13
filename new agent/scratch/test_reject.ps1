$headers = @{ "Content-Type" = "application/json" }
$body = @{
    inquiry_id = "REQ-TEST-HITL-01"
    decision = "Rejected"
    approver_name = "Hoàng Minh Trí (Trưởng phòng Kinh doanh)"
    note = "Chiết khấu quá cao 10% và khách hàng không đáp ứng điều kiện bảo lãnh thanh toán."
} | ConvertTo-Json

$res = Invoke-RestMethod -Uri "http://localhost:8080/api/approvals/decide" -Method POST -Headers $headers -Body $body
Write-Host "Success:" $res.success
Write-Host "New Status:" $res.updated_opportunity.status
Write-Host "Approval Decision Text:" $res.updated_opportunity.approval_decision

