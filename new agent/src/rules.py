"""
Business Rules and Policy Verification Engine
Chứa toàn bộ quy tắc nghiệp vụ: chiết khấu, phân quyền, lead time, thẩm định khả thi
"""

from typing import Dict, Any, List, Tuple
from .models import InquiryItem, FeasibilityResult, PricingResult


class BusinessRulesEngine:
    def __init__(self, policies: Dict[str, Any], products: List[Dict[str, Any]]):
        self.policies = policies
        self.products = {p["id"]: p for p in products}
        # Name lookup index for fuzzy/exact matching
        self.product_name_map = {p["name"].lower(): p for p in products}

    def match_product(self, raw_name: str, product_id: str = None) -> Dict[str, Any]:
        """Tra cứu sản phẩm theo ID hoặc tên chính xác/tương đối"""
        if product_id and product_id in self.products:
            return self.products[product_id]
        raw_lower = raw_name.lower().strip()
        if raw_lower in self.product_name_map:
            return self.product_name_map[raw_lower]
        for key, p in self.products.items():
            if raw_lower in p["name"].lower() or p["name"].lower() in raw_lower:
                return p
        # Check subkeywords
        for key, p in self.products.items():
            if "dell" in raw_lower and "dell" in p["name"].lower():
                return p
            if "hpe" in raw_lower and "hpe" in p["name"].lower():
                return p
            if "switch" in raw_lower and "switch" in p["name"].lower():
                return p
            if "wifi" in raw_lower and "wifi" in p["name"].lower():
                return p
            if "dịch vụ" in raw_lower and "dịch vụ" in p["name"].lower():
                return p
        return None

    def validate_inquiry_completeness(self, inquiry_data: Dict[str, Any]) -> List[str]:
        """Kiểm tra tính đầy đủ của yêu cầu khách hàng"""
        missing = []
        if not inquiry_data.get("customer_name"):
            missing.append("Tên khách hàng (customer_name)")
        if not inquiry_data.get("contact_email"):
            missing.append("Email liên hệ (contact_email)")
        items = inquiry_data.get("items", [])
        if not items:
            missing.append("Danh sách hạng mục/sản phẩm (items)")
        else:
            for idx, it in enumerate(items, 1):
                if not it.get("quantity") or it.get("quantity") <= 0:
                    missing.append(f"Số lượng cho hạng mục #{idx} ({it.get('product_name', 'Chưa rõ')})")
        if inquiry_data.get("budget") is None:
            missing.append("Ngân sách dự kiến (budget)")
        if inquiry_data.get("deadline_days") is None:
            missing.append("Thời hạn triển khai mong muốn (deadline_days)")
        return missing

    def evaluate_feasibility(
        self, items: List[InquiryItem], deadline_days: int
    ) -> FeasibilityResult:
        """Thẩm định tồn kho khả dụng và thời hạn triển khai"""
        stock_all = True
        max_required_lead_time = 0
        reasons = []

        for it in items:
            prod = self.match_product(it.product_name, it.product_id)
            if not prod:
                reasons.append(f"Sản phẩm '{it.product_name}' không tồn tại trong danh mục hiện hành.")
                stock_all = False
                continue

            it.matched_id = prod["id"]
            it.list_price = prod["list_price"]
            it.stock_available = prod["available_stock"]
            it.ready_lead_time_days = prod["ready_lead_time_days"]
            it.restock_lead_time_days = prod["restock_lead_time_days"]

            # Kiểm tra tồn kho
            if prod["available_stock"] >= it.quantity:
                it.stock_sufficient = True
                lead_time = prod["ready_lead_time_days"]
                reasons.append(
                    f"{prod['name']}: Tồn kho đủ ({prod['available_stock']} >= {it.quantity}), lead time giao có sẵn: {lead_time} ngày."
                )
            else:
                it.stock_sufficient = False
                stock_all = False
                lead_time = prod["restock_lead_time_days"]
                shortage = it.quantity - prod["available_stock"]
                reasons.append(
                    f"{prod['name']}: Tồn kho KHÔNG đủ (thiếu {shortage} chiếc, kho có {prod['available_stock']}/{it.quantity}). Cần đặt hàng bổ sung với lead time: {lead_time} ngày."
                )

            if lead_time > max_required_lead_time:
                max_required_lead_time = lead_time

        # Kiểm tra deadline của khách
        lead_time_met = True
        if deadline_days is not None:
            if deadline_days < max_required_lead_time:
                lead_time_met = False
                reasons.append(
                    f"VI PHẠM THỜI HẠN: Khách yêu cầu giao trong {deadline_days} ngày, nhưng thời gian chuẩn bị/nhập hàng tối thiểu là {max_required_lead_time} ngày."
                )
            else:
                reasons.append(
                    f"ĐÁP ỨNG THỜI HẠN: Thời gian đáp ứng của công ty ({max_required_lead_time} ngày) nằm trong hạn mức khách yêu cầu ({deadline_days} ngày)."
                )

        is_feasible = lead_time_met and (len([r for r in reasons if "không tồn tại" in r]) == 0)
        return FeasibilityResult(
            is_feasible=is_feasible,
            stock_sufficient_all=stock_all,
            lead_time_met=lead_time_met,
            required_lead_time_days=max_required_lead_time,
            requested_deadline_days=deadline_days,
            reasons=reasons,
        )

    def calculate_pricing_and_authority(
        self,
        items: List[InquiryItem],
        requested_discount_rate: float,
        budget: float,
    ) -> PricingResult:
        """Tính toán tổng giá niêm yết, chiết khấu và xác định thẩm quyền duyệt"""
        list_total = sum(it.list_price * it.quantity for it in items)

        # 1. Xác định khung chiết khấu tiêu chuẩn theo quy mô đơn hàng
        standard_discount = 0.0
        for tier in self.policies["volume_discount_policy"]:
            if tier["min_amount"] <= list_total < tier["max_amount"]:
                standard_discount = tier["max_discount_rate"]
                break

        applied_discount = requested_discount_rate
        approval_reasons = []
        requires_approval = False

        # 2. Kiểm tra thẩm quyền chiết khấu
        sales_rep_max_discount = self.policies["approval_authority_matrix"]["sales_rep"]["max_discount_rate"]
        sales_rep_max_amount = self.policies["approval_authority_matrix"]["sales_rep"]["max_order_amount"]
        manager_max_discount = self.policies["approval_authority_matrix"]["sales_manager"]["max_discount_rate"]

        if requested_discount_rate > standard_discount:
            approval_reasons.append(
                f"Mức chiết khấu yêu cầu ({requested_discount_rate*100:.1f}%) vượt khung tiêu chuẩn cho quy mô đơn ({standard_discount*100:.1f}%)."
            )
            requires_approval = True

        if requested_discount_rate > sales_rep_max_discount:
            approval_reasons.append(
                f"Mức chiết khấu ({requested_discount_rate*100:.1f}%) vượt hạn mức tối đa của NVKD ({sales_rep_max_discount*100:.1f}%)."
            )
            requires_approval = True

        # 3. Kiểm tra thẩm quyền theo quy mô giá trị đơn hàng
        if list_total > sales_rep_max_amount:
            approval_reasons.append(
                f"Tổng giá trị đơn hàng ({list_total:,.0f} VND) vượt thẩm quyền tự quyết của NVKD ({sales_rep_max_amount:,.0f} VND)."
            )
            requires_approval = True

        discount_amount = list_total * applied_discount
        final_total = list_total - discount_amount

        # 4. Kiểm tra ngân sách khách hàng
        within_budget = True
        budget_deficit = 0.0
        if budget is not None:
            if budget < final_total:
                within_budget = False
                budget_deficit = final_total - budget
                # Kiểm tra xem nếu giảm kịch trần thẩm quyền Quản lý (15%) có vừa ngân sách không
                lowest_possible = list_total * (1 - manager_max_discount)
                if budget < lowest_possible:
                    approval_reasons.append(
                        f"NGÂN SÁCH KHÔNG KHẢ THI: Ngân sách khách ({budget:,.0f} VND) thấp hơn giá sàn tối thiểu sau chiết khấu tối đa 15% ({lowest_possible:,.0f} VND). Thiếu hụt {lowest_possible - budget:,.0f} VND."
                    )
                else:
                    approval_reasons.append(
                        f"Ngân sách khách ({budget:,.0f} VND) thấp hơn giá chào sau chiết khấu ({final_total:,.0f} VND). Cần đàm phán nâng chiết khấu hoặc giảm hạng mục."
                    )
                    requires_approval = True

        authorized_by = "Trưởng phòng Kinh doanh" if requires_approval else "Nhân viên Kinh doanh (NVKD)"

        return PricingResult(
            list_total=list_total,
            standard_discount_rate=standard_discount,
            applied_discount_rate=applied_discount,
            discount_amount=discount_amount,
            final_total=final_total,
            budget=budget,
            within_budget=within_budget,
            budget_deficit=budget_deficit,
            requires_approval=requires_approval,
            approval_reasons=approval_reasons,
            authorized_by=authorized_by,
        )

