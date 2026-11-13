# API & Business Logic Engine for Minh An B2B AI Agent (AI301 - Đề 01)
# Native Windows PowerShell Implementation - 100% Offline & Standalone

$DbDir = "$PSScriptRoot\..\data\db"
if (-not (Test-Path $DbDir)) {
    New-Item -ItemType Directory -Force -Path $DbDir | Out-Null
}

function Read-DbTable($name, $defaultObj) {
    $f = "$DbDir\$name.json"
    if (Test-Path $f) {
        try {
            $raw = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
            return $raw | ConvertFrom-Json
        } catch {
            return $defaultObj
        }
    }
    return $defaultObj
}

function Save-DbTable($name, $data) {
    $f = "$DbDir\$name.json"
    $json = $data | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($f, $json, [System.Text.Encoding]::UTF8)
}

function Init-DatabaseIfEmpty {
    if (-not (Test-Path "$DbDir\products.json")) {
        Copy-Item "$PSScriptRoot\..\data\products_inventory.json" "$DbDir\products.json" -Force
    }
    if (-not (Test-Path "$DbDir\policies.json")) {
        Copy-Item "$PSScriptRoot\..\data\business_policies.json" "$DbDir\policies.json" -Force
    }
    if (-not (Test-Path "$DbDir\inquiries.json")) {
        Copy-Item "$PSScriptRoot\..\data\test_inquiries.json" "$DbDir\inquiries.json" -Force
    }
    if (-not (Test-Path "$DbDir\opportunities.json")) {
        Save-DbTable "opportunities" @()
    }
    if (-not (Test-Path "$DbDir\approvals.json")) {
        Save-DbTable "approvals" @()
    }
    if (-not (Test-Path "$DbDir\audit_logs.json")) {
        Save-DbTable "audit_logs" @()
    }
}

# Match product helper
function Match-CatalogProduct($name, $id, $products) {
    if ($id) {
        $p = $products | Where-Object { $_.id -eq $id }
        if ($p) { return $p }
    }
    if (-not $name) { return $null }
    $nLower = $name.ToLower()
    foreach ($p in $products) {
        if ($p.name.ToLower().Contains($nLower) -or $nLower.Contains($p.name.ToLower())) {
            return $p
        }
    }
    foreach ($p in $products) {
        if ($nLower -match "dell" -and $p.name -match "dell") { return $p }
        if ($nLower -match "hpe" -and $p.name -match "hpe") { return $p }
        if ($nLower -match "switch" -and $p.name -match "switch") { return $p }
        if ($nLower -match "wifi" -and $p.name -match "wifi") { return $p }
        if ($nLower -match "dịch vụ" -and $p.name -match "dịch vụ") { return $p }
    }
    return $null
}

