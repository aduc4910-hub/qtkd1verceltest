"""
AI Agent Core Engine cho Quy trình Xử lý Cơ hội Bán hàng B2B - Công ty Minh An
Điều phối các công cụ (Tool Calling), quản lý luồng rẽ nhánh và thực thi quy tắc an toàn
"""

import json
import os
from typing import Dict, Any, List
from .models import OpportunityStatus
from .tools import InquiryProcessingTools
from .logger import AuditLogger


class B2BSalesAgent:
    def __init__(
        self,
        tools: InquiryProcessingTools,
        policies: Dict[str, Any],
        logger: AuditLogger,
    ):
        self.tools = tools
        self.policies = policies
        self.logger = logger
        self.sales_reps = policies.get("sales_reps", [])
        self.rep_counter = 0

    def get_next_sales_rep(self) -> Dict[str, str]:
        """Phân công NVKD phụ trách theo cơ chế Round-robin công bằng giữa 6 NVKD"""
        if not self.sales_reps:
            return {"id": "SR01", "name": "Nguyễn Văn An", "email": "an.nv@minhan.com.vn"}
        rep = self.sales_reps[self.rep_counter % len(self.sales_reps)]
        self.rep_counter += 1
        return rep

    def process_inquiry(self, inquiry_dict: Dict[str, Any]) -> Dict[str, Any]:
        """Xử lý toàn diện một yêu cầu từ khách hàng qua các bước nghiệp vụ"""
        inquiry_id = inquiry_dict.get("inquiry_id", "UNKNOWN")
        customer_name = inquiry_dict.get("customer_name", "Không rõ")

        # Gán NVKD phụ trách hồ sơ
        assigned_rep = self.get_next_sales_rep()

        # =====================================================================
        # BƯỚC 1: TIẾP NHẬN, TRÍCH XUẤT & KIỂM TRA THÔNG TIN (ĐỦ DỮ LIỆU?)
        # =====================================================================
        thought_1 = f"Agent tiếp nhận yêu cầu {inquiry_id} từ {customer_name}. Cần trích xuất các trường thông tin bắt buộc và kiểm tra tính đầy đủ."
        extract_result = self.tools.tool_extract_and_validate(inquiry_dict)

        rules_applied_1 = [
            "Kiểm tra trường bắt buộc: customer_name, contact_email, items (với số lượng > 0), budget, deadline_days"
        ]

        if not extract_result["is_complete"]:
            decision_1 = f"Yêu cầu thiếu dữ liệu: {', '.join(extract_result['missing_fields'])}. Kích hoạt nhánh: Yêu cầu KH làm rõ/bổ sung."
            status = OpportunityStatus.NEED_INFO

            self.logger.log_step(
                inquiry_id=inquiry_id,
                step_name="1. Phân loại & Kiểm tra thông tin",
                agent_thought=thought_1,
                tool_called="tool_extract_and_validate",
                tool_input={"inquiry_id": inquiry_id},
                tool_output={
                    "is_complete": False,
                    "missing_fields": extract_result["missing_fields"],
                },
                rules_applied=rules_applied_1,
                decision=decision_1,
            )

            # Tạo bản nháp email hỏi lại khách hàng
            draft_output = self.tools.tool_generate_drafts_and_dossier(
                inquiry_info=extract_result,
                feasibility_info=None,
                pricing_info=None,
                assigned_rep=assigned_rep,
                status=status,
            )

            self._save_outputs(inquiry_id, draft_output)
            return {
                "inquiry_id": inquiry_id,
                "customer_name": customer_name,
                "status": status.value,
                "assigned_rep": assigned_rep,
                "final_total": 0.0,
                "eligible_for_pipeline": False,
                "summary": "Thiếu thông tin, đã tạo bản nháp email yêu cầu KH bổ sung.",
            }

        decision_1 = "Đầy đủ thông tin hợp lệ. Chuyển sang bước Tạo Hồ sơ & Thẩm định tồn kho & giá."
        self.logger.log_step(
            inquiry_id=inquiry_id,
            step_name="1. Phân loại & Kiểm tra thông tin",
            agent_thought=thought_1,
            tool_called="tool_extract_and_validate",
            tool_input={"inquiry_id": inquiry_id},
            tool_output={"is_complete": True, "items_count": extract_result["items_count"]},
            rules_applied=rules_applied_1,
            decision=decision_1,
        )

        # =====================================================================
        # BƯỚC 2: THẨM ĐỊNH TỒN KHO & THỜI HẠN TRIỂN KHAI (VẬN HÀNH)
        # =====================================================================
        thought_2 = f"Kiểm tra tồn kho khả dụng và so sánh thời hạn yêu cầu ({extract_result['deadline_days']} ngày) với Lead time cung ứng."
        feasibility_result = self.tools.tool_assess_inventory_and_leadtime(
            items=extract_result["items"],
            deadline_days=extract_result["deadline_days"],
        )

        rules_applied_2 = [
            "Đối chiếu tồn kho khả dụng hiện hành (Master Data)",
            "Quy tắc Lead time: Nếu thiếu hàng thì Lead time = restock_lead_time_days",
            "SLA: Nếu deadline_days < required_lead_time_days thì vi phạm cam kết tiến độ",
        ]

        # =====================================================================
        # BƯỚC 3: ĐỊNH GIÁ & CHÍNH SÁCH CHIẾT KHẤU & THẨM QUYỀN
        # =====================================================================
        thought_3 = f"Tính toán tổng giá trị theo giá niêm yết mới nhất, áp dụng chính sách chiết khấu theo quy mô và thẩm quyền."
        pricing_result = self.tools.tool_calculate_pricing_and_authority(
            items=extract_result["items"],
            requested_discount_rate=extract_result["requested_discount_rate"],
            budget=extract_result["budget"],
        )

        rules_applied_3 = [
            "Bảng giá niêm yết hiện hành chống dùng giá cũ",
            "Ma trận chiết khấu theo quy mô giá trị đơn hàng",
            "Phân quyền NVKD tối đa chiết khấu 10% và đơn hàng <= 200M VND",
            "Thẩm quyền Trưởng phòng duyệt chiết khấu đến 15% hoặc đơn hàng > 200M VND",
        ]

        # =====================================================================
        # BƯỚC 4: TỔNG HỢP & PHÂN LUỒNG QUYẾT ĐỊNH (BRANCHING)
        # =====================================================================
        # 1. Kiểm tra trường hợp không thể đáp ứng (Unfulfillable)
        is_unfulfillable = False
        unfulfillable_reasons = []

        if not feasibility_result["is_feasible"]:
            is_unfulfillable = True
            unfulfillable_reasons.append("Không thể đáp ứng thời hạn giao hàng do vượt tồn kho và lead time nhập hàng kéo dài.")

        # Kiểm tra ngân sách có khả thi với giá sàn tối đa không
        lowest_acceptable = pricing_result["list_total"] * (1 - self.policies["approval_authority_matrix"]["sales_manager"]["max_discount_rate"])
        if extract_result["budget"] is not None and extract_result["budget"] < lowest_acceptable:
            is_unfulfillable = True
            unfulfillable_reasons.append(f"Ngân sách ({extract_result['budget']:,.0f} VND) thấp hơn giá sàn tối thiểu ({lowest_acceptable:,.0f} VND).")

        if is_unfulfillable:
            status = OpportunityStatus.UNFULFILLABLE
            decision_final = f"Yêu cầu không khả thi: {'; '.join(unfulfillable_reasons)}. Tạo email thông báo lý do và phương án thay thế."
            eligible = False
        elif pricing_result["requires_approval"]:
            status = OpportunityStatus.PENDING_APPROVAL
            decision_final = f"Yêu cầu khả thi nhưng vượt thẩm quyền NVKD ({', '.join(pricing_result['approval_reasons'])}). Tạo Phiếu chuyển duyệt gửi Trưởng phòng."
            eligible = True
        else:
            status = OpportunityStatus.READY
            decision_final = "Yêu cầu hoàn toàn khả thi và nằm trong thẩm quyền của NVKD. Tạo Hồ sơ Cơ hội và Bản nháp Báo giá chính thức."
            eligible = True

        self.logger.log_step(
            inquiry_id=inquiry_id,
            step_name="2. Thẩm định tồn kho & giá",
            agent_thought=thought_2 + " | " + thought_3,
            tool_called="tool_assess_inventory_and_leadtime + tool_calculate_pricing_and_authority",
            tool_input={
                "items_count": len(extract_result["items"]),
                "requested_discount": extract_result["requested_discount_rate"],
                "budget": extract_result["budget"],
            },
            tool_output={
                "is_feasible": feasibility_result["is_feasible"],
                "final_total": pricing_result["final_total"],
                "requires_approval": pricing_result["requires_approval"],
                "status": status.value,
            },
            rules_applied=rules_applied_2 + rules_applied_3,
            decision=decision_final,
        )

        # =====================================================================
        # BƯỚC 5: TẠO HỒ SƠ CƠ HỘI & BẢN NHÁP PHẢN HỒI (TOOL 4)
        # =====================================================================
        draft_output = self.tools.tool_generate_drafts_and_dossier(
            inquiry_info=extract_result,
            feasibility_info=feasibility_result,
            pricing_info=pricing_result,
            assigned_rep=assigned_rep,
            status=status,
        )

        self._save_outputs(inquiry_id, draft_output)

        return {
            "inquiry_id": inquiry_id,
            "customer_name": customer_name,
            "status": status.value,
            "assigned_rep": assigned_rep,
            "list_total": pricing_result["list_total"],
            "discount_rate": pricing_result["applied_discount_rate"],
            "final_total": pricing_result["final_total"] if status in [OpportunityStatus.READY, OpportunityStatus.PENDING_APPROVAL] else 0.0,
            "eligible_for_pipeline": eligible,
            "summary": decision_final,
        }

    def _save_outputs(self, inquiry_id: str, draft_output: Dict[str, Any]):
        """Lưu trữ hồ sơ cơ hội, email nháp và phiếu chuyển duyệt ra đĩa (hỗ trợ cả môi trường serverless readonly)"""
        for out_root in ["outputs", "/tmp/outputs"]:
            try:
                os.makedirs(os.path.join(out_root, "dossiers"), exist_ok=True)
                os.makedirs(os.path.join(out_root, "drafts"), exist_ok=True)

                dossier_path = os.path.join(out_root, "dossiers", f"dossier_{inquiry_id}.md")
                with open(dossier_path, "w", encoding="utf-8") as f:
                    f.write(draft_output["dossier_markdown"])

                draft_path = os.path.join(out_root, "drafts", f"draft_response_{inquiry_id}.txt")
                with open(draft_path, "w", encoding="utf-8") as f:
                    f.write(draft_output["draft_response"])

                if draft_output.get("approval_ticket"):
                    ticket_path = os.path.join(out_root, "drafts", f"approval_ticket_{inquiry_id}.txt")
                    with open(ticket_path, "w", encoding="utf-8") as f:
                        f.write(draft_output["approval_ticket"])
                break
            except Exception:
                continue

