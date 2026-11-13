# PowerShell Native Runner cho B2B Sales Opportunity Processing Agent
# Đồ án AI301 | Đề 01 - Công ty Minh An
# Chạy trực tiếp trên mọi máy tính Windows mà không cần cài thêm Python

param(
    [string]$DataPath = "data\test_inquiries.json"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "     HỆ THỐNG AI AGENT XỬ LÝ CƠ HỘI BÁN HÀNG B2B - CÔNG TY MINH AN" -ForegroundColor Yellow
Write-Host "     Môn học: AI301 | Đề 01 | Bộ điều phối Agent (Native PowerShell Engine)" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Đọc Master Data & Policies
if (-not (Test-Path $DataPath)) {
    Write-Host "[LỖI] Không tìm thấy tệp: $DataPath" -ForegroundColor Red
    exit 1
}

$Products = Get-Content -Raw -Encoding UTF8 "data\products_inventory.json" | ConvertFrom-Json
$Policies = Get-Content -Raw -Encoding UTF8 "data\business_policies.json" | ConvertFrom-Json
$Inquiries = Get-Content -Raw -Encoding UTF8 $DataPath | ConvertFrom-Json

Write-Host "-> Đã nạp $($Products.Count) sản phẩm từ Bảng giá & Tồn kho hiện hành." -ForegroundColor Gray
Write-Host "-> Đã nạp Quy tắc Chiết khấu & Ma trận Thẩm quyền phê duyệt." -ForegroundColor Gray
Write-Host "-> Bắt đầu xử lý $($Inquiries.Count) yêu cầu từ: $DataPath`n" -ForegroundColor Gray

# Chuẩn bị thư mục đầu ra
New-Item -ItemType Directory -Force -Path "outputs\dossiers", "outputs\drafts", "outputs\logs" | Out-Null

$SalesReps = $Policies.sales_reps
$RepIndex = 0

$StatusCounts = @{
    "Có thể tiếp tục" = 0
    "Cần bổ sung thông tin" = 0
    "Chưa đáp ứng" = 0
    "Chờ duyệt" = 0
}
$TotalEligibleValue = 0.0
$Results = @()

# Hàm tra cứu sản phẩm
function Match-Product($name, $id) {
    if ($id) {
        $p = $Products | Where-Object { $_.id -eq $id }
        if ($p) { return $p }
    }
    $nLower = $name.ToLower()
    foreach ($p in $Products) {
        if ($p.name.ToLower().Contains($nLower) -or $nLower.Contains($p.name.ToLower())) {
            return $p
        }
    }
    # Tìm kiếm theo từ khóa
    foreach ($p in $Products) {
        if ($nLower -match "dell" -and $p.name -match "dell") { return $p }
        if ($nLower -match "hpe" -and $p.name -match "hpe") { return $p }
        if ($nLower -match "switch" -and $p.name -match "switch") { return $p }
        if ($nLower -match "wifi" -and $p.name -match "wifi") { return $p }
        if ($nLower -match "dịch vụ" -and $p.name -match "dịch vụ") { return $p }
    }
    return $null
}

# Hàm trích xuất tự động từ văn bản thô tiếng Việt (NLP Heuristic/Regex) khi đề thi không có sẵn extracted_data
function Parse-RawTextVietnamese($rawText, $custName, $contactEmail) {
    $textLower = if ($rawText) { $rawText.ToLower() } else { "" }
    $items = @()

    $patterns = @(
        @{ id = "PROD-001"; name = "Laptop Dell Latitude 5540"; regex = "(\d+)\s*(?:chiếc\s*|máy\s*|bộ\s*)?(?:laptop\s*)?(?:dell|latitude\s*5540)" },
        @{ id = "PROD-002"; name = "Máy chủ HPE ProLiant DL380 Gen10"; regex = "(\d+)\s*(?:chiếc\s*|máy\s*|bộ\s*)?(?:máy\s*chủ\s*|server\s*)?(?:hpe|proliant|dl380)" },
        @{ id = "PROD-003"; name = "Cisco Catalyst Switch 24-Port"; regex = "(\d+)\s*(?:chiếc\s*|bộ\s*|cái\s*)?(?:switch\s*cisco|cisco\s*catalyst|switch\s*24-port)" },
        @{ id = "PROD-004"; name = "Bộ phát WiFi 6 Cisco Business 150AX"; regex = "(\d+)\s*(?:chiếc\s*|bộ\s*|cái\s*)?(?:bộ\s*phát\s*)?(?:wifi\s*6?\s*cisco|cisco\s*business\s*150ax|wifi\s*150ax)" },
        @{ id = "PROD-005"; name = "Dịch vụ Triển khai Cài đặt"; regex = "(\d+)\s*(?:gói\s*)?(?:dịch\s*vụ\s*triển\s*khai|dịch\s*vụ\s*cài\s*đặt|gói\s*dịch\s*vụ)" }
    )

    foreach ($p in $patterns) {
        if ($textLower -match $p.regex) {
            $items += [PSCustomObject]@{
                product_id = $p.id
                product_name = $p.name
                quantity = [int]$Matches[1]
            }
        }
    }

    $budget = $null
    if ($textLower -notmatch "chưa\s*(?:chốt|rõ|xác\s*định|có)\s*ngân\s*sách") {
        if ($textLower -match "(?:ngân\s*sách|kinh\s*phí)[^0-9]{0,40}?(\d+(?:[\.,]\d+)?)\s*(?:triệu|tr\b|m\b)") {
            $val = [double]($Matches[1] -replace ",", ".")
            $budget = $val * 1000000
        }
    }

    $deadlineDays = $null
    if ($textLower -notmatch "(?:thời\s*gian|thời\s*hạn)[^.]*chưa\s*xác\s*định") {
        if ($textLower -match "(?:trong\s*vòng|trong|bàn\s*giao|giao\s*hàng|thời\s*hạn)[^0-9]{0,25}?(\d+)\s*ngày") {
            $deadlineDays = [int]$Matches[1]
        } elseif ($textLower -match "trong tuần này|1 tuần") {
            $deadlineDays = 7
        }
    }

    $reqDiscount = 0.0
    if ($textLower -match "(?:chiết\s*khấu|giảm\s*giá|ưu\s*đãi)[^0-9]{0,25}?(\d+(?:[\.,]\d+)?)\s*%") {
        $reqDiscount = ([double]($Matches[1] -replace ",", ".")) / 100.0
    }

    return [PSCustomObject]@{
        customer_name = if ($custName) { $custName } else { "Khách hàng Doanh nghiệp" }
        contact_email = if ($contactEmail) { $contactEmail } else { "contact@enterprise.vn" }
        items = $items
        budget = $budget
        deadline_days = $deadlineDays
        requested_discount_rate = $reqDiscount
    }
}

# Vòng lặp xử lý từng cơ hội
$idx = 0
foreach ($inq in $Inquiries) {
    $idx++
    $inqId = if ($inq.inquiry_id) { $inq.inquiry_id } else { "REQ-$idx" }
    $custName = if ($inq.customer_name) { $inq.customer_name } else { "Không rõ" }
    $ext = if ($inq.extracted_data) { $inq.extracted_data } else { Parse-RawTextVietnamese $inq.raw_text $custName $inq.contact_email }

    # Phân công NVKD (Round-robin)
    $assignedRep = $SalesReps[$RepIndex % $SalesReps.Count]
    $RepIndex++

    Write-Host "[$idx/$($Inquiries.Count)] Đang xử lý $inqId - $custName" -ForegroundColor White
    Write-Host "    Phân loại test: $($inq.case_category)" -ForegroundColor DarkGray

    # Audit Trace Log
    $traceSteps = @()

    # =========================================================================
    # BƯỚC 1: TIẾP NHẬN & KIỂM TRA TÍNH ĐẦY ĐỦ
    # =========================================================================
    $missingFields = @()
    if (-not $ext.customer_name) { $missingFields += "Tên khách hàng" }
    if (-not $ext.contact_email) { $missingFields += "Email liên hệ" }
    if (-not $ext.items -or $ext.items.Count -eq 0) {
        $missingFields += "Danh mục sản phẩm"
    } else {
        foreach ($item in $ext.items) {
            if (-not $item.quantity -or $item.quantity -le 0) {
                $missingFields += "Số lượng sản phẩm ($($item.product_name))"
            }
        }
    }
    if ($null -eq $ext.budget) { $missingFields += "Ngân sách dự kiến (budget)" }
    if ($null -eq $ext.deadline_days) { $missingFields += "Thời hạn triển khai mong muốn (deadline_days)" }

    $step1Thought = "Agent tiếp nhận yêu cầu $inqId từ $custName. Kiểm tra các trường bắt buộc theo chính sách công ty."
    
    if ($missingFields.Count -gt 0) {
        $status = "Cần bổ sung thông tin"
        $decision1 = "Yêu cầu THIẾU THÔNG TIN: $($missingFields -join ', '). Rẽ nhánh: Gửi email yêu cầu KH làm rõ/bổ sung."
        
        $traceSteps += [PSCustomObject]@{
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            step = "1. Phân loại & Kiểm tra thông tin"
            thought = $step1Thought
            tool_called = "tool_extract_and_validate"
            tool_output = @{ is_complete = $false; missing_fields = $missingFields }
            rule_applied = "Chính sách kiểm tra 5 trường bắt buộc (Customer, Email, Items, Budget, Deadline)"
            decision = $decision1
        }

        # Soạn bản nháp email xin bổ sung
        $missingListStr = ($missingFields | ForEach-Object { "- $_" }) -join "`r`n"
        $draftResponse = @"
Kính gửi Quý Khách hàng ($custName),

Công ty Cổ phần Công nghệ Minh An xin chân thành cảm ơn Quý đơn vị đã gửi yêu cầu chào giá.

Để hoàn thiện Hồ sơ Báo giá và phương án kỹ thuật tối ưu nhất cho Quý khách, chúng tôi kính đề nghị Quý khách vui lòng cung cấp hoặc làm rõ thêm một số thông tin sau:
$missingListStr

Sau khi nhận được thông tin bổ sung, chuyên viên kinh doanh của Minh An sẽ gửi Báo giá chi tiết trong vòng 04 giờ làm việc.

Trân trọng cảm ơn,
Chuyên viên phụ trách: $($assignedRep.name) ($($assignedRep.email))
Phòng Kinh doanh - Công ty Cổ phần Công nghệ Minh An
"@

        $dossierMd = @"
# HỒ SƠ CƠ HỘI BÁN HÀNG B2B (OPPORTUNITY DOSSIER)
- Mã hồ sơ: $inqId
- Khách hàng: $custName
- Trạng thái phân loại: **$status**
- Nhân viên phụ trách: $($assignedRep.name) ($($assignedRep.email))

## 1. Kết quả Phân loại & Xác thực dữ liệu:
- Tính đầy đủ: THIẾU THÔNG TIN
- Các trường còn thiếu: $($missingFields -join ', ')
- Ngân sách: Chưa xác định
- Thời hạn mong muốn: Chưa xác định

## 2. Bước xử lý tiếp theo (Next Action):
- NVKD kiểm tra bản nháp email và gửi khách hàng đề nghị làm rõ thông tin.
- Hệ thống đánh dấu 'Chờ khách hàng bổ sung' và theo dõi lại trong 24h.
"@

        Set-Content -Path "outputs\dossiers\dossier_$inqId.md" -Value $dossierMd -Encoding UTF8
        Set-Content -Path "outputs\drafts\draft_response_$inqId.txt" -Value $draftResponse -Encoding UTF8

        # Xuất Nhật ký truy vết cho trường hợp thiếu thông tin
        $traceLogStr = @"
# NHẬT KÝ TRUY VẾT THỰC THI AGENT (AUDIT TRACE) - $inqId
Thời gian thực thi: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
======================================================================
### BƯỚC 1: 1. Phân loại & Kiểm tra thông tin
- **Thời gian:** $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
- **Agent Thought (Suy luận):** $step1Thought
- **Tool Called (Công cụ gọi):** tool_extract_and_validate
- **Tool Output:** {"is_complete": false, "missing_fields": $($missingFields | ConvertTo-Json -Compress)}
- **Quy tắc áp dụng:** Chính sách kiểm tra 5 trường bắt buộc (Customer, Email, Items, Budget, Deadline)
- **Quyết định:** $decision1
--------------------------------------------------
"@
        Set-Content -Path "outputs\logs\trace_$inqId.txt" -Value $traceLogStr -Encoding UTF8

        $StatusCounts[$status]++
        Write-Host "    => Trạng thái: [$status] (Thiếu: $($missingFields -join ', '))" -ForegroundColor Yellow

        $Results += [PSCustomObject]@{
            inquiry_id = $inqId
            customer_name = $custName
            status = $status
            final_total = 0.0
            assigned_rep = $assignedRep.name
            summary = $decision1
        }
        continue
    }

    # Nếu ĐẦY ĐỦ dữ liệu
    $traceSteps += [PSCustomObject]@{
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        step = "1. Phân loại & Kiểm tra thông tin"
        thought = $step1Thought
        tool_called = "tool_extract_and_validate"
        tool_output = @{ is_complete = $true; items_count = $ext.items.Count }
        rule_applied = "Kiểm tra hợp lệ đầy đủ 5 trường thiết yếu"
        decision = "Đủ thông tin. Chuyển sang bước Tạo Hồ sơ Cơ hội & Thẩm định tồn kho & giá."
    }

    # =========================================================================
    # BƯỚC 2: THẨM ĐỊNH TỒN KHO & LEAD TIME (VẬN HÀNH)
    # =========================================================================
    $stockAll = $true
    $maxRequiredLeadTime = 0
    $feasibilityReasons = @()
    $parsedItems = @()

    foreach ($item in $ext.items) {
        $prod = Match-Product $item.product_name $item.product_id
        if (-not $prod) {
            $feasibilityReasons += "Sản phẩm '$($item.product_name)' không tồn tại trong danh mục."
            $stockAll = $false
            continue
        }
        $lineTotal = [double]$prod.list_price * [int]$item.quantity
        $itemStockSuff = ($prod.available_stock -ge $item.quantity)
        $leadTime = if ($itemStockSuff) { $prod.ready_lead_time_days } else { $prod.restock_lead_time_days }
        if (-not $itemStockSuff) {
            $stockAll = $false
            $shortage = $item.quantity - $prod.available_stock
            $feasibilityReasons += "$($prod.name): Thiếu $shortage chiếc (kho có $($prod.available_stock)/$($item.quantity)). Cần đặt hàng bổ sung với lead time $leadTime ngày."
        } else {
            $feasibilityReasons += "$($prod.name): Tồn kho đủ ($($prod.available_stock) >= $($item.quantity)), lead time giao sẵn $leadTime ngày."
        }
        if ($leadTime -gt $maxRequiredLeadTime) {
            $maxRequiredLeadTime = $leadTime
        }
        $parsedItems += [PSCustomObject]@{
            id = $prod.id
            name = $prod.name
            quantity = $item.quantity
            list_price = $prod.list_price
            line_total = $lineTotal
            stock_suff = $itemStockSuff
        }
    }

    $leadTimeMet = ($ext.deadline_days -ge $maxRequiredLeadTime)
    if (-not $leadTimeMet) {
        $feasibilityReasons += "VI PHẠM TIẾN ĐỘ: Khách yêu cầu $ext.deadline_days ngày, nhưng thời gian nhập/chuẩn bị hàng cần tối thiểu $maxRequiredLeadTime ngày."
    } else {
        $feasibilityReasons += "ĐÁP ỨNG TIẾN ĐỘ: Thời gian đáp ứng của công ty ($maxRequiredLeadTime ngày) nằm trong hạn mức yêu cầu ($($ext.deadline_days) ngày)."
    }

    $isFeasible = $leadTimeMet

    # =========================================================================
    # BƯỚC 3: ĐỊNH GIÁ & CHÍNH SÁCH CHIẾT KHẤU & THẨM QUYỀN
    # =========================================================================
    $listTotal = ($parsedItems | Measure-Object -Property line_total -Sum).Sum
    $standardDiscount = 0.0
    foreach ($tier in $Policies.volume_discount_policy) {
        if ($listTotal -ge $tier.min_amount -and $listTotal -lt $tier.max_amount) {
            $standardDiscount = [double]$tier.max_discount_rate
            break
        }
    }

    $reqDiscount = if ($ext.requested_discount_rate) { [double]$ext.requested_discount_rate } else { 0.0 }
    $appliedDiscount = $reqDiscount
    $approvalReasons = @()
    $requiresApproval = $false

    if ($reqDiscount -gt $standardDiscount) {
        $approvalReasons += "Chiết khấu yêu cầu ($($reqDiscount*100)%) vượt khung tiêu chuẩn theo quy mô đơn hàng ($($standardDiscount*100)%)."
        $requiresApproval = $true
    }
    if ($reqDiscount -gt [double]$Policies.approval_authority_matrix.sales_rep.max_discount_rate) {
        $approvalReasons += "Chiết khấu yêu cầu ($($reqDiscount*100)%) vượt hạn mức tối đa của NVKD (10%)."
        $requiresApproval = $true
    }
    if ($listTotal -gt [double]$Policies.approval_authority_matrix.sales_rep.max_order_amount) {
        $approvalReasons += "Tổng giá trị đơn hàng ($('{0:N0}' -f $listTotal) VND) vượt thẩm quyền tự quyết của NVKD (200,000,000 VND)."
        $requiresApproval = $true
    }

    $discountAmount = $listTotal * $appliedDiscount
    $finalTotal = $listTotal - $discountAmount

    # Kiểm tra ngân sách
    $withinBudget = ($ext.budget -ge $finalTotal)
    $lowestAcceptable = $listTotal * (1 - [double]$Policies.approval_authority_matrix.sales_manager.max_discount_rate)
    $budgetImpossible = ($ext.budget -lt $lowestAcceptable)

    if ($budgetImpossible) {
        $approvalReasons += "NGÂN SÁCH KHÔNG KHẢ THI: Ngân sách khách ($('{0:N0}' -f $ext.budget) VND) thấp hơn giá sàn tối thiểu sau chiết khấu kịch trần 15% ($('{0:N0}' -f $lowestAcceptable) VND)."
    }

    # =========================================================================
    # BƯỚC 4: PHÂN LUỒNG QUYẾT ĐỊNH
    # =========================================================================
    $approvalTicket = $null
    if (-not $isFeasible -or $budgetImpossible) {
        $status = "Chưa đáp ứng"
        $decisionFinal = "Yêu cầu không khả thi do vi phạm thời hạn giao hàng hoặc ngân sách không đạt giá sàn."
    } elseif ($requiresApproval) {
        $status = "Chờ duyệt"
        $decisionFinal = "Yêu cầu khả thi nhưng vượt thẩm quyền NVKD ($($approvalReasons -join '; ')). Chuyển Trưởng phòng duyệt."
    } else {
        $status = "Có thể tiếp tục"
        $decisionFinal = "Yêu cầu hợp lệ, đủ hàng/thời hạn và trong hạn mức thẩm quyền của NVKD."
    }

    $traceSteps += [PSCustomObject]@{
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        step = "2. Thẩm định tồn kho & giá"
        thought = "Thẩm định tồn kho và đối chiếu lead time, áp dụng chính sách chiết khấu và kiểm tra thẩm quyền."
        tool_called = "tool_assess_inventory_and_leadtime + tool_calculate_pricing_and_authority"
        tool_output = @{
            is_feasible = $isFeasible
            list_total = $listTotal
            final_total = $finalTotal
            requires_approval = $requiresApproval
            status = $status
        }
        rule_applied = "Bảng giá niêm yết hiện hành; Khung chiết khấu bậc thang; Ma trận thẩm quyền NVKD & Quản lý"
        decision = $decisionFinal
    }

    # =========================================================================
    # BƯỚC 5: TẠO HỒ SƠ & BẢN NHÁP PHẢN HỒI
    # =========================================================================
    $itemsTableStr = ($parsedItems | ForEach-Object {
        "  + $($_.name) | SL: $($_.quantity) | Đơn giá: $('{0:N0}' -f $_.list_price) VND | Thành tiền: $('{0:N0}' -f $_.line_total) VND"
    }) -join "`r`n"

    $feasibilityReasonsStr = ($feasibilityReasons | ForEach-Object { "  * $_" }) -join "`r`n"
    $approvalReasonsStr = ($approvalReasons | ForEach-Object { "- $_" }) -join "`r`n"

    $dossierMd = @"
# HỒ SƠ CƠ HỘI BÁN HÀNG B2B (OPPORTUNITY DOSSIER)
- Mã hồ sơ: $inqId
- Khách hàng: $custName
- Email liên hệ: $($ext.contact_email)
- Trạng thái phân loại: **$status**
- Nhân viên phụ trách: $($assignedRep.name) ($($assignedRep.email))

## 1. Kết quả Phân loại & Xác thực dữ liệu:
- Tính đầy đủ: ĐẦY ĐỦ
- Ngân sách khai báo: $('{0:N0}' -f $ext.budget) VND
- Thời hạn mong muốn: $($ext.deadline_days) ngày

## 2. Kết quả Thẩm định Tồn kho & Thời gian triển khai (Vận hành):
- Khả thi cung ứng: $(if ($isFeasible) { 'KHẢ THI' } else { 'KHÔNG KHẢ THI' })
- Tồn kho: $(if ($stockAll) { 'Đủ toàn bộ hạng mục' } else { 'Có hạng mục cần đặt hàng' })
- Thời gian đáp ứng giao hàng: $maxRequiredLeadTime ngày
- Chi tiết đối chiếu:
$feasibilityReasonsStr

## 3. Kết quả Thẩm định Giá & Chính sách Chiết khấu:
- Tổng giá niêm yết: $('{0:N0}' -f $listTotal) VND
- Chiết khấu áp dụng: $($appliedDiscount*100)% (-$('{0:N0}' -f $discountAmount) VND)
- Giá trị đề xuất sau chiết khấu: $('{0:N0}' -f $finalTotal) VND
- Người phê duyệt có thẩm quyền: $(if ($requiresApproval) { 'Trưởng phòng Kinh doanh' } else { 'NVKD tự duyệt' })
- Đánh giá ngân sách: $(if ($withinBudget) { 'Trong hạn mức ngân sách' } else { 'Thấp hơn giá chào' })

## 4. Căn cứ Quy tắc Nghiệp vụ áp dụng:
$approvalReasonsStr

## 5. Bước xử lý tiếp theo (Next Action):
$(if ($status -eq 'Chờ duyệt') {
    "- NVKD chuyển Escalation Ticket lên Trưởng phòng Kinh doanh duyệt chiết khấu/deal size trước khi gửi khách."
} elseif ($status -eq 'Có thể tiếp tục') {
    "- NVKD kiểm tra bản nháp báo giá và gửi chính thức cho khách hàng."
} else {
    "- Gửi email thông báo từ chối lịch sự và tư vấn phương án điều chỉnh tiến độ hoặc cấu hình."
})
"@

    # Soạn thảo Draft Email phản hồi khách hàng
    if ($status -eq "Chưa đáp ứng") {
        $draftResponse = @"
Kính gửi Quý Khách hàng ($custName),

Công ty Cổ phần Công nghệ Minh An xin trân trọng cảm ơn sự quan tâm của Quý khách đối với thiết bị và giải pháp của chúng tôi.

Sau khi rà soát khả năng cung ứng và chính sách giá, chúng tôi rất tiếc phải thông báo hiện tại chưa thể đáp ứng ngay yêu cầu của Quý khách do:
$feasibilityReasonsStr
$approvalReasonsStr

Chúng tôi xin đề xuất hai phương án giải quyết:
1. Điều chỉnh thời gian giao hàng lên $maxRequiredLeadTime ngày để bộ phận Cung ứng hoàn tất nhập hàng.
2. Điều chỉnh lại cấu hình thiết bị để tối ưu hóa ngân sách.

Chuyên viên $($assignedRep.name) ($($assignedRep.email)) sẽ chủ động liên hệ Quý khách để hỗ trợ phương án tốt nhất.

Trân trọng,
Công ty Cổ phần Công nghệ Minh An
"@
    } elseif ($status -eq "Chờ duyệt") {
        $draftResponse = @"
[BẢN NHÁP BÁO GIÁ - CHỜ TRƯỞNG PHÒNG DUYỆT TRƯỚC KHI GỬI CHÍNH THỨC]
Kính gửi Quý Khách hàng ($custName),

Công ty Minh An trân trọng gửi Quý khách Dự thảo Báo giá sơ bộ:
- Danh mục hạng mục:
$itemsTableStr
- Tổng giá niêm yết: $('{0:N0}' -f $listTotal) VND
- Chiết khấu đề xuất ($($appliedDiscount*100)%): -$('{0:N0}' -f $discountAmount) VND
- TỔNG THANH TOÁN: $('{0:N0}' -f $finalTotal) VND
- Thời gian giao hàng: $maxRequiredLeadTime ngày làm việc.

(Báo giá chính thức có chữ ký duyệt sẽ được gửi tới Quý khách ngay sau khi Trưởng phòng Kinh doanh hoàn tất phê duyệt).

Người lập: $($assignedRep.name) ($($assignedRep.email))
Phòng Kinh doanh - Công ty Cổ phần Công nghệ Minh An
"@

        $approvalTicket = @"
======================================================================
PHIẾU CHUYỂN DUYỆT CƠ HỘI BÁN HÀNG VƯỢT THẨM QUYỀN (ESCALATION TICKET)
Mã yêu cầu: $inqId | Khách hàng: $custName
NVKD phụ trách: $($assignedRep.name) ($($assignedRep.email))
Người nhận phê duyệt: Hoàng Minh Trí - Trưởng phòng Kinh doanh
----------------------------------------------------------------------
1. THÔNG SỐ TÀI CHÍNH & VẬN HÀNH:
   - Tổng giá niêm yết: $('{0:N0}' -f $listTotal) VND
   - Mức chiết khấu xin duyệt: $($appliedDiscount*100)% (-$('{0:N0}' -f $discountAmount) VND)
   - Doanh thu dự kiến: $('{0:N0}' -f $finalTotal) VND
   - Ngân sách khách hàng: $('{0:N0}' -f $ext.budget) VND
   - Thời gian giao hàng cam kết: $maxRequiredLeadTime ngày (Hạn yêu cầu: $($ext.deadline_days) ngày)

2. CĂN CỨ VƯỢT THẨM QUYỀN CẦN DUYỆT:
$approvalReasonsStr

3. ĐỀ XUẤT CỦA NVKD & AGENT:
   - Kính đề nghị Trưởng phòng phê duyệt để tiến hành ký kết hợp đồng.
======================================================================
"@
        Set-Content -Path "outputs\drafts\approval_ticket_$inqId.txt" -Value $approvalTicket -Encoding UTF8
    } else {
        # READY - Có thể tiếp tục
        $draftResponse = @"
Kính gửi Quý Khách hàng ($custName),

Công ty Cổ phần Công nghệ Minh An trân trọng gửi tới Quý khách Bản Báo giá và Kế hoạch triển khai cho yêu cầu mã ${inqId}:

1. DANH MỤC THIẾT BỊ & DỊCH VỤ:
$itemsTableStr

2. CHÍNH SÁCH GIÁ & THANH TOÁN:
- Tổng giá niêm yết: $('{0:N0}' -f $listTotal) VND
- Chiết khấu doanh nghiệp ($($appliedDiscount*100)%): -$('{0:N0}' -f $discountAmount) VND
- TỔNG CỘNG THANH TOÁN: $('{0:N0}' -f $finalTotal) VND (Chưa gồm VAT)
- Ngân sách Quý khách: $('{0:N0}' -f $ext.budget) VND (Thỏa mãn)

3. THỜI GIAN VÀ ĐIỀU KIỆN GIAO HÀNG:
- Tình trạng hàng: Có sẵn đầy đủ trong kho Minh An.
- Thời gian giao hàng: $maxRequiredLeadTime ngày làm việc kể từ ngày ký hợp đồng.

Báo giá có hiệu lực trong vòng 15 ngày. NVKD phụ trách sẽ liên hệ hỗ trợ hợp đồng.

Trân trọng kính thư,
Chuyên viên: $($assignedRep.name) ($($assignedRep.email))
Công ty Cổ phần Công nghệ Minh An
"@
    }

    Set-Content -Path "outputs\dossiers\dossier_$inqId.md" -Value $dossierMd -Encoding UTF8
    Set-Content -Path "outputs\drafts\draft_response_$inqId.txt" -Value $draftResponse -Encoding UTF8

    # Xuất Nhật ký truy vết (Trace Log)
    $traceLogStr = @"
# NHẬT KÝ TRUY VẾT THỰC THI AGENT (AUDIT TRACE) - $inqId
Thời gian thực thi: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
======================================================================
"@
    $stepNum = 0
    foreach ($st in $traceSteps) {
        $stepNum++
        $sStep = $st.step
        $sTime = $st.timestamp
        $sThought = $st.thought
        $sTool = $st.tool_called
        $sOutput = $st.tool_output | ConvertTo-Json -Compress
        $sRule = $st.rule_applied
        $sDecision = $st.decision

        $traceLogStr += "`r`n`r`n### BƯỚC $stepNum`: $sStep`r`n"
        $traceLogStr += "- **Thời gian:** $sTime`r`n"
        $traceLogStr += "- **Agent Thought (Suy luận):** $sThought`r`n"
        $traceLogStr += "- **Tool Called (Công cụ gọi):** $sTool`r`n"
        $traceLogStr += "- **Tool Output:** $sOutput`r`n"
        $traceLogStr += "- **Quy tắc áp dụng:** $sRule`r`n"
        $traceLogStr += "- **Quyết định:** $sDecision`r`n"
        $traceLogStr += "--------------------------------------------------"
    }
    Set-Content -Path "outputs\logs\trace_$inqId.txt" -Value $traceLogStr -Encoding UTF8

    $StatusCounts[$status]++

    if ($status -eq "Có thể tiếp tục" -or $status -eq "Chờ duyệt") {
        $TotalEligibleValue += $finalTotal
        Write-Host "    => Trạng thái: [$status] | Giá trị: $('{0:N0}' -f $finalTotal) VND | Phụ trách: $($assignedRep.name)" -ForegroundColor Green
    } else {
        Write-Host "    => Trạng thái: [$status] | Phụ trách: $($assignedRep.name)" -ForegroundColor Red
    }

    $Results += [PSCustomObject]@{
        inquiry_id = $inqId
        customer_name = $custName
        status = $status
        final_total = if ($status -eq "Có thể tiếp tục" -or $status -eq "Chờ duyệt") { $finalTotal } else { 0.0 }
        assigned_rep = $assignedRep.name
        summary = $decisionFinal
    }
}

# =============================================================================
# TỔNG HỢP KẾT QUẢ & XUẤT DASHBOARD
# =============================================================================
$summaryObj = [PSCustomObject]@{
    total_inquiries = $Inquiries.Count
    status_breakdown = $StatusCounts
    total_eligible_pipeline_value_vnd = $TotalEligibleValue
    currency = "VND"
    detailed_results = $Results
}
$summaryObj | ConvertTo-Json -Depth 5 | Set-Content -Path "outputs\summary_dashboard.json" -Encoding UTF8

$dashboardMd = @"
# BẢNG TỔNG HỢP KẾT QUẢ XỬ LÝ CƠ HỘI BÁN HÀNG B2B - CÔNG TY MINH AN
- Bộ dữ liệu nguồn: `${DataPath}`
- Tổng số yêu cầu tiếp nhận: $($Inquiries.Count)

| Phân loại trạng thái | Số lượng cơ hội | Tỷ lệ (%) | Hành động tiếp theo |
|---|---|---|---|
| **Có thể tiếp tục (Qualified / Ready)** | **$($StatusCounts['Có thể tiếp tục'])** | $([math]::Round($StatusCounts['Có thể tiếp tục'] / $Inquiries.Count * 100, 1))% | NVKD kiểm tra bản nháp & phát hành báo giá |
| **Cần bổ sung thông tin (Need Info)** | **$($StatusCounts['Cần bổ sung thông tin'])** | $([math]::Round($StatusCounts['Cần bổ sung thông tin'] / $Inquiries.Count * 100, 1))% | Gửi email nháp đề nghị khách hàng làm rõ |
| **Chưa đáp ứng (Unfulfillable)** | **$($StatusCounts['Chưa đáp ứng'])** | $([math]::Round($StatusCounts['Chưa đáp ứng'] / $Inquiries.Count * 100, 1))% | Gửi email từ chối lịch sự & tư vấn giải pháp |
| **Chờ duyệt (Pending Approval)** | **$($StatusCounts['Chờ duyệt'])** | $([math]::Round($StatusCounts['Chờ duyệt'] / $Inquiries.Count * 100, 1))% | Chuyển phiếu duyệt Escalation Ticket cho Trưởng phòng |
| **TỔNG CỘNG** | **$($Inquiries.Count)** | 100% | Phân bổ đều giữa 6 NVKD theo cơ chế Round-robin |

### TỔNG GIÁ TRỊ CƠ HỘI ĐỦ ĐIỀU KIỆN TIẾP TỤC HOẶC CHỜ DUYỆT:
> **$('{0:N0}' -f $TotalEligibleValue) VND**

### CHI TIẾT CÁC CƠ HỘI:
| Mã YC | Khách hàng | Trạng thái | Giá trị đề xuất (VND) | NVKD phụ trách | Tóm tắt căn cứ |
|---|---|---|---|---|---|
"@
foreach ($r in $Results) {
    $valStr = if ($r.final_total -gt 0) { ('{0:N0}' -f $r.final_total) } else { "-" }
    $dashboardMd += "`r`n| $($r.inquiry_id) | $($r.customer_name) | **$($r.status)** | $valStr | $($r.assigned_rep) | $($r.summary) |"
}
Set-Content -Path "outputs\summary_dashboard.md" -Value $dashboardMd -Encoding UTF8

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "                      BẢNG TỔNG HỢP CƠ HỘI BÁN HÀNG B2B" -ForegroundColor Yellow
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "1. Tổng số cơ hội tiếp nhận:       $($Inquiries.Count) cơ hội"
Write-Host "2. Có thể tiếp tục (Qualified):    $($StatusCounts['Có thể tiếp tục']) cơ hội" -ForegroundColor Green
Write-Host "3. Cần bổ sung thông tin:          $($StatusCounts['Cần bổ sung thông tin']) cơ hội" -ForegroundColor Yellow
Write-Host "4. Chưa đáp ứng (Unfulfillable):   $($StatusCounts['Chưa đáp ứng']) cơ hội" -ForegroundColor Red
Write-Host "5. Chờ duyệt (Pending Approval):   $($StatusCounts['Chờ duyệt']) cơ hội" -ForegroundColor Magenta
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
Write-Host ">> TỔNG GIÁ TRỊ CÁC CƠ HỘI ĐỦ ĐIỀU KIỆN TIẾP TỤC HOẶC CHỜ DUYỆT:" -ForegroundColor Cyan
Write-Host "   $('{0:N0}' -f $TotalEligibleValue) VND" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Đã xuất toàn bộ Dossier, Draft Email, Approval Ticket, Audit Trace vào outputs\`n" -ForegroundColor Gray
