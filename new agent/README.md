# HỆ THỐNG AI AGENT XỬ LÝ CƠ HỘI BÁN HÀNG B2B - CÔNG TY MINH AN
**Học phần:** AI301 | Đề 01 | Đại học FPT  
**Công nghệ:** Agentic Architecture (ReAct Loop + Tool Calling + Policy Guardrails + Audit Trace Logging)

---

## 1. Cấu trúc thư mục dự án
```text
.
├── data/
│   ├── products_inventory.json     # Danh mục sản phẩm, bảng giá niêm yết & tồn kho khả dụng
│   ├── business_policies.json      # Quy tắc chiết khấu, phân quyền phê duyệt & điều kiện SLA
│   ├── test_inquiries.json         # Bộ 7 test cases (chuẩn, thiếu dữ liệu, ranh giới quy tắc)
│   └── test_exam_sample.json       # Bộ dữ liệu mẫu dùng cho buổi thi thực hành
├── src/
│   ├── models.py                   # Cấu trúc dữ liệu (Dataclasses: Inquiry, Dossier, Results)
│   ├── rules.py                    # Bộ quy tắc nghiệp vụ (Rules Engine, Thẩm quyền, Chiết khấu)
│   ├── tools.py                    # 4 Kỹ năng nghiệp vụ độc lập (Skills/Tools)
│   ├── logger.py                   # Nhật ký truy vết thực thi (Audit Trace Logger)
│   └── agent.py                    # Lõi điều phối AI Agent (ReAct Loop, Branching)
├── outputs/
│   ├── dossiers/                   # Hồ sơ cơ hội (Opportunity Dossier .md)
│   ├── drafts/                     # Bản nháp phản hồi KH (.txt) & Phiếu duyệt (.txt)
│   ├── logs/                       # Nhật ký truy vết từng bước (Audit Trace Logs)
│   ├── summary_dashboard.json      # Bảng tổng hợp số liệu JSON
│   └── summary_dashboard.md        # Bảng tổng hợp số liệu Markdown
├── main.py                         # Điểm chạy Python tiêu chuẩn
├── run_agent.ps1                   # Runner PowerShell chạy trực tiếp trên Windows (Zero Setup)
├── requirements.txt                # Khai báo môi trường
└── README.md                       # Tài liệu hướng dẫn sử dụng
```

---

## 2. Hướng dẫn chạy chương trình

### Cách 1: Chạy trực tiếp trên Windows (Không cần cài đặt Python)
Mở PowerShell tại thư mục dự án và chạy:
```powershell
# Chạy với bộ dữ liệu kiểm thử mặc định (7 test cases):
powershell -ExecutionPolicy Bypass -File .\run_agent.ps1

# Chạy với bộ dữ liệu thi bất kỳ do Giảng viên cung cấp:
powershell -ExecutionPolicy Bypass -File .\run_agent.ps1 -DataPath "data\test_exam_sample.json"
```

### Cách 2: Chạy bằng Python (Nếu máy có cài Python)
```bash
# Chạy với bộ dữ liệu mặc định:
python main.py

# Chạy với bộ dữ liệu mới:
python main.py data/test_exam_sample.json
```

---

## 3. Các kết quả đầu ra được tự động tạo lập
1. **Hồ sơ cơ hội (`outputs/dossiers/dossier_*.md`):** Thể hiện kết quả đối chiếu tồn kho, bảng giá, lead time, thẩm quyền và bước xử lý tiếp theo.
2. **Bản nháp phản hồi khách hàng (`outputs/drafts/draft_response_*.txt`):**
   - *Nếu thiếu thông tin:* Email đề nghị khách hàng làm rõ.
   - *Nếu không khả thi:* Email từ chối lịch sự và tư vấn giải pháp thay thế.
   - *Nếu chờ duyệt:* Dự thảo báo giá chờ duyệt.
   - *Nếu hợp lệ:* Báo giá chính thức và cam kết thời gian giao hàng.
3. **Phiếu chuyển duyệt (`outputs/drafts/approval_ticket_*.txt`):** Tạo tự động khi chiết khấu > 10% hoặc đơn hàng > 200M VND gửi Trưởng phòng Kinh doanh.
4. **Nhật ký truy vết thực thi (`outputs/logs/trace_*.txt`):** Ghi rõ Thought - Action (Tool Called) - Observation (Tool Output) - Quy tắc áp dụng - Quyết định.
5. **Bảng tổng hợp (`outputs/summary_dashboard.md` & `.json`):** Phân loại 4 trạng thái và tổng giá trị các cơ hội đủ điều kiện.