# =============================================================================
# SKILL 1: requirement_analysis
# =============================================================================
function Invoke-SkillRequirementAnalysis($inquiry) {
    $rawText = if ($inquiry.raw_text) { $inquiry.raw_text } else { "" }
    $textLower = $rawText.ToLower()

    $custName = if ($inquiry.customer_name) { $inquiry.customer_name } else { "" }
    $contactEmail = if ($inquiry.contact_email) { $inquiry.contact_email } else { "" }

    # Fallback NLP extraction for Customer & Email if missing
    if (-not $custName) {
        if ($rawText -match "(?:Công\s*ty|Tập\s*đoàn|Ngân\s*hàng|Doanh\s*nghiệp)[^,\n.]{2,50}") {
            $custName = $Matches[0].Trim()
        }
    }
    if (-not $contactEmail) {
        if ($rawText -match "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}") {
            $contactEmail = $Matches[0].Trim()
        }
    }

    $extData = if ($inquiry.extracted_data) { $inquiry.extracted_data } elseif ($inquiry.extracted_info) { $inquiry.extracted_info } else { $null }

    $items = @()
    $rawItems = if ($extData -and $extData.items -and $extData.items.Count -gt 0) { $extData.items } elseif ($inquiry.items -and $inquiry.items.Count -gt 0) { $inquiry.items } else { $null }
    if ($rawItems) {
        foreach ($it in $rawItems) {
            $prodId = if ($it.product_id) { $it.product_id } elseif ($it.id) { $it.id } else { "" }
            $pName = if ($it.product_name) { $it.product_name } elseif ($it.name) { $it.name } else { "" }
            $pQty = if ($null -ne $it.quantity) { [int]$it.quantity } elseif ($null -ne $it.qty) { [int]$it.qty } else { 1 }
            $items += [PSCustomObject]@{
                product_id = $prodId
                product_name = $pName
                quantity = $pQty
            }
        }
    } else {
        # NLP Regex entity extractor
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
    }

    $budget = $null
    if ($extData -and $null -ne $extData.budget -and "$($extData.budget)" -ne "") {
        $budget = [double]$extData.budget
    } elseif ($null -ne $inquiry.budget -and "$($inquiry.budget)" -ne "") {
        $budget = [double]$inquiry.budget
    } else {
        if ($textLower -notmatch "chưa\s*(?:chốt|rõ|xác\s*định|có)\s*ngân\s*sách") {
            if ($textLower -match "(?:ngân\s*sách|kinh\s*phí)[^0-9]{0,40}?(\d+(?:[\.,]\d+)?)\s*(?:triệu|tr\b|m\b)") {
                $val = [double]($Matches[1] -replace ",", ".")
                $budget = $val * 1000000.0
            }
        }
    }

    $deadlineDays = $null
    if ($extData -and $null -ne $extData.deadline_days -and "$($extData.deadline_days)" -ne "") {
        $deadlineDays = [int]$extData.deadline_days
    } elseif ($null -ne $inquiry.deadline_days -and "$($inquiry.deadline_days)" -ne "") {
        $deadlineDays = [int]$inquiry.deadline_days
    } else {
        if ($textLower -notmatch "(?:thời\s*gian|thời\s*hạn)[^.]*chưa\s*xác\s*định") {
            if ($textLower -match "(?:trong\s*vòng|trong|bàn\s*giao|giao\s*hàng|thời\s*hạn)[^0-9]{0,25}?(\d+)\s*ngày") {
                $deadlineDays = [int]$Matches[1]
            } elseif ($textLower -match "trong tuần này|1 tuần") {
                $deadlineDays = 7
            }
        }
    }

    $reqDiscount = 0.0
    if ($extData -and $null -ne $extData.requested_discount_rate -and "$($extData.requested_discount_rate)" -ne "") {
        $reqDiscount = [double]$extData.requested_discount_rate
    } elseif ($null -ne $inquiry.requested_discount_rate -and "$($inquiry.requested_discount_rate)" -ne "") {
        $reqDiscount = [double]$inquiry.requested_discount_rate
    } else {
        if ($textLower -match "(?:chiết\s*khấu|giảm\s*giá|ưu\s*đãi)[^0-9]{0,25}?(\d+(?:[\.,]\d+)?)\s*%") {
            $reqDiscount = ([double]($Matches[1] -replace ",", ".")) / 100.0
        }
    }

    # Validate 5 mandatory fields
    $missing = @()
    if (-not $custName) { $missing += "Tên khách hàng" }
    if (-not $contactEmail) { $missing += "Email liên hệ" }
    if (-not $items -or $items.Count -eq 0) {
        $missing += "Danh mục sản phẩm (items)"
    } else {
        foreach ($it in $items) {
            if (-not $it.quantity -or $it.quantity -le 0) {
                $missing += "Số lượng sản phẩm ($($it.product_name))"
            }
        }
    }
    if ($null -eq $budget) { $missing += "Ngân sách dự kiến (budget)" }
    if ($null -eq $deadlineDays) { $missing += "Thời hạn triển khai (deadline_days)" }

    return [PSCustomObject]@{
        skill = "requirement_analysis"
        is_complete = ($missing.Count -eq 0)
        missing_fields = $missing
        extracted = [PSCustomObject]@{
            customer_name = $custName
            contact_email = $contactEmail
            items = $items
            budget = $budget
            deadline_days = $deadlineDays
            requested_discount_rate = $reqDiscount
        }
    }
}

