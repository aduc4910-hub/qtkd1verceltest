"""
Data Models for B2B Sales Opportunity Processing Agent (Minh An Company)
Môn học: AI301 | Đề 01
"""

from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
from enum import Enum


class OpportunityStatus(str, Enum):
    READY = "Có thể tiếp tục"
    NEED_INFO = "Cần bổ sung thông tin"
    UNFULFILLABLE = "Chưa đáp ứng"
    PENDING_APPROVAL = "Chờ duyệt"


@dataclass
class InquiryItem:
    product_id: Optional[str]
    product_name: str
    quantity: int
    matched_id: Optional[str] = None
    list_price: float = 0.0
    item_total: float = 0.0
    stock_available: int = 0
    stock_sufficient: bool = False
    ready_lead_time_days: int = 0
    restock_lead_time_days: int = 0


@dataclass
class CustomerInquiry:
    inquiry_id: str
    customer_name: str
    contact_email: str
    raw_text: str
    items: List[InquiryItem]
    budget: Optional[float] = None
    deadline_days: Optional[int] = None
    requested_discount_rate: float = 0.0
    case_category: str = "Chưa phân loại"
    missing_fields: List[str] = field(default_factory=list)


@dataclass
class FeasibilityResult:
    is_feasible: bool
    stock_sufficient_all: bool
    lead_time_met: bool
    required_lead_time_days: int
    requested_deadline_days: Optional[int]
    reasons: List[str] = field(default_factory=list)


@dataclass
class PricingResult:
    list_total: float
    standard_discount_rate: float
    applied_discount_rate: float
    discount_amount: float
    final_total: float
    budget: Optional[float]
    within_budget: bool
    budget_deficit: float
    requires_approval: bool
    approval_reasons: List[str] = field(default_factory=list)
    authorized_by: str = "NVKD"


@dataclass
class OpportunityDossier:
    inquiry_id: str
    customer_name: str
    contact_email: str
    status: OpportunityStatus
    assigned_sales_rep: Dict[str, str]
    feasibility: Optional[FeasibilityResult]
    pricing: Optional[PricingResult]
    next_step: str
    basis_and_rules: List[str]
    draft_response: str
    approval_ticket: Optional[str] = None
    created_at: str = ""

