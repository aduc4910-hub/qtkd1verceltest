"""
MINH AN B2B AI AGENT - BACKEND CORE & API SERVER
Đồ án AI301 | Đề 01 - Công ty Cổ phần Công nghệ Minh An
Hỗ trợ chạy đồng thời:
1. FastAPI Server trên Vercel Serverless Functions & Localhost (Entrypoint: app, application, handler)
2. CLI Evaluation Runner khi chấm thi trực tiếp (python main.py <file.json>)
"""

import sys
import json
import os
import shutil
import random
from datetime import datetime
from typing import Dict, Any, List, Optional

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware

# Import AI Agent Engine & Skills
from src.rules import BusinessRulesEngine
from src.tools import InquiryProcessingTools
from src.logger import AuditLogger
from src.agent import B2BSalesAgent
from src.models import OpportunityStatus

# ==============================================================================
# 1. KHỞI TẠO FASTAPI APP & VERCEL ENTRYPOINT (app, application, handler)
# ==============================================================================
app = FastAPI(
    title="MINH AN B2B AI AGENT",
    description="Hệ thống AI Agent Xử lý Cơ hội Bán hàng B2B - Công ty Cổ phần Công nghệ Minh An",
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Thêm CORS Middleware để giao diện web gọi API mượt mà không bị chặn
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Vercel Serverless Function & WSGI/ASGI Compatibility Hooks
application = app
handler = app

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_DIR = os.path.join(BASE_DIR, "data", "db")
TMP_DIR = "/tmp/minhan_agent"
TMP_DB_DIR = os.path.join(TMP_DIR, "db")

# ==============================================================================
# 2. CƠ CHẾ QUẢN TRỊ CƠ SỞ DỮ LIỆU TỰ ĐỘNG (LOCAL & SERVERLESS COMPATIBLE)
# ==============================================================================
def get_active_db_dir() -> str:
    """Xác định thư mục CSDL có quyền ghi (hỗ trợ cả Localhost và Vercel Read-only Filesystem)"""
    try:
        os.makedirs(DB_DIR, exist_ok=True)
        test_file = os.path.join(DB_DIR, ".write_check")
        with open(test_file, "w") as f:
            f.write("ok")
        os.remove(test_file)
        return DB_DIR
    except Exception:
        # Môi trường Vercel Serverless: File system tại /var/task là read-only, sử dụng /tmp
        os.makedirs(TMP_DB_DIR, exist_ok=True)
        if os.path.exists(DB_DIR):
            for fname in os.listdir(DB_DIR):
                src = os.path.join(DB_DIR, fname)
                dst = os.path.join(TMP_DB_DIR, fname)
                if os.path.isfile(src) and not os.path.exists(dst):
                    try:
                        shutil.copy2(src, dst)
                    except Exception:
                        pass
        return TMP_DB_DIR

ACTIVE_DB_DIR = get_active_db_dir()

def read_db(table_name: str, default: Any = None) -> Any:
    """Đọc dữ liệu từ bảng CSDL với fallback linh hoạt"""
    path = os.path.join(ACTIVE_DB_DIR, f"{table_name}.json")
    if not os.path.exists(path):
        # Fallback kiểm tra tại thư mục gốc data/
        alt_path = os.path.join(BASE_DIR, "data", f"{table_name}.json")
        if table_name == "products" and not os.path.exists(alt_path):
            alt_path = os.path.join(BASE_DIR, "data", "products_inventory.json")
        elif table_name == "policies" and not os.path.exists(alt_path):
            alt_path = os.path.join(BASE_DIR, "data", "business_policies.json")
        if os.path.exists(alt_path):
            path = alt_path
        else:
            return default if default is not None else []
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default if default is not None else []

def write_db(table_name: str, data: Any):
    """Ghi dữ liệu an toàn vào bảng CSDL"""
    global ACTIVE_DB_DIR
    path = os.path.join(ACTIVE_DB_DIR, f"{table_name}.json")
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception:
        ACTIVE_DB_DIR = TMP_DB_DIR
        os.makedirs(ACTIVE_DB_DIR, exist_ok=True)
        path = os.path.join(ACTIVE_DB_DIR, f"{table_name}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

# ==============================================================================
# 3. KHỞI TẠO AI AGENT CORE & BỘ ĐIỀU PHỐI SKILLS
# ==============================================================================
def get_agent_instance():
    """Khởi tạo AI Agent với Master Data & Chính sách hiện hành"""
    products = read_db("products", [])
    policies = read_db("policies", {})
    if not products:
        with open(os.path.join(BASE_DIR, "data", "products_inventory.json"), "r", encoding="utf-8") as f:
            products = json.load(f)
    if not policies:
        with open(os.path.join(BASE_DIR, "data", "business_policies.json"), "r", encoding="utf-8") as f:
            policies = json.load(f)

    rules_engine = BusinessRulesEngine(policies, products)
    tools = InquiryProcessingTools(rules_engine)

    log_dir = os.path.join(BASE_DIR, "outputs", "logs")
    try:
        os.makedirs(log_dir, exist_ok=True)
    except Exception:
        log_dir = "/tmp/outputs/logs"
        os.makedirs(log_dir, exist_ok=True)

    logger = AuditLogger(log_dir=log_dir)
    agent = B2BSalesAgent(tools, policies, logger)
    return agent, tools, rules_engine, policies, products

def process_inquiry_with_agent(inq_dict: Dict[str, Any]) -> Dict[str, Any]:
    """Kích hoạt chuỗi 3 Skills của AI Agent để thẩm định và xuất hồ sơ cơ hội"""
    agent, tools, rules_engine, policies, products = get_agent_instance()
    inquiry_id = inq_dict.get("inquiry_id") or f"REQ-{datetime.now().strftime('%Y%m%d-%H%M%S')}-{random.randint(100, 999)}"
    inq_dict["inquiry_id"] = inquiry_id

    # Thực thi Agent Pipeline
    res = agent.process_inquiry(inq_dict)

    # Đọc tài liệu Markdown, Email nháp và Phiếu duyệt
    dossier_content = ""
    draft_response = ""
    approval_ticket = None

    for base_out in [os.path.join(BASE_DIR, "outputs"), "/tmp/outputs"]:
        d_path = os.path.join(base_out, "dossiers", f"dossier_{inquiry_id}.md")
        r_path = os.path.join(base_out, "drafts", f"draft_response_{inquiry_id}.txt")
        t_path = os.path.join(base_out, "drafts", f"approval_ticket_{inquiry_id}.txt")
        if os.path.exists(d_path) and not dossier_content:
            try:
                with open(d_path, "r", encoding="utf-8") as f: dossier_content = f.read()
            except Exception: pass
        if os.path.exists(r_path) and not draft_response:
            try:
                with open(r_path, "r", encoding="utf-8") as f: draft_response = f.read()
            except Exception: pass
        if os.path.exists(t_path) and not approval_ticket:
            try:
                with open(t_path, "r", encoding="utf-8") as f: approval_ticket = f.read()
            except Exception: pass

    # Xây dựng đối tượng Opportunity hoàn chỉnh
    ext = inq_dict.get("extracted_data") or inq_dict
    status_str = res.get("status", "Chưa đáp ứng")
    opp = {
        "inquiry_id": inquiry_id,
        "customer_name": inq_dict.get("customer_name") or ext.get("customer_name", "Không rõ"),
        "contact_email": inq_dict.get("contact_email") or ext.get("contact_email", "contact@customer.vn"),
        "assigned_rep": res.get("assigned_rep"),
        "status": status_str,
        "eligible_for_pipeline": res.get("eligible_for_pipeline", False),
        "subtotal": res.get("list_total", 0.0),
        "applied_discount_rate": res.get("discount_rate", 0.0),
        "discount_amount": res.get("list_total", 0.0) * res.get("discount_rate", 0.0),
        "final_total": res.get("final_total", 0.0),
        "budget": ext.get("budget", inq_dict.get("budget")),
        "deadline_days": ext.get("deadline_days", inq_dict.get("deadline_days")),
        "approval_required": "Chờ duyệt" in status_str,
        "approval_reason": res.get("summary") if "Chờ duyệt" in status_str else None,
        "dossier_md": dossier_content,
        "draft_email": draft_response,
        "approval_ticket": approval_ticket,
        "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }

    # Lưu vào opportunities.json
    all_opps = read_db("opportunities", [])
    found = False
    for i, o in enumerate(all_opps):
        if o.get("inquiry_id") == inquiry_id:
            all_opps[i] = opp
            found = True
            break
    if not found:
        all_opps.append(opp)
    write_db("opportunities", all_opps)

    # Đồng bộ vết kiểm toán vào audit_logs.json
    all_logs = read_db("audit_logs", [])
    for t in agent.logger.traces:
        if t.get("inquiry_id") == inquiry_id:
            all_logs.append(t)
    write_db("audit_logs", all_logs)

    return opp

# ==============================================================================
# 4. HỆ THỐNG REST API ENDPOINTS ĐỒNG BỘ 8 PHÂN HỆ
# ==============================================================================

# 4.1 Dashboard KPI & Thống kê
@app.get("/api/dashboard")
def get_dashboard():
    inquiries = read_db("inquiries", [])
    opportunities = read_db("opportunities", [])
    counts = {
        "Có thể tiếp tục": 0,
        "Cần bổ sung": 0,
        "Chưa đáp ứng": 0,
        "Chờ duyệt": 0
    }
    total_eligible = 0.0
    total_pending = 0.0

    for opp in opportunities:
        st = opp.get("status", "")
        if "Chờ duyệt" in st and "Đã phê duyệt" not in st and "Từ chối" not in st:
            counts["Chờ duyệt"] += 1
            total_pending += float(opp.get("final_total", 0.0))
        elif "tiếp tục" in st:
            counts["Có thể tiếp tục"] += 1
            total_eligible += float(opp.get("final_total", 0.0))
        elif "bổ sung" in st:
            counts["Cần bổ sung"] += 1
        else:
            counts["Chưa đáp ứng"] += 1

    return {
        "total_inquiries": len(inquiries),
        "total_processed": len(opportunities),
        "status_counts": counts,
        "total_eligible_value": total_eligible,
        "total_pending_approval_value": total_pending,
        "currency": "VND"
    }

# 4.2 Danh mục Sản phẩm & Kho ATP
@app.get("/api/products")
def get_products():
    return read_db("products", [])

@app.post("/api/products")
def add_product(prod: Dict[str, Any]):
    prods = read_db("products", [])
    prods.append(prod)
    write_db("products", prods)
    return {"success": True, "product": prod}

# 4.3 Chính sách Chiết khấu & Hạn mức Thẩm quyền
@app.get("/api/policies")
def get_policies():
    return read_db("policies", {})

@app.post("/api/policies")
def update_policies(pol: Dict[str, Any]):
    write_db("policies", pol)
    return {"success": True, "policies": pol}

# 4.4 Tiếp nhận Yêu cầu B2B & Kích hoạt AI Agent
@app.get("/api/inquiries")
def get_inquiries():
    return read_db("inquiries", [])

@app.post("/api/inquiries")
def create_inquiry(payload: Dict[str, Any]):
    # Kiểm tra tính hợp lệ của dữ liệu đầu vào
    ext = payload.get("extracted_data") or {}
    cust = payload.get("customer_name") or ext.get("customer_name")
    if not cust or len(str(cust).strip()) < 2:
        raise HTTPException(status_code=400, detail="Tên khách hàng không được để trống (tối thiểu 2 ký tự).")

    email = payload.get("contact_email") or ext.get("contact_email")
    if not email or "@" not in str(email):
        raise HTTPException(status_code=400, detail="Email khách hàng không hợp lệ.")

    inq_id = payload.get("inquiry_id")
    if not inq_id:
        rnd = random.randint(100, 999)
        inq_id = f"REQ-{datetime.now().strftime('%Y%m%d-%H%M%S')}-{rnd}"
        payload["inquiry_id"] = inq_id

    # Lưu yêu cầu gốc
    inqs = read_db("inquiries", [])
    inqs.append(payload)
    write_db("inquiries", inqs)

    # Chuyển dữ liệu sang AI Agent xử lý
    opp = process_inquiry_with_agent(payload)
    dash = get_dashboard()

    return {
        "success": True,
        "message": f"Tiếp nhận và AI Agent xử lý thành công hồ sơ {inq_id}!",
        "inquiry_id": inq_id,
        "inquiry": payload,
        "opportunity": opp,
        "dashboard": dash
    }

# 4.5 Hồ sơ Cơ hội (Opportunities)
@app.get("/api/opportunities")
def get_opportunities():
    return read_db("opportunities", [])

@app.post("/api/process-single")
def process_single(payload: Dict[str, Any]):
    inq_id = payload.get("inquiry_id")
    inqs = read_db("inquiries", [])
    target = next((i for i in inqs if i.get("inquiry_id") == inq_id), None)
    if not target:
        raise HTTPException(status_code=404, detail=f"Không tìm thấy yêu cầu {inq_id}")
    opp = process_inquiry_with_agent(target)
    return {"success": True, "opportunity": opp}

# 4.6 Phê duyệt Ngoại lệ (Human-in-the-Loop)
@app.get("/api/approvals")
def get_approvals():
    opps = read_db("opportunities", [])
    hist = read_db("approvals", [])
    pending = [
        o for o in opps 
        if "Chờ duyệt" in o.get("status", "") 
        and "Đã phê duyệt" not in o.get("status", "") 
        and "Từ chối" not in o.get("status", "")
    ]
    return {
        "pending_opportunities": pending,
        "approval_history": hist
    }

@app.post("/api/approvals/decide")
@app.post("/api/approvals")
def make_approval_decision(payload: Dict[str, Any]):
    target_id = payload.get("inquiry_id") or payload.get("opportunity_id")
    if not target_id:
        raise HTTPException(status_code=400, detail="Thiếu mã yêu cầu / cơ hội (inquiry_id).")

    decision_raw = str(payload.get("decision", "Approved")).strip()
    dec_low = decision_raw.lower()
    approver_name = payload.get("approver_name") or "Hoàng Minh Trí (Trưởng phòng Kinh doanh)"
    approver_role = payload.get("approver_role") or "Trưởng phòng Kinh doanh"
    note = str(payload.get("note", "")).strip() or "Đã xem xét và quyết định theo thẩm quyền quản trị B2B"
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    dec_id = f"DEC-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

    # Cập nhật trạng thái cơ hội
    opps = read_db("opportunities", [])
    found_opp = None
    for opp in opps:
        if opp.get("inquiry_id") == target_id:
            if "approve" in dec_low or "đồng ý" in dec_low:
                opp["status"] = "Có thể tiếp tục (Đã phê duyệt)"
                opp["approval_decision"] = f"Đã duyệt bởi {approver_name} - Ghi chú: {note}"
            elif "reject" in dec_low or "từ chối" in dec_low:
                opp["status"] = "Chưa đáp ứng (Từ chối duyệt)"
                opp["approval_decision"] = f"Từ chối bởi {approver_name} - Lý do: {note}"
            else:
                opp["status"] = "Cần bổ sung (Yêu cầu đàm phán lại)"
                opp["approval_decision"] = f"Yêu cầu chỉnh sửa bởi {approver_name}: {note}"
            found_opp = opp
            break

    if found_opp:
        write_db("opportunities", opps)

    # Lưu bản ghi phê duyệt
    record = {
        "decision_id": dec_id,
        "opportunity_id": target_id,
        "inquiry_id": target_id,
        "decision": decision_raw,
        "approver_name": approver_name,
        "approver_role": approver_role,
        "note": note,
        "decided_at": now_str,
        "timestamp": now_str
    }
    approvals = read_db("approvals", [])
    approvals.append(record)
    write_db("approvals", approvals)

    # Ghi nhận vào Nhật ký Kiểm toán Audit Log
    audit_logs = read_db("audit_logs", [])
    audit_logs.append({
        "inquiry_id": target_id,
        "timestamp": now_str,
        "step_name": "4. Phê duyệt Ngoại lệ (Human-in-the-Loop)",
        "skill_called": "HITL_approval",
        "tool_called": "manager_decision_action",
        "tool_input": {
            "inquiry_id": target_id,
            "decision": decision_raw,
            "approver": approver_name,
            "note": note
        },
        "tool_output": {
            "status": "Thành công",
            "decision_id": dec_id,
            "new_opportunity_status": found_opp.get("status") if found_opp else "Unknown"
        },
        "rules_applied": "Chính sách thẩm quyền phê duyệt B2B: Chiết khấu > 5% hoặc Giá trị > 200.000.000 VND",
        "decision": f"Trưởng phòng ({approver_name}) ra quyết định [{decision_raw}] cho hồ sơ {target_id}. Ghi chú: {note}"
    })
    write_db("audit_logs", audit_logs)

    return {
        "success": True,
        "message": "Quyết định phê duyệt đã được lưu thành công",
        "record": record,
        "updated_opportunity": found_opp
    }

# 4.7 Nhật ký Kiểm toán (Audit Logs)
@app.get("/api/audit-logs")
def get_audit_logs():
    return read_db("audit_logs", [])

# 4.8 Bộ Kiểm thử Tự động (Automated Test Suite)
@app.post("/api/run-tests")
def run_tests():
    test_file = os.path.join(BASE_DIR, "data", "test_exam_sample.json")
    if not os.path.exists(test_file):
        test_file = os.path.join(BASE_DIR, "data", "test_inquiries.json")
    with open(test_file, "r", encoding="utf-8") as f:
        sample_inquiries = json.load(f)

    results = []
    for inq in sample_inquiries:
        opp = process_inquiry_with_agent(inq)
        results.append(opp)

    return {
        "success": True,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "total_tested": len(results),
        "results": results,
        "dashboard": get_dashboard()
    }

# 4.9 Trạng thái Hệ thống
@app.get("/api/status")
def get_status():
    return {"status": "online", "framework": "FastAPI", "version": "2.0.0"}

# ==============================================================================
# 5. ĐIỀU HƯỚNG GIAO DIỆN WEB & STATIC ASSETS
# ==============================================================================
@app.get("/assets/{asset_path:path}")
def get_static_asset(asset_path: str):
    for candidate in [
        os.path.join(BASE_DIR, "web", "assets", asset_path),
        os.path.join(BASE_DIR, "web", asset_path),
        os.path.join(BASE_DIR, "outputs", asset_path)
    ]:
        if os.path.exists(candidate) and os.path.isfile(candidate):
            return FileResponse(candidate)
    raise HTTPException(status_code=404, detail="Asset not found")

@app.get("/{full_path:path}")
def serve_web_pages(full_path: str):
    if not full_path or full_path == "index.html":
        index_file = os.path.join(BASE_DIR, "web", "index.html")
        if os.path.exists(index_file):
            return FileResponse(index_file)
        return HTMLResponse("<h1>MINH AN B2B AI AGENT</h1>")

    # Kiểm tra xem có phải file tĩnh trong web/ không
    candidate = os.path.join(BASE_DIR, "web", full_path)
    if os.path.exists(candidate) and os.path.isfile(candidate):
        return FileResponse(candidate)

    # Mặc định fallback về index.html cho Single Page Application
    index_file = os.path.join(BASE_DIR, "web", "index.html")
    if os.path.exists(index_file):
        return FileResponse(index_file)
    return HTMLResponse("<h1>MINH AN B2B AI AGENT</h1>")

# ==============================================================================
# 6. BỘ CHẠY ĐÁNH GIÁ DÒNG LỆNH (CLI RUNNER PHỤC VỤ CHẤM THI)
# ==============================================================================
def run_pipeline(data_file_path: str = "data/test_inquiries.json"):
    print("=" * 80)
    print("  HỆ THỐNG AI AGENT XỬ LÝ CƠ HỘI BÁN HÀNG B2B - CÔNG TY MINH AN")
    print("  Học phần: AI301 | Đề 01 | Phiên bản Kiểm thử Tự động")
    print("=" * 80)

    with open("data/products_inventory.json", "r", encoding="utf-8") as f:
        products = json.load(f)
    with open("data/business_policies.json", "r", encoding="utf-8") as f:
        policies = json.load(f)

    if not os.path.exists(data_file_path):
        print(f"[LỖI] Không tìm thấy tệp dữ liệu: {data_file_path}")
        return

    with open(data_file_path, "r", encoding="utf-8") as f:
        inquiries = json.load(f)

    rules_engine = BusinessRulesEngine(policies, products)
    tools = InquiryProcessingTools(rules_engine)
    logger = AuditLogger(log_dir="outputs/logs")
    agent = B2BSalesAgent(tools, policies, logger)

    results = []
    status_counts = {
        "Có thể tiếp tục": 0,
        "Cần bổ sung thông tin": 0,
        "Chưa đáp ứng": 0,
        "Chờ duyệt": 0,
    }
    total_eligible_value = 0.0

    for idx, inq in enumerate(inquiries, 1):
        inq_id = inq.get("inquiry_id", f"REQ-{idx}")
        cust_name = inq.get("customer_name", "Không rõ")
        res = agent.process_inquiry(inq)
        results.append(res)
        st = res["status"]
        status_counts[st] = status_counts.get(st, 0) + 1
        if res["eligible_for_pipeline"]:
            total_eligible_value += res["final_total"]

    print(f"Hoàn thành xử lý {len(inquiries)} cơ hội. Tổng giá trị đủ điều kiện: {total_eligible_value:,.0f} VND")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1].endswith(".json"):
        run_pipeline(sys.argv[1])
    else:
        import uvicorn
        port = int(os.environ.get("PORT", 8080))
        print(f"🚀 MINH AN B2B AI AGENT (FastAPI Server) đang chạy tại: http://localhost:{port}/")
        uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