# =============================================================================
# SKILL 2: opportunity_evaluation
# =============================================================================
function Invoke-SkillOpportunityEvaluation($analysis, $products, $policies) {
    $ext = $analysis.extracted
    $reasons = @()

    if (-not $analysis.is_complete) {
        return [PSCustomObject]@{
            skill = "opportunity_evaluation"
            status = "Cần bổ sung"
            eligible_for_pipeline = $false
            is_feasible = $false
            reasons = @("Thiếu thông tin bắt buộc: $($analysis.missing_fields -join ', ')")
            enriched_items = @()
            subtotal = 0.0
            discount_rate = 0.0
            discount_amount = 0.0
            final_total = 0.0
            max_lead_time = 0
            approval_required = $false
        }
    }

    $subtotal = 0.0
    $stockAllOk = $true
    $maxLeadTime = 0
    $enrichedItems = @()

    foreach ($it in $ext.items) {
        $p = Match-CatalogProduct $it.product_name $it.product_id $products
        if (-not $p) {
            $stockAllOk = $false
            $reasons += "Sản phẩm '$($it.product_name)' không tồn tại trong danh mục hiện hành."
            continue
        }

        $stockOk = ($p.available_stock -ge $it.quantity)
        if (-not $stockOk) { $stockAllOk = $false }

        $lead = if ($stockOk) { [int]$p.ready_lead_time_days } else { [int]$p.restock_lead_time_days }
        if ($lead -gt $maxLeadTime) { $maxLeadTime = $lead }

        $lineTotal = [double]$p.list_price * [int]$it.quantity
        $subtotal += $lineTotal

        $enrichedItems += [PSCustomObject]@{
            product_id = $p.id
            product_name = $p.name
            quantity = [int]$it.quantity
            list_price = [double]$p.list_price
            line_total = $lineTotal
            stock_available = [int]$p.available_stock
            stock_sufficient = $stockOk
            lead_time_days = $lead
        }
    }

    # Determine discount tier from volume_discount_policy
    $discountPolicy = $policies.volume_discount_policy
    $tierDiscountRate = 0.0
    $tierName = "Mặc định (0%)"
    foreach ($tier in $discountPolicy) {
        if ($subtotal -ge $tier.min_amount -and $subtotal -lt $tier.max_amount) {
            $tierDiscountRate = [double]$tier.max_discount_rate
            $tierName = $tier.tier_name
            break
        }
    }

    # Applied discount: if customer requested higher discount, consider boundary
    $appliedDiscountRate = $tierDiscountRate
    $requestedExceedsTier = $false
    if ($ext.requested_discount_rate -gt 0) {
        if ($ext.requested_discount_rate -le $tierDiscountRate) {
            $appliedDiscountRate = $ext.requested_discount_rate
        } else {
            $appliedDiscountRate = $ext.requested_discount_rate
            $requestedExceedsTier = $true
        }
    }

    $discountAmount = $subtotal * $appliedDiscountRate
    $finalTotal = $subtotal - $discountAmount

    # Check feasibility constraints
    $deadlineOk = ($maxLeadTime -le $ext.deadline_days)
    $budgetOk = ($finalTotal -le $ext.budget)

    # Check authority matrix
    $repAuthority = $policies.approval_authority_matrix.sales_rep
    $exceedsRepDiscount = ($appliedDiscountRate -gt $repAuthority.max_discount_rate)
    $exceedsRepAmount = ($finalTotal -gt $repAuthority.max_order_amount)
    $needsApproval = ($exceedsRepDiscount -or $exceedsRepAmount)

    # Status Determination according to formal rules
    $status = ""
    $eligibleForPipeline = $false

    if (-not $stockAllOk -and -not $deadlineOk) {
        $status = "Chưa đáp ứng"
        $reasons += "Kho không đủ hàng sẵn và thời gian nhập hàng ($maxLeadTime ngày) vượt thời hạn yêu cầu của khách ($($ext.deadline_days) ngày)."
    } elseif (-not $budgetOk) {
        $status = "Chưa đáp ứng"
        $shortfall = $finalTotal - $ext.budget
        $reasons += "Ngân sách của khách ($($ext.budget.ToString('N0')) VND) thấp hơn giá chào sau chiết khấu ($($finalTotal.ToString('N0')) VND, thiếu $($shortfall.ToString('N0')) VND)."
    } elseif ($needsApproval) {
        $status = "Chờ duyệt"
        $eligibleForPipeline = $true
        if ($exceedsRepDiscount) {
            $reasons += "Chiết khấu $([math]::Round($appliedDiscountRate * 100, 1))% vượt hạn mức NVKD tối đa ($([math]::Round($repAuthority.max_discount_rate * 100, 1))%). Cần Trưởng phòng duyệt."
        }
        if ($exceedsRepAmount) {
            $reasons += "Giá trị đơn hàng ($($finalTotal.ToString('N0')) VND) vượt hạn mức phê duyệt NVKD ($($repAuthority.max_order_amount.ToString('N0')) VND). Cần Trưởng phòng duyệt."
        }
    } else {
        $status = "Có thể tiếp tục"
        $eligibleForPipeline = $true
        $reasons += "Đầy đủ thông tin, hàng khả dụng đủ/kịp tiến độ ($maxLeadTime ngày <= $($ext.deadline_days) ngày), ngân sách hợp lệ và chiết khấu trong thẩm quyền NVKD."
    }

    return [PSCustomObject]@{
        skill = "opportunity_evaluation"
        status = $status
        eligible_for_pipeline = $eligibleForPipeline
        is_feasible = ($stockAllOk -and $deadlineOk -and $budgetOk)
        enriched_items = $enrichedItems
        subtotal = $subtotal
        applied_discount_rate = $appliedDiscountRate
        discount_amount = $discountAmount
        final_total = $finalTotal
        max_lead_time_days = $maxLeadTime
        reasons = $reasons
        approval_required = $needsApproval
        approval_reason = if ($needsApproval) { ($reasons -join "; ") } else { $null }
    }
}

