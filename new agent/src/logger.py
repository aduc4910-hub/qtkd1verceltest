"""
Audit Trace Logger for Agent Execution
Lưu nhật ký truy vết các bước suy luận, gọi công cụ, áp dụng quy tắc
"""

import json
import os
from datetime import datetime
from typing import Dict, Any, List


class AuditLogger:
    def __init__(self, log_dir: str = "outputs/logs"):
        self.log_dir = log_dir
        try:
            os.makedirs(log_dir, exist_ok=True)
        except Exception:
            self.log_dir = "/tmp/outputs/logs"
            try:
                os.makedirs(self.log_dir, exist_ok=True)
            except Exception:
                pass
        self.traces: List[Dict[str, Any]] = []

    def log_step(
        self,
        inquiry_id: str,
        step_name: str,
        agent_thought: str,
        tool_called: str,
        tool_input: Dict[str, Any],
        tool_output: Dict[str, Any],
        rules_applied: List[str],
        decision: str,
    ):
        timestamp = datetime.now().isoformat()
        entry = {
            "timestamp": timestamp,
            "inquiry_id": inquiry_id,
            "step_name": step_name,
            "agent_thought": agent_thought,
            "tool_called": tool_called,
            "tool_input": tool_input,
            "tool_output": tool_output,
            "rules_applied": rules_applied,
            "decision": decision,
        }
        self.traces.append(entry)

        # Append to JSONL log file
        try:
            jsonl_path = os.path.join(self.log_dir, f"trace_{inquiry_id}.jsonl")
            with open(jsonl_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

            # Global audit log
            global_path = os.path.join(self.log_dir, "audit_trace_all.jsonl")
            with open(global_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except Exception:
            pass

    def export_readable_log(self, inquiry_id: str) -> str:
        filtered = [t for t in self.traces if t["inquiry_id"] == inquiry_id]
        lines = [
            f"# NHẬT KÝ TRUY VẾT THỰC THI AGENT (AUDIT TRACE) - {inquiry_id}",
            f"Thời gian tạo: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            "=" * 70,
        ]
        for idx, t in enumerate(filtered, 1):
            lines.append(f"\n### BƯỚC {idx}: {t['step_name']}")
            lines.append(f"- **Thời gian:** {t['timestamp']}")
            lines.append(f"- **Agent Thought (Suy luận):** {t['agent_thought']}")
            lines.append(f"- **Tool Called (Công cụ gọi):** `{t['tool_called']}`")
            lines.append(f"- **Tool Input:** {json.dumps(t['tool_input'], ensure_ascii=False)}")
            lines.append(f"- **Tool Output Summary:** {json.dumps(t['tool_output'], ensure_ascii=False)}")
            lines.append(f"- **Quy tắc áp dụng:** {', '.join(t['rules_applied']) if t['rules_applied'] else 'N/A'}")
            lines.append(f"- **Kết luận bước:** {t['decision']}")
            lines.append("-" * 50)

        out_txt = "\n".join(lines)
        txt_path = os.path.join(self.log_dir, f"trace_{inquiry_id}.txt")
        with open(txt_path, "w", encoding="utf-8") as f:
            f.write(out_txt)
        return out_txt

