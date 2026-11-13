"""
Business Tools (Kỹ năng nghiệp vụ) cho AI Agent Công ty Minh An
Cung cấp các công cụ độc lập có thể gọi tuần tự hoặc điều phối linh hoạt
Hỗ trợ trích xuất tự động từ văn bản thô (raw_text) tiếng Việt hoặc dữ liệu có cấu trúc
"""

import os
import re
from typing import Dict, Any, List, Optional
from .models import InquiryItem, CustomerInquiry, OpportunityStatus
from .rules import BusinessRulesEngine


class InquiryProcessingTools:
    def __init__(self, rules_engine: BusinessRulesEngine):
        self.rules = rules_engine

    def _parse_raw_text_vietnamese(self, raw_text: str) -> Dict[str, Any]:
        """Trích xuất thực thể tự động từ văn bản yêu cầu tiếng Việt (NLP Heuristic/Regex)"""
        text_lower = raw_text.lower()

        # 1. Trích xuất danh mục sản phẩm & số lượng
        items = []
        product_patterns = [
            ("PROD-001", "Laptop Dell Latitude 5540", r"(\d+)\s*(?:chiếc\s*|máy\s*|bộ\s*)?(?:laptop\s*)?(?:dell|latitude\s*5540)"),
            ("PROD-002", "Máy chủ HPE ProLiant DL380 Gen10", r"(\d+)\s*(?:chiếc\s*|máy\s*|bộ\s*)?(?:máy\s*chủ\s*|server\s*)?(?:hpe|proliant|dl380)"),
            ("PROD-003", "Cisco Catalyst Switch 24-Port", r"(\d+)\s*(?:chiếc\s*|bộ\s*|cái\s*)?(?:switch\s*cisco|cisco\s*catalyst|switch\s*24-port)"),
            ("PROD-004", "Bộ phát WiFi 6 Cisco Business 150AX", r"(\d+)\s*(?:chiếc\s*|bộ\s*|cái\s*)?(?:bộ\s*phát\s*)?(?:wifi\s*6?\s*cisco|cisco\s*business\s*150ax|wifi\s*150ax)"),
            ("PROD-005", "Dịch vụ Triển khai Cài đặt", r"(\d+)\s*(?:gói\s*)?(?:dịch\s*vụ\s*triển\s*khai|dịch\s*vụ\s*cài\s*đặt|gói\s*dịch\s*vụ)"),
        ]
        for prod_id, prod_name, pattern in product_patterns:
            match = re.search(pattern, text_lower)
            if match:
                qty = int(match.group(1))
                items.append({"product_id": prod_id, "product_name": prod_name, "quantity": qty})

        # 2. Trích xuất Ngân sách (Budget)
        budget: Optional[float] = None
        if not re.search(r"chưa\s*(?:chốt|rõ|xác\s*định|có)\s*ngân\s*sách", text_lower):
            # Tìm dạng: 135 triệu, 270 triệu vnd, 650tr
            m_trieu = re.search(r"(?:ngân\s*sách|kinh\s*phí)[^0-9]{0,40}?(\d+(?:[\.,]\d+)?)\s*(?:triệu|tr\b|m\b)", text_lower)
            if m_trieu:
                val = float(m_trieu.group(1).replace(",", "."))
                budget = val * 1_000_000
            else:
                m_full = re.search(r"(?:ngân\s*sách|kinh\s*phí)[^0-9]{0,40}?(\d{2,3}(?:[\.,]\d{3}){2,3})", text_lower)
                if m_full:
                    clean_num = re.sub(r"[\.,]", "", m_full.group(1))
                    budget = float(clean_num)

        # 3. Trích xuất Thời hạn triển khai (Deadline)
        deadline_days: Optional[int] = None
        if not re.search(r"(?:thời\s*gian|thời\s*hạn)[^.]*chưa\s*xác\s*định", text_lower):
            m_days = re.search(r"(?:trong\s*vòng|trong|bàn\s*giao|giao\s*hàng|thời\s*hạn)[^0-9]{0,25}?(\d+)\s*ngày", text_lower)
            if m_days:
                deadline_days = int(m_days.group(1))
            elif "trong tuần này" in text_lower or "1 tuần" in text_lower:
                deadline_days = 7

        # 4. Trích xuất Chiết khấu yêu cầu (Requested Discount)
        requested_discount = 0.0
        m_disc = re.search(r"(?:chiết\s*khấu|giảm\s*giá|ưu\s*đãi)[^0-9]{0,25}?(\d+(?:[\.,]\d+)?)\s*%", text_lower)
        if m_disc:
            requested_discount = float(m_disc.group(1).replace(",", ".")) / 100.0

        return {
            "items": items,
            "budget": budget,
            "deadline_days": deadline_days,
            "requested_discount_rate": requested_discount,
        }

    def tool_extract_and_validate(self, inquiry_dict: Dict[str, Any]) -> Dict[str, Any]:
        """Kỹ năng 1: Trích xuất và xác thực dữ liệu đầu vào"""
        raw_text = inquiry_dict.get("raw_text", "")
        ext = inquiry_dict.get("extracted_data")

        # Nếu dữ liệu đầu vào chỉ có raw_text mà chưa có extracted_data, tự động chạy NLP parser
        auto_parsed = self._parse_raw_text_vietnamese(raw_text) if raw_text else {}

        if ext is None:
            ext = auto_parsed

        customer_name = ext.get("customer_name") or inquiry_dict.get("customer_name", "Không rõ")
        contact_email = ext.get("contact_email") or inquiry_dict.get("contact_email", "contact@customer.vn")

        raw_items = ext.get("items") if ext.get("items") is not None else auto_parsed.get("items", [])
        parsed_items = []
        for it in raw_items:
            parsed_items.append(
                InquiryItem(
                    product_id=it.get("product_id"),
                    product_name=it.get("product_name", ""),
                    quantity=it.get("quantity", 0),
                )
            )

        budget = ext.get("budget") if "budget" in ext else auto_parsed.get("budget")
        deadline_days = ext.get("deadline_days") if "deadline_days" in ext else auto_parsed.get("deadline_days")
        requested_discount = ext.get("requested_discount_rate") if "requested_discount_rate" in ext else auto_parsed.get("requested_discount_rate", 0.0)

        # Kiểm tra tính đầy đủ
        check_dict = {
            "customer_name": customer_name,
            "contact_email": contact_email,
            "items": [{"quantity": it.quantity, "product_name": it.product_name} for it in parsed_items],
            "budget": budget,
            "deadline_days": deadline_days,
        }
        missing_fields = self.rules.validate_inquiry_completeness(check_dict)

        return {
            "inquiry_id": inquiry_dict.get("inquiry_id", "REQ-NEW"),
            "customer_name": customer_name,
            "contact_email": contact_email,
            "items_count": len(parsed_items),
            "items": parsed_items,
            "budget": budget,
            "deadline_days": deadline_days,
            "requested_discount_rate": requested_discount,
            "is_complete": len(missing_fields) == 0,
            "missing_fields": missing_fields,
        }

    def tool_assess_inventory_and_leadtime(
        self, items: List[InquiryItem], deadline_days: int
    ) -> Dict[str, Any]:
        """Kỹ năng 2: Thẩm định tồn kho khả dụng và thời hạn triển khai"""
        feasibility = self.rules.evaluate_feasibility(items, deadline_days)
        return {
            "is_feasible": feasibility.is_feasible,
            "stock_sufficient_all": feasibility.stock_sufficient_all,
            "lead_time_met": feasibility.lead_time_met,
            "required_lead_time_days": feasibility.required_lead_time_days,
            "requested_deadline_days": feasibility.requested_deadline_days,
            "reasons": feasibility.reasons,
            "feasibility_object": feasibility,
        }

    def tool_calculate_pricing_and_authority(
        self,
        items: List[InquiryItem],
        requested_discount_rate: float,
        budget: float,
    ) -> Dict[str, Any]:
        """Kỹ năng 3: Định giá, chính sách chiết khấu và thẩm quyền phê duyệt"""
        pricing = self.rules.calculate_pricing_and_authority(
            items, requested_discount_rate, budget
        )
        return {
            "list_total": pricing.list_total,
            "standard_discount_rate": pricing.standard_discount_rate,
            "applied_discount_rate": pricing.applied_discount_rate,
            "discount_amount": pricing.discount_amount,
            "final_total": pricing.final_total,
            "budget": pricing.budget,
            "within_budget": pricing.within_budget,
            "requires_approval": pricing.requires_approval,
            "approval_reasons": pricing.approval_reasons,
            "authorized_by": pricing.authorized_by,
            "pricing_object": pricing,
        }

    def tool_generate_drafts_and_dossier(
        self,
        inquiry_info: Dict[str, Any],
        feasibility_info: Dict[str, Any],
        pricing_info: Dict[str, Any],
        assigned_rep: Dict[str, str],
        status: OpportunityStatus,
    ) -> Dict[str, Any]:
        """Kỹ năng 4: Tạo hồ sơ cơ hội, soạn bản nháp phản hồi và phiếu chuyển duyệt"""
        inquiry_id = inquiry_info["inquiry_id"]
        customer_name = inquiry_info["customer_name"]
        items = inquiry_info.get("items", [])

        # 1. Soạn thảo bản nháp phản hồi khách hàng (Customer Draft Response)
        draft_response = ""
        approval_ticket = None

        if status == OpportunityStatus.NEED_INFO:
            missing_text = "\n".join([f"- {m}" for m in inquiry_info["missing_fields"]])
            draft_response = f"""Kính gửi Quý Khách hàng ({customer_name}),

Công ty Cổ phần Công nghệ Minh An xin chân thành cảm ơn Quý đơn vị đã quan tâm đến sản phẩm và dịch vụ công nghệ của chúng tôi.

Để hoàn thiện Hồ sơ Báo giá và phương án kỹ thuật tối ưu nhất cho Quý khách, chúng tôi kính đề nghị Quý khách vui lòng cung cấp hoặc làm rõ thêm một số thông tin sau:
{missing_text}

Sau khi nhận được thông tin bổ sung, chuyên viên kinh doanh của Minh An sẽ gửi Báo giá chi tiết trong vòng 04 giờ làm việc.

Trân trọng cảm ơn,
Chuyên viên phụ trách: {assigned_rep['name']} ({assigned_rep['email']})
Phòng Kinh doanh - Công ty Cổ phần Công nghệ Minh An
"""

        elif status == OpportunityStatus.UNFULFILLABLE:
            reasons_text = "\n".join([f"- {r}" for r in feasibility_info.get("reasons", []) if "VI PHẠM" in r or "KHÔNG đủ" in r or "không tồn tại" in r])
            if pricing_info and not pricing_info.get("within_budget", True):
                reasons_text += f"\n- Mức ngân sách dự kiến ({pricing_info.get('budget', 0):,.0f} VND) chưa tương thích với giá trị giải pháp sau ưu đãi tối đa."

            draft_response = f"""Kính gửi Quý Khách hàng ({customer_name}),

Công ty Minh An xin trân trọng cảm ơn sự quan tâm của Quý khách đối với gói thiết bị và giải pháp công nghệ của chúng tôi.

Sau khi đối chiếu với kế hoạch cung ứng và kho vận hiện tại, chúng tôi rất tiếc phải thông báo rằng yêu cầu hiện thời chưa thể đáp ứng ngay vì các nguyên nhân sau:
{reasons_text}

Để hỗ trợ Quý đơn vị tốt nhất, chúng tôi xin đề xuất giải pháp thay thế:
1. Điều chỉnh thời hạn bàn giao để bộ phận Cung ứng tiến hành nhập hàng theo diện ưu tiên.
2. Hoặc linh hoạt cơ cấu lại cấu hình thiết bị phù hợp hơn với khung ngân sách dự kiến.

Chuyên viên {assigned_rep['name']} ({assigned_rep['email']}) sẽ liên hệ trực tiếp với Quý khách trong ngày hôm nay để trao đổi phương án tối ưu nhất.

Trân trọng,
Công ty Cổ phần Công nghệ Minh An
"""

        elif status == OpportunityStatus.PENDING_APPROVAL:
            draft_response = f"""[DỰ THẢO - CHỜ TRƯỞNG PHÒNG PHÊ DUYỆT TRƯỚC KHI GỬI]
Kính gửi Quý Khách hàng ({customer_name}),

Công ty Cổ phần Công nghệ Minh An trân trọng gửi tới Quý khách Báo giá sơ bộ cho các hạng mục thiết bị:
- Tổng giá trị niêm yết: {pricing_info['list_total']:,.0f} VND
- Mức chiết khấu đề xuất: {pricing_info['applied_discount_rate']*100:.1f}% (Tiết kiệm: {pricing_info['discount_amount']:,.0f} VND)
- Tổng giá trị thanh toán: {pricing_info['final_total']:,.0f} VND (Chưa gồm VAT)
- Thời gian bàn giao dự kiến: {feasibility_info['required_lead_time_days']} ngày làm việc.

(Báo giá chính thức có chữ ký số sẽ được gửi tới Quý khách ngay sau khi Trưởng phòng Kinh doanh phê duyệt hạn mức ưu đãi).

Người lập: {assigned_rep['name']} ({assigned_rep['email']})
Công ty Cổ phần Công nghệ Minh An
"""
            escalation_reasons = "\n".join([f"- {r}" for r in pricing_info.get("approval_reasons", [])])
            approval_ticket = f"""======================================================================
PHIẾU CHUYỂN DUYỆT CƠ HỘI BÁN HÀNG VƯỢT THẨM QUYỀN (ESCALATION TICKET)
Mã yêu cầu: {inquiry_id} | Ngày tiếp nhận: Hôm nay
Khách hàng: {customer_name}
NVKD phụ trách đề xuất: {assigned_rep['name']} ({assigned_rep['email']})
Người có thẩm quyền duyệt: Hoàng Minh Trí - Trưởng phòng Kinh doanh
----------------------------------------------------------------------
1. TỔNG QUAN TÀI CHÍNH & KỸ THUẬT:
   - Tổng giá niêm yết: {pricing_info['list_total']:,.0f} VND
   - Chiết khấu khách yêu cầu: {pricing_info['applied_discount_rate']*100:.1f}% ({pricing_info['discount_amount']:,.0f} VND)
   - Doanh thu dự kiến: {pricing_info['final_total']:,.0f} VND
   - Ngân sách khách hàng: {pricing_info['budget']:,.0f} VND
   - Thời gian đáp ứng kỹ thuật: {feasibility_info['required_lead_time_days']} ngày (Hạn yêu cầu: {feasibility_info['requested_deadline_days']} ngày)

2. CĂN CỨ VÀ LÝ DO VƯỢT THẨM QUYỀN:
{escalation_reasons}

3. ĐỀ XUẤT CỦA AGENT & NVKD:
   - Đánh giá rủi ro: Biên lợi nhuận gộp vẫn đảm bảo mục tiêu doanh thu dự án lớn.
   - Kiến nghị Trưởng phòng: Phê duyệt mức chiết khấu {pricing_info['applied_discount_rate']*100:.1f}% và ký lệnh xuất kho.
======================================================================
"""

        elif status == OpportunityStatus.READY:
            draft_response = f"""Kính gửi Quý Khách hàng ({customer_name}),

Công ty Cổ phần Công nghệ Minh An xin trân trọng gửi tới Quý khách Bản Báo giá và Kế hoạch triển khai cho yêu cầu mã {inquiry_id}:

1. DANH MỤC THIẾT BỊ & DỊCH VỤ:
{chr(10).join([f"  + {it.product_name} | SL: {it.quantity} | Đơn giá: {it.list_price:,.0f} VND | Thành tiền: {it.list_price * it.quantity:,.0f} VND" for it in items])}

2. CHÍNH SÁCH GIÁ & THANH TOÁN:
- Tổng giá niêm yết: {pricing_info['list_total']:,.0f} VND
- Chiết khấu doanh nghiệp ({pricing_info['applied_discount_rate']*100:.1f}%): -{pricing_info['discount_amount']:,.0f} VND
- TỔNG CỘNG THANH TOÁN: {pricing_info['final_total']:,.0f} VND (Chưa gồm VAT)
- Ngân sách Quý khách đăng ký: {pricing_info['budget']:,.0f} VND (Thỏa mãn)

3. THỜI GIAN & ĐIỀU KIỆN GIAO HÀNG:
- Tình trạng kho vận: Hàng có sẵn trong kho Minh An.
- Thời gian giao hàng: {feasibility_info['required_lead_time_days']} ngày làm việc kể từ khi ký hợp đồng (Thỏa mãn hạn mức {feasibility_info['requested_deadline_days']} ngày của Quý khách).

Báo giá có hiệu lực trong vòng 15 ngày. NVKD phụ trách sẽ liên hệ để hoàn tất thủ tục hợp đồng.

Trân trọng kính thư,
Chuyên viên: {assigned_rep['name']} ({assigned_rep['email']})
Công ty Cổ phần Công nghệ Minh An
"""

        # 2. Xây dựng Hồ sơ Cơ hội (Opportunity Dossier)
        dossier_text = f"""# HỒ SƠ CƠ HỘI BÁN HÀNG B2B (OPPORTUNITY DOSSIER)
- Mã hồ sơ: {inquiry_id}
- Khách hàng: {customer_name}
- Email liên hệ: {inquiry_info.get('contact_email')}
- Phân loại trạng thái: **{status.value}**
- Nhân viên phụ trách: {assigned_rep['name']} ({assigned_rep['email']})

## 1. Kết quả Phân loại & Xác thực dữ liệu:
- Tính đầy đủ: {'ĐẦY ĐỦ' if inquiry_info.get('is_complete') else 'THIẾU THÔNG TIN'}
- Trường thông tin còn thiếu: {', '.join(inquiry_info.get('missing_fields', [])) if inquiry_info.get('missing_fields') else 'Không có'}
- Ngân sách khai báo: {f"{inquiry_info.get('budget'):,.0f} VND" if inquiry_info.get('budget') is not None else 'Chưa xác định'}
- Thời hạn mong muốn: {f"{inquiry_info.get('deadline_days')} ngày" if inquiry_info.get('deadline_days') is not None else 'Chưa xác định'}

## 2. Kết quả Thẩm định Tồn kho & Thời gian triển khai (Bộ phận Vận hành):
- Khả thi cung ứng: {'KHẢ THI' if feasibility_info and feasibility_info.get('is_feasible') else 'KHÔNG KHẢ THI / CHƯA XÁC ĐỊNH'}
- Tồn kho: {'Đủ toàn bộ hạng mục' if feasibility_info and feasibility_info.get('stock_sufficient_all') else 'Có hạng mục cần đặt hàng'}
- Thời gian hoàn thành giao hàng: {feasibility_info.get('required_lead_time_days', 0) if feasibility_info else 0} ngày
- Chi tiết đối chiếu:
{chr(10).join([f"  * {r}" for r in feasibility_info.get('reasons', [])]) if feasibility_info else '  * Chưa thẩm định do thiếu dữ liệu'}

## 3. Kết quả Thẩm định Giá & Chính sách Chiết khấu:
- Tổng giá niêm yết: {f"{pricing_info.get('list_total'):,.0f} VND" if pricing_info else 'Chưa tính'}
- Chiết khấu áp dụng: {f"{pricing_info.get('applied_discount_rate', 0)*100:.1f}%" if pricing_info else 'N/A'}
- Giá trị đề xuất sau chiết khấu: {f"{pricing_info.get('final_total'):,.0f} VND" if pricing_info else 'N/A'}
- Người phê duyệt có thẩm quyền: {pricing_info.get('authorized_by', 'N/A') if pricing_info else 'N/A'}
- Đánh giá ngân sách: {'Trong hạn mức ngân sách' if pricing_info and pricing_info.get('within_budget') else 'Vượt quá hoặc chưa rõ ngân sách'}

## 4. Căn cứ Quy tắc Nghiệp vụ áp dụng:
{chr(10).join([f"- {r}" for r in pricing_info.get('approval_reasons', [])]) if pricing_info and pricing_info.get('approval_reasons') else '- Tuân thủ hạn mức chiết khấu và thẩm quyền NVKD.'}

## 5. Bước xử lý tiếp theo (Next Action):
"""
        if status == OpportunityStatus.NEED_INFO:
            dossier_text += "- **Gửi email yêu cầu bổ sung thông tin:** NVKD kiểm tra email nháp và gửi khách hàng để làm rõ ngân sách/thời hạn.\n"
        elif status == OpportunityStatus.UNFULFILLABLE:
            dossier_text += "- **Đóng cơ hội hoặc tư vấn phương án thay thế:** Gửi email thông báo giới hạn kho vận và đề xuất gia hạn deadline/điều chỉnh cấu hình.\n"
        elif status == OpportunityStatus.PENDING_APPROVAL:
            dossier_text += f"- **Chuyển phiếu duyệt lên Trưởng phòng:** NVKD chuyển Escalation Ticket lên {assigned_rep.get('manager', 'Trưởng phòng')} phê duyệt ngoại lệ trước khi gửi khách.\n"
        elif status == OpportunityStatus.READY:
            dossier_text += "- **NVKD kiểm tra lần cuối & Phát hành Báo giá:** NVKD duyệt bản nháp và chính thức gửi báo giá đến khách hàng.\n"

        return {
            "dossier_markdown": dossier_text,
            "draft_response": draft_response,
            "approval_ticket": approval_ticket,
        }