# =============================================================================
# SKILL 3: sales_document_generator
# =============================================================================
function Invoke-SkillDocumentGenerator($inquiry, $analysis, $evaluation, $assignedRep, $policies) {
    $inqId = if ($inquiry.inquiry_id) { $inquiry.inquiry_id } else { "REQ-001" }
    $cust = $analysis.extracted.customer_name
    $status = $evaluation.status

    # 1. Opportunity Dossier Markdown
    $dossier = @"
# HỒ SƠ CƠ HỘI BÁN HÀNG B2B (OPPORTUNITY DOSSIER)
- **Mã hồ sơ:** $inqId
- **Khách hàng:** $cust
- **Email liên hệ:** $($analysis.extracted.contact_email)
- **Chuyên viên phụ trách:** $($assignedRep.name) ($($assignedRep.email))
- **Trạng thái phân loại:** **$status**
- **Thời gian lập hồ sơ:** $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))

---

## 1. Kết quả Đánh giá Nghiệp vụ & Khả năng đáp ứng:
- **Tổng giá trị niêm yết (Subtotal):** $($evaluation.subtotal.ToString('N0')) VND
- **Tỷ lệ chiết khấu áp dụng:** $([math]::Round($evaluation.applied_discount_rate * 100, 1))% ($($evaluation.discount_amount.ToString('N0')) VND)
- **Tổng giá trị đề xuất sau chiết khấu:** **$($evaluation.final_total.ToString('N0')) VND**
- **Ngân sách khách hàng:** $(if ($analysis.extracted.budget) { $analysis.extracted.budget.ToString('N0') + ' VND' } else { 'Chưa cung cấp' })
- **Thời hạn giao hàng cam kết:** $($evaluation.max_lead_time_days) ngày (Khách yêu cầu: $($analysis.extracted.deadline_days) ngày)

