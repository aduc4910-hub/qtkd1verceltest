$headers = @{ "Content-Type" = "application/json" }
$payload1 = @{
    customer_name = "Tập đoàn Viễn thông Viettel Post"
    contact_email = "muasam@viettelpost.com.vn"
    budget = 450000000
    deadline_days = 10
    applied_discount_rate = 0.08
    items = @(
        @{
            product_id = "PROD-002"
            quantity = 3
        },
        @{
            product_id = "PROD-003"
            quantity = 2
        }
    )
} | ConvertTo-Json

$res1 = Invoke-RestMethod -Uri "http://localhost:8080/api/inquiries" -Method POST -Headers $headers -Body $payload1
Write-Host "Inquiry 1 created:" $res1.inquiry_id "Status:" $res1.opportunity.status

$payload2 = @{
    customer_name = "Công ty Cổ phần Chứng khoán SSI"
    contact_email = "it-procurement@ssi.com.vn"
    budget = 600000000
    deadline_days = 15
    applied_discount_rate = 0.12
    items = @(
        @{
            product_id = "PROD-002"
            quantity = 5
        }
    )
} | ConvertTo-Json

$res2 = Invoke-RestMethod -Uri "http://localhost:8080/api/inquiries" -Method POST -Headers $headers -Body $payload2
Write-Host "Inquiry 2 created:" $res2.inquiry_id "Status:" $res2.opportunity.status

