# -*- coding: utf-8 -*-
"""Extract, catalog, and merge Cursor error logs for the community knowledge base."""
from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime
from pathlib import Path

ERROR_PATTERNS = re.compile(
    r"(?i)(\[error\]|ERROR:|ConnectError|Failed to|ECONNRESET|SQLITE_BUSY|"
    r"UNRESPONSIVE|EPERM|timeout|Too many free trial|usage limit|"
    r"Internal Error|AppHang|resource_exhausted|Failed to parse|Agent Execution)",
)

SKIP_NOISE = re.compile(
    r"(?i)(span_started|span_completed|clearErrorDetails|InteractivePermissions)",
)


def data_dir() -> Path:
    p = Path(os.environ.get("LOCALAPPDATA", "")) / "CursorBoost"
    p.mkdir(parents=True, exist_ok=True)
    return p


def catalog_path() -> Path:
    return data_dir() / "error-catalog.json"


def submissions_dir() -> Path:
    p = data_dir() / "submissions"
    p.mkdir(parents=True, exist_ok=True)
    return p


def _fingerprint(text: str) -> str:
    norm = re.sub(r"\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}", "", text)
    norm = re.sub(r"request[Ii]d[=:\"][\w-]+", "", norm)
    norm = re.sub(r"\s+", " ", norm.strip())[:240]
    return hashlib.sha1(norm.encode("utf-8", errors="replace")).hexdigest()[:12]


def extract_errors_from_text(log_text: str, source: str = "") -> list[dict]:
    found: dict[str, dict] = {}
    for line in log_text.splitlines():
        line = line.strip()
        if len(line) < 12 or SKIP_NOISE.search(line):
            continue
        if not ERROR_PATTERNS.search(line):
            continue
        if len(line) > 600:
            line = line[:600] + "..."
        fp = _fingerprint(line)
        if fp in found:
            found[fp]["count"] += 1
            found[fp]["last_seen"] = datetime.now().isoformat(timespec="seconds")
            continue
        found[fp] = {
            "id": fp,
            "message": line,
            "source": source,
            "count": 1,
            "first_seen": datetime.now().isoformat(timespec="seconds"),
            "last_seen": datetime.now().isoformat(timespec="seconds"),
        }
    return list(found.values())


def load_catalog() -> dict:
    p = catalog_path()
    if not p.exists():
        return {"version": 1, "updated_at": "", "errors": [], "sessions_scanned": []}
    try:
        return json.loads(p.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, OSError):
        return {"version": 1, "updated_at": "", "errors": [], "sessions_scanned": []}


def merge_catalog(new_errors: list[dict]) -> dict:
    cat = load_catalog()
    by_id = {e["id"]: e for e in cat.get("errors", [])}
    for e in new_errors:
        eid = e["id"]
        if eid in by_id:
            by_id[eid]["count"] = by_id[eid].get("count", 1) + e.get("count", 1)
            by_id[eid]["last_seen"] = e.get("last_seen", by_id[eid].get("last_seen"))
            if len(e.get("message", "")) > len(by_id[eid].get("message", "")):
                by_id[eid]["message"] = e["message"]
        else:
            by_id[eid] = e
    cat["errors"] = sorted(by_id.values(), key=lambda x: x.get("count", 0), reverse=True)
    cat["updated_at"] = datetime.now().isoformat(timespec="seconds")
    catalog_path().write_text(json.dumps(cat, ensure_ascii=False, indent=2), encoding="utf-8")
    return cat


def save_submission(scan: dict, note: str = "", errors: list[dict] | None = None) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out = submissions_dir() / f"report-{stamp}.json"
    payload = {
        "submitted_at": datetime.now().isoformat(timespec="seconds"),
        "machine": os.environ.get("COMPUTERNAME", ""),
        "user": os.environ.get("USERNAME", ""),
        "note": note,
        "scan": scan,
        "errors": errors or [],
    }
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


def build_github_issue_body(scan: dict, errors: list[dict], note: str = "") -> str:
    lines = [
        "## Cursor 报错反馈",
        "",
        f"- 时间: {scan.get('scanned_at', '')}",
        f"- Cursor 进程: {scan.get('cursor_processes', '?')}",
        f"- state.vscdb: {scan.get('state_vscdb_mb', '?')} MB",
        f"- 日志目录: `{scan.get('log_dir', '')}`",
        "",
    ]
    if note:
        lines += ["## 用户描述", note, ""]
    issues = scan.get("issues") or []
    if issues:
        lines += ["## 匹配到的问题库条目", ""]
        for i in issues:
            lines.append(f"- **{i.get('title')}** ({i.get('fix_mode', '')}) — {i.get('desc', '')}")
        lines.append("")
    if errors:
        lines += ["## 日志报错摘录（前 15 条）", "```"]
        for e in errors[:15]:
            lines.append(e.get("message", "")[:400])
        lines += ["```", ""]
    lines += [
        "## 附件",
        "请附上 Cursor Boost 导出的 `CursorReport-*.zip`",
        "",
        "---",
        "维护者：请更新 `issues.json` 并发布新版本",
    ]
    return "\n".join(lines)