## 2. Lý do Phân loại Trạng thái:
$($evaluation.reasons | ForEach-Object { "- $_" } | Out-String)

## 3. Danh mục Hạng mục Báo giá (BoQ):
| Mã SP | Tên Sản Phẩm | SL | Đơn Giá (VND) | Thành Tiền (VND) | Tồn kho ATP | Lead Time |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
$($evaluation.enriched_items | ForEach-Object { "| $($_.product_id) | $($_.product_name) | $($_.quantity) | $($_.list_price.ToString('N0')) | $($_.line_total.ToString('N0')) | $($_.stock_available) | $($_.lead_time_days) ngày |" } | Out-String)
"@

    # 2. Draft Email Response
    $draftEmail = ""
    if ($status -eq "Có thể tiếp tục") {
        $draftEmail = @"
Kính gửi Quý Khách hàng ($cust),

Công ty Cổ phần Công nghệ Minh An xin chân thành cảm ơn Quý đơn vị đã quan tâm và gửi yêu cầu chào giá.

Chúng tôi trân trọng gửi tới Quý khách Báo giá chi tiết cho các hạng mục thiết bị và dịch vụ:
- Tổng giá trị niêm yết: $($evaluation.subtotal.ToString('N0')) VND
- Chiết khấu ưu đãi doanh nghiệp ($([math]::Round($evaluation.applied_discount_rate * 100, 1))%): -$($evaluation.discount_amount.ToString('N0')) VND
- TỔNG GIÁ TRỊ THANH TOÁN (đã gồm VAT): $($evaluation.final_total.ToString('N0')) VND
- Thời gian bàn giao và triển khai: Trong vòng $($evaluation.max_lead_time_days) ngày làm việc kể từ ngày ký hợp đồng.

Hàng hóa được cam kết chính hãng 100%, bảo hành tiêu chuẩn theo quy định của nhà sản xuất. Báo giá có hiệu lực trong vòng 15 ngày.

Rất mong sớm nhận được phản hồi và có cơ hội hợp tác cùng Quý công ty.

Trân trọng,
$($assignedRep.name) - Chuyên viên Kinh doanh B2B
Phòng Kinh doanh • Công ty Cổ phần Công nghệ Minh An
Hotline: 1900 8866 • Email: $($assignedRep.email)
"@
    } elseif ($status -eq "Cần bổ sung") {
        $draftEmail = @"
Kính gửi Quý Khách hàng ($cust),

Công ty Minh An trân trọng cảm ơn Quý đơn vị đã liên hệ. Để chúng tôi có thể lập phương án báo giá chính xác và tối ưu nhất, kính đề nghị Quý khách vui lòng làm rõ/bổ sung các thông tin sau:
$($analysis.missing_fields | ForEach-Object { "- $_" } | Out-String)

Ngay sau khi nhận đủ thông tin, chuyên viên Minh An sẽ gửi Báo giá chính thức trong vòng 04 giờ làm việc.

Trân trọng cảm ơn,
$($assignedRep.name) ($($assignedRep.email))
Phòng Kinh doanh • Công ty Minh An
"@
    } elseif ($status -eq "Chờ duyệt") {
        $draftEmail = @"
Kính gửi Quý Khách hàng ($cust),

Công ty Minh An đã tiếp nhận hồ sơ yêu cầu chào giá của Quý đơn vị. 

Hồ sơ của Quý khách đang được trình Trưởng phòng Kinh doanh xem xét và phê duyệt chính sách chiết khấu ngoại lệ ($([math]::Round($evaluation.applied_discount_rate * 100, 1))%) theo quy định quản trị doanh nghiệp.

Chuyên viên phụ trách ($($assignedRep.name)) sẽ phản hồi kết quả và gửi Hồ sơ Báo giá hoàn chỉnh tới Quý khách trước 17h00 cùng ngày.

Trân trọng cảm ơn sự kiên nhẫn của Quý công ty,
$($assignedRep.name) - Chuyên viên Kinh doanh B2B
Công ty Cổ phần Công nghệ Minh An
"@
    } else {
        $draftEmail = @"
Kính gửi Quý Khách hàng ($cust),

Công ty Minh An trân trọng cảm ơn Quý đơn vị đã gửi yêu cầu. Sau khi đối chiếu dữ liệu kho vận và năng lực đáp ứng, chúng tôi rất tiếc phải thông báo hiện tại Minh An chưa thể đáp ứng đầy đủ yêu cầu theo các điều kiện sau:
$($evaluation.reasons | ForEach-Object { "- $_" } | Out-String)

Chuyên viên Minh An xin phép được liên hệ trực tiếp để tư vấn các phương án sản phẩm tương đương hoặc điều chỉnh tiến độ giao hàng phù hợp hơn với Quý đơn vị.

Trân trọng cảm ơn,
$($assignedRep.name) ($($assignedRep.email))
Công ty Cổ phần Công nghệ Minh An
"@
    }

    # 3. Approval Ticket (if required)
    $approvalTicket = $null
    if ($evaluation.approval_required) {
        $approvalTicket = @"
PHIẾU CHUYỂN PHÊ DUYỆT NGOẠI LỆ (APPROVAL TICKET)
Mã phiếu: TKT-$inqId
Thời gian tạo: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
--------------------------------------------------------------------------------
1. Thông tin Khách hàng & Cơ hội:
- Khách hàng: $cust
- Nhân viên đề xuất: $($assignedRep.name) ($($assignedRep.email))
- Tổng giá trị đơn hàng sau chiết khấu: $($evaluation.final_total.ToString('N0')) VND
- Tỷ lệ chiết khấu xin duyệt: $([math]::Round($evaluation.applied_discount_rate * 100, 1))%

2. Căn cứ và Lý do chuyển duyệt:
$($evaluation.reasons | ForEach-Object { "- $_" } | Out-String)

3. Cấp thẩm quyền phê duyệt:
- Thẩm quyền xét duyệt: $($policies.manager.role) ($($policies.manager.name) - $($policies.manager.email))
- Hạn xử lý SLA: Trong vòng 04 giờ làm việc.

4. Quyết định của Trưởng phòng / Cấp thẩm quyền:
[  ] ĐỒNG Ý PHÊ DUYỆT (APPROVED)
[  ] TỪ CHỐI (REJECTED)
[  ] YÊU CẦU CHỈNH SỬA / ĐÀM PHÁN LẠI (REVISION REQUIRED)
Ý kiến phê duyệt: .............................................................
Chữ ký số: .....................................................................
"@
    }

    return [PSCustomObject]@{
        skill = "sales_document_generator"
        dossier_md = $dossier
        draft_email = $draftEmail
        approval_ticket = $approvalTicket
    }
}

