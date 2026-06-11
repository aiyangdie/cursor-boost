# -*- coding: utf-8 -*-
"""Scan Cursor logs + local state, match known issues from issues.json"""
from __future__ import annotations

import json
import os
import re
from datetime import datetime, timedelta
from pathlib import Path


def app_dir() -> Path:
    return Path(__file__).resolve().parent


def load_issues() -> list[dict]:
    p = app_dir() / "issues.json"
    if not p.exists():
        return []
    return json.loads(p.read_text(encoding="utf-8-sig"))


def cursor_logs_dir() -> Path:
    return Path(os.environ.get("APPDATA", "")) / "Cursor" / "logs"


def list_log_sessions(limit: int = 20) -> list[dict]:
    logs = cursor_logs_dir()
    if not logs.exists():
        return []
    out = []
    for d in sorted([x for x in logs.iterdir() if x.is_dir()], reverse=True)[:limit]:
        files = list(d.rglob("*.log"))
        total = sum(f.stat().st_size for f in files if f.is_file())
        out.append({"name": d.name, "path": str(d), "files": len(files), "size_mb": round(total / 1048576, 2)})
    return out


def collect_all_errors(hours: int = 168, max_bytes: int = 15_000_000) -> tuple[list[dict], list[dict]]:
    """Scan all recent logs, return (errors, sessions). Updates local catalog."""
    from error_catalog import extract_errors_from_text, merge_catalog

    logs = cursor_logs_dir()
    if not logs.exists():
        return [], []
    cutoff = datetime.now() - timedelta(hours=hours)
    all_errors: list[dict] = []
    sessions = list_log_sessions(30)

    total = 0
    for d in sorted(logs.iterdir(), reverse=True):
        if not d.is_dir():
            continue
        try:
            if d.name[:8].isdigit():
                dt = datetime.strptime(d.name[:8], "%Y%m%d")
                if dt.date() < cutoff.date():
                    continue
        except ValueError:
            pass
        for f in d.rglob("*.log"):
            if total >= max_bytes:
                break
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            total += len(text)
            try:
                rel = str(f.relative_to(logs))
            except ValueError:
                rel = str(f)
            all_errors.extend(extract_errors_from_text(text, rel))
        if total >= max_bytes:
            break

    # dedupe across files
    merged: dict[str, dict] = {}
    for e in all_errors:
        eid = e["id"]
        if eid in merged:
            merged[eid]["count"] += e.get("count", 1)
        else:
            merged[eid] = e
    errors = sorted(merged.values(), key=lambda x: x.get("count", 0), reverse=True)
    cat = merge_catalog(errors)
    return errors, sessions


def read_recent_log_text(hours: int = 72, max_bytes: int = 8_000_000) -> str:
    logs = cursor_logs_dir()
    if not logs.exists():
        return ""
    cutoff = datetime.now() - timedelta(hours=hours)
    chunks: list[str] = []
    total = 0
    for d in sorted(logs.iterdir(), reverse=True):
        if not d.is_dir():
            continue
        try:
            # folder name like 20260612T024551
            if d.name[:8].isdigit():
                dt = datetime.strptime(d.name[:8], "%Y%m%d")
                if dt.date() < cutoff.date():
                    continue
        except ValueError:
            pass
        for f in d.rglob("*.log"):
            try:
                data = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            chunks.append(data)
            total += len(data)
            if total >= max_bytes:
                break
        if total >= max_bytes:
            break
    return "\n".join(chunks)


def proc_count() -> int:
    try:
        import subprocess
        r = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "(Get-Process -Name Cursor -EA SilentlyContinue).Count"],
            capture_output=True, text=True, timeout=10,
        )
        return int(r.stdout.strip() or "0")
    except Exception:
        return 0


def count_root_workspaces() -> int:
    ws = Path(os.environ.get("APPDATA", "")) / "Cursor" / "User" / "workspaceStorage"
    if not ws.exists():
        return 0
    n = 0
    for d in ws.iterdir():
        wj = d / "workspace.json"
        if wj.exists() and "/root" in wj.read_text(encoding="utf-8", errors="replace"):
            n += 1
    return n


def state_vscdb_mb() -> float:
    p = Path(os.environ.get("APPDATA", "")) / "Cursor" / "User" / "globalStorage" / "state.vscdb"
    if not p.exists():
        return 0.0
    return round(p.stat().st_size / (1024 * 1024), 1)


def has_stale_locks() -> bool:
    roaming = Path(os.environ.get("APPDATA", "")) / "Cursor"
    for name in ("code.lock",):
        if (roaming / name).exists():
            return True
    vsc = roaming / "User" / "globalStorage" / "storage.json.vsctmp"
    return vsc.exists()


def broken_hooks_local() -> bool:
    for rel in (".cursor/hooks.json", "Downloads/.cursor/hooks.json"):
        p = Path(os.environ.get("USERPROFILE", "")) / rel
        if not p.exists():
            continue
        try:
            json.loads(p.read_text(encoding="utf-8-sig"))
        except (json.JSONDecodeError, OSError):
            return True
    return False


def run_check(name: str) -> bool:
    if name == "proc_count":
        return proc_count() > 12
    if name == "state_vscdb_mb":
        return state_vscdb_mb() > 1500
    if name == "stale_locks":
        return has_stale_locks()
    if name == "broken_hooks":
        return broken_hooks_local()
    return False


def scan() -> dict:
    issues = load_issues()
    log_text = read_recent_log_text()
    log_lower = log_text.lower()
    detected: list[dict] = []
    seen_ids: set[str] = set()

    for issue in issues:
        iid = issue["id"]
        matched = False
        for pat in issue.get("patterns", []):
            if pat.lower() in log_lower or pat in log_text:
                matched = True
                break
        extra = issue.get("check")
        if extra and run_check(extra):
            matched = True
        if iid == "root_workspace" and count_root_workspaces() > 0:
            matched = True
        if matched and iid not in seen_ids:
            seen_ids.add(iid)
            detected.append({
                "id": iid,
                "title": issue["title"],
                "category": issue.get("category", ""),
                "desc": issue.get("desc", ""),
                "severity": issue.get("severity", "low"),
                "fix_action": issue.get("fix_action", ""),
                "fix_label": issue.get("fix_label", "修复"),
                "note": issue.get("note", ""),
                "manual_only": issue.get("manual_only", False),
                "fix_mode": issue.get("fix_mode", "hot"),
            })

    # sort: high first
    order = {"high": 0, "medium": 1, "low": 2}
    detected.sort(key=lambda x: order.get(x["severity"], 9))

    latest_log = ""
    sessions = list_log_sessions(10)
    if cursor_logs_dir().exists():
        dirs = sorted([d for d in cursor_logs_dir().iterdir() if d.is_dir()], reverse=True)
        if dirs:
            latest_log = str(dirs[0])

    errors, _ = collect_all_errors(hours=168)

    return {
        "scanned_at": datetime.now().isoformat(timespec="seconds"),
        "log_dir": str(cursor_logs_dir()),
        "latest_log_session": latest_log,
        "log_sessions": sessions,
        "cursor_processes": proc_count(),
        "root_workspaces": count_root_workspaces(),
        "state_vscdb_mb": state_vscdb_mb(),
        "stale_locks": has_stale_locks(),
        "issues": detected,
        "issue_count": len(detected),
        "error_count": len(errors),
        "errors_sample": errors[:20],
    }


if __name__ == "__main__":
    out = Path(os.environ.get("TEMP", ".")) / "cursor-boost-scan.json"
    result = scan()
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