# =============================================================================
# AGENT PIPELINE COORDINATOR (Điều phối 3 Skills)
# =============================================================================
function Invoke-AgentPipeline($inquiryId, $inquiryObj = $null) {
    Init-DatabaseIfEmpty
    $products = Read-DbTable "products" @()
    $policies = Read-DbTable "policies" @{}
    $inquiries = Read-DbTable "inquiries" @()

    $inq = if ($inquiryObj) { $inquiryObj } else { $inquiries | Where-Object { $_.inquiry_id -eq $inquiryId } }
    if (-not $inq) {
        return @{ error = "Không tìm thấy yêu cầu: $inquiryId" }
    }

    # Round-robin assign rep
    $salesReps = $policies.sales_reps
    $assignedRep = $salesReps[([Math]::Abs($inq.inquiry_id.GetHashCode())) % $salesReps.Count]

    $startTime = Get-Date
    $traceLogs = @()

    # Step 1: Skill requirement_analysis
    $step1Start = Get-Date
    $analysis = Invoke-SkillRequirementAnalysis $inq
    $traceLogs += [PSCustomObject]@{
        inquiry_id = $inq.inquiry_id
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        step_name = "1. Tiếp nhận & Phân tích yêu cầu"
        skill_called = "requirement_analysis"
        tool_called = "tool_extract_and_validate"
        tool_input = @{ raw_text = $inq.raw_text; customer_name = $inq.customer_name }
        tool_output = @{ is_complete = $analysis.is_complete; missing_fields = $analysis.missing_fields }
        rules_applied = "Kiểm tra tính đầy đủ 5 trường: Customer, Email, Items, Budget, Deadline"
        decision = if ($analysis.is_complete) { "Đầy đủ thông tin hợp lệ -> Chuyển sang Thẩm định nghiệp vụ." } else { "Thiếu thông tin: $($analysis.missing_fields -join ', ') -> Kích hoạt nhánh Bổ sung." }
        execution_time_ms = [int]((Get-Date) - $step1Start).TotalMilliseconds
    }

    # Step 2: Skill opportunity_evaluation
    $step2Start = Get-Date
    $evaluation = Invoke-SkillOpportunityEvaluation $analysis $products $policies
    $traceLogs += [PSCustomObject]@{
        inquiry_id = $inq.inquiry_id
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        step_name = "2. Thẩm định kho, giá & Ma trận phê duyệt"
        skill_called = "opportunity_evaluation"
        tool_called = "tool_evaluate_feasibility_and_pricing"
        tool_input = @{ items = $analysis.extracted.items; budget = $analysis.extracted.budget; deadline = $analysis.extracted.deadline_days }
        tool_output = @{ status = $evaluation.status; subtotal = $evaluation.subtotal; final_total = $evaluation.final_total; lead_time = $evaluation.max_lead_time_days }
        rules_applied = "Bảng giá Master, Tồn kho ATP, Chính sách chiết khấu Tier 1-4, Thẩm quyền NVKD <= 10% & <= 200M"
        decision = "Xác định trạng thái: $($evaluation.status). Lý do: $($evaluation.reasons -join '; ')"
        execution_time_ms = [int]((Get-Date) - $step2Start).TotalMilliseconds
    }

    # Step 3: Skill sales_document_generator
    $step3Start = Get-Date
    $docs = Invoke-SkillDocumentGenerator $inq $analysis $evaluation $assignedRep $policies
    $traceLogs += [PSCustomObject]@{
        inquiry_id = $inq.inquiry_id
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        step_name = "3. Tạo Hồ sơ, Dự thảo Email & Phiếu duyệt"
        skill_called = "sales_document_generator"
        tool_called = "tool_generate_dossier_email_ticket"
        tool_input = @{ status = $evaluation.status; assigned_rep = $assignedRep.name }
        tool_output = @{ has_dossier = ($null -ne $docs.dossier_md); has_email = ($null -ne $docs.draft_email); has_ticket = ($null -ne $docs.approval_ticket) }
        rules_applied = "Mẫu hồ sơ B2B chuẩn, Quy chuẩn soạn thảo email chào giá, Phiếu trình duyệt Trưởng phòng"
        decision = "Hoàn tất tạo hồ sơ $inqId. Sẵn sàng bàn giao cho NVKD ($($assignedRep.name))."
        execution_time_ms = [int]((Get-Date) - $step3Start).TotalMilliseconds
    }

    # Save outputs to files
    New-Item -ItemType Directory -Force -Path "outputs\dossiers", "outputs\drafts", "outputs\logs" | Out-Null
    if ($docs.dossier_md) {
        [System.IO.File]::WriteAllText("outputs\dossiers\dossier_$($inq.inquiry_id).md", $docs.dossier_md, [System.Text.Encoding]::UTF8)
    }
    if ($docs.draft_email) {
        [System.IO.File]::WriteAllText("outputs\drafts\draft_response_$($inq.inquiry_id).txt", $docs.draft_email, [System.Text.Encoding]::UTF8)
    }
    if ($docs.approval_ticket) {
        [System.IO.File]::WriteAllText("outputs\drafts\approval_ticket_$($inq.inquiry_id).txt", $docs.approval_ticket, [System.Text.Encoding]::UTF8)
    }

    # Construct Opportunity record
    $oppRecord = [PSCustomObject]@{
        inquiry_id = $inq.inquiry_id
        customer_name = $analysis.extracted.customer_name
        contact_email = $analysis.extracted.contact_email
        assigned_rep = $assignedRep
        status = $evaluation.status
        eligible_for_pipeline = $evaluation.eligible_for_pipeline
        subtotal = $evaluation.subtotal
        applied_discount_rate = $evaluation.applied_discount_rate
        discount_amount = $evaluation.discount_amount
        final_total = $evaluation.final_total
        budget = $analysis.extracted.budget
        deadline_days = $analysis.extracted.deadline_days
        max_lead_time_days = $evaluation.max_lead_time_days
        approval_required = $evaluation.approval_required
        approval_reason = $evaluation.approval_reason
        classification_reasons = $evaluation.reasons
        enriched_items = $evaluation.enriched_items
        dossier_md = $docs.dossier_md
        draft_email = $docs.draft_email
        approval_ticket = $docs.approval_ticket
        trace_logs = $traceLogs
        processed_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    # Persist to data/db/opportunities.json
    $allOpps = [System.Collections.Generic.List[object]](Read-DbTable "opportunities" @())
    $existingIdx = -1
    for ($i = 0; $i -lt $allOpps.Count; $i++) {
        if ($allOpps[$i].inquiry_id -eq $inq.inquiry_id) { $existingIdx = $i; break }
    }
    if ($existingIdx -ge 0) {
        $allOpps[$existingIdx] = $oppRecord
    } else {
        $allOpps.Add($oppRecord)
    }
    Save-DbTable "opportunities" $allOpps

    # Persist to data/db/audit_logs.json
    $allLogs = [System.Collections.Generic.List[object]](Read-DbTable "audit_logs" @())
    foreach ($log in $traceLogs) {
        $allLogs.Add($log)
    }
    Save-DbTable "audit_logs" $allLogs

    return $oppRecord
}

# =============================================================================
# DASHBOARD STATS CALCULATOR
# =============================================================================
function Get-DashboardSummary {
    Init-DatabaseIfEmpty
    $inquiries = Read-DbTable "inquiries" @()
    $opportunities = Read-DbTable "opportunities" @()

    $counts = @{
        "Có thể tiếp tục" = 0
        "Cần bổ sung" = 0
        "Chưa đáp ứng" = 0
        "Chờ duyệt" = 0
    }
    $totalEligible = 0.0
    $totalPending = 0.0

    foreach ($opp in $opportunities) {
        $st = $opp.status
        if ($st -match "Chờ duyệt") {
            $counts["Chờ duyệt"]++
            $totalPending += [double]$opp.final_total
        } elseif ($st -match "tiếp tục") {
            $counts["Có thể tiếp tục"]++
            $totalEligible += [double]$opp.final_total
        } elseif ($st -match "bổ sung") {
            $counts["Cần bổ sung"]++
        } else {
            $counts["Chưa đáp ứng"]++
        }
    }

    return [PSCustomObject]@{
        total_inquiries = $inquiries.Count
        total_processed = $opportunities.Count
        status_counts = $counts
        total_eligible_value = $totalEligible
        total_pending_approval_value = $totalPending
        currency = "VND"
        recent_opportunities = ($opportunities | Select-Object -Last 6)
    }
}
