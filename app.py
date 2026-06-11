# -*- coding: utf-8 -*-
"""
Cursor Boost v1.6 — 万能 Cursor 问题修复系统
读日志 · 知识库 · 一键修 · 共建 GitHub
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path

try:
    import customtkinter as ctk
except ImportError:
    print("pip install customtkinter")
    sys.exit(1)

# ── Theme ──────────────────────────────────────────────
APP_NAME = "Cursor Boost"
APP_VERSION = "1.6.0"
REPO = "https://github.com/aiyangdie/cursor-boost"

C = {
    "bg": "#0b0d12",
    "sidebar": "#12151c",
    "card": "#181c26",
    "card2": "#1f2430",
    "border": "#2a3142",
    "text": "#e8eaed",
    "muted": "#8b93a7",
    "accent": "#6366f1",
    "accent_h": "#818cf8",
    "teal": "#14b8a6",
    "orange": "#f59e0b",
    "red": "#ef4444",
    "green": "#22c55e",
}
SEV = {"high": C["red"], "medium": C["orange"], "low": "#60a5fa"}
MODE = {"hot": ("热修复", C["teal"]), "reload": ("Reload", "#38bdf8"),
        "restart": ("需重启", C["orange"]), "manual": ("仅说明", C["muted"])}

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")


def app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys._MEIPASS)  # type: ignore
    return Path(__file__).resolve().parent


def run_engine(action: str) -> tuple[bool, list[str]]:
    engine = app_dir() / "engine.ps1"
    if not engine.exists():
        engine = Path(__file__).resolve().parent / "engine.ps1"
    try:
        proc = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
             "-File", str(engine), "-Action", action, "-Quiet"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300,
        )
        lines = [ln for ln in (proc.stdout or "").splitlines() if ln.strip()]
        rp = Path(os.environ.get("TEMP", ".")) / "cursor-boost-action.json"
        if rp.exists():
            try:
                lines = json.loads(rp.read_text(encoding="utf-8-sig")).get("lines") or lines
            except Exception:
                pass
        return proc.returncode == 0, lines
    except Exception as e:
        return False, [str(e)]


def scan_logs() -> dict:
    try:
        import importlib.util
        sp = app_dir() / "log_scanner.py"
        if not sp.exists():
            sp = Path(__file__).resolve().parent / "log_scanner.py"
        spec = importlib.util.spec_from_file_location("log_scanner", sp)
        if spec and spec.loader:
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            result = mod.scan()
            Path(os.environ.get("TEMP", ".")).joinpath("cursor-boost-scan.json").write_text(
                json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
            _write_github_body(result)
            return result
    except Exception as e:
        return {"issues": [], "errors_sample": [], "error": str(e), "issue_count": 0, "error_count": 0}
    return {"issues": [], "errors_sample": [], "issue_count": 0, "error_count": 0}


def load_knowledge() -> list[dict]:
    p = app_dir() / "issues.json"
    if not p.exists():
        p = Path(__file__).resolve().parent / "issues.json"
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8-sig"))
    return []


def _write_github_body(scan: dict):
    try:
        import importlib.util
        ep = app_dir() / "error_catalog.py"
        if not ep.exists():
            ep = Path(__file__).resolve().parent / "error_catalog.py"
        spec = importlib.util.spec_from_file_location("error_catalog", ep)
        if spec and spec.loader:
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            body = mod.build_github_issue_body(
                scan, scan.get("errors_sample") or [], "")
            Path(os.environ.get("TEMP", ".")).joinpath("cursor-boost-github-issue.md").write_text(
                body, encoding="utf-8")
    except Exception:
        pass


class StatCard(ctk.CTkFrame):
    def __init__(self, master, title: str, value: str, color: str, **kw):
        super().__init__(master, fg_color=C["card"], corner_radius=12,
                         border_width=1, border_color=C["border"], **kw)
        ctk.CTkLabel(self, text=title, font=ctk.CTkFont(size=11), text_color=C["muted"]).pack(
            anchor="w", padx=16, pady=(14, 0))
        self.val = ctk.CTkLabel(self, text=value, font=ctk.CTkFont(size=28, weight="bold"), text_color=color)
        self.val.pack(anchor="w", padx=16, pady=(4, 14))

    def set(self, v: str):
        self.val.configure(text=v)


class NavBtn(ctk.CTkButton):
    def __init__(self, master, text, icon, command, **kw):
        super().__init__(
            master, text=f"  {icon}  {text}", anchor="w",
            height=42, corner_radius=10, fg_color="transparent",
            text_color=C["muted"], hover_color=C["card2"],
            font=ctk.CTkFont(size=13), command=command, **kw)
        self._active = False

    def set_active(self, on: bool):
        self._active = on
        if on:
            self.configure(fg_color=C["accent"], text_color="white")
        else:
            self.configure(fg_color="transparent", text_color=C["muted"])


def health_score(data: dict) -> int:
    s = 100
    s -= min(36, data.get("issue_count", 0) * 6)
    proc = data.get("cursor_processes", 0) or 0
    s -= min(18, max(0, proc - 8) * 3)
    if (data.get("state_vscdb_mb") or 0) > 1500:
        s -= 12
    if data.get("stale_locks"):
        s -= 10
    return max(0, min(100, s))


def health_label(score: int) -> tuple[str, str]:
    if score >= 85:
        return "健康", C["green"]
    if score >= 60:
        return "一般", C["orange"]
    return "需修复", C["red"]


class CursorBoostApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.configure(fg_color=C["bg"])
        self.title(f"{APP_NAME} v{APP_VERSION}")
        self.geometry("960x720")
        self.minsize(880, 640)

        self._busy = False
        self._scan: dict = {}
        self._all_errors: list = []
        self._knowledge_items: list = []
        self._nav_btns: list[NavBtn] = []
        self._pages: dict[str, ctk.CTkFrame] = {}
        self._issue_widgets: list = []

        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        self._build_sidebar()
        self._main = ctk.CTkFrame(self, fg_color="transparent")
        self._main.grid(row=0, column=1, sticky="nsew", padx=(0, 12), pady=12)
        self._main.grid_columnconfigure(0, weight=1)
        self._main.grid_rowconfigure(0, weight=1)

        for name in ("overview", "detect", "logs", "knowledge", "tools", "community"):
            f = ctk.CTkFrame(self._main, fg_color="transparent")
            f.grid(row=0, column=0, sticky="nsew")
            f.grid_columnconfigure(0, weight=1)
            f.grid_rowconfigure(0, weight=1)
            self._pages[name] = f

        self._build_overview()
        self._build_detect()
        self._build_logs()
        self._build_knowledge()
        self._build_tools()
        self._build_community()
        self._build_log_bar()

        self._show_page("overview")
        self._log("系统启动，正在全量扫描 Cursor 日志…")
        self.after(200, self.refresh_all)

    # ── Sidebar ──
    def _build_sidebar(self):
        sb = ctk.CTkFrame(self, width=220, fg_color=C["sidebar"], corner_radius=0)
        sb.grid(row=0, column=0, sticky="nsew")
        sb.grid_propagate(False)

        brand = ctk.CTkFrame(sb, fg_color=C["accent"], corner_radius=14, width=44, height=44)
        brand.pack(anchor="w", padx=20, pady=(24, 8))
        ctk.CTkLabel(brand, text="⚡", font=ctk.CTkFont(size=22)).place(relx=0.5, rely=0.5, anchor="center")
        ctk.CTkLabel(sb, text=APP_NAME, font=ctk.CTkFont(size=18, weight="bold")).pack(anchor="w", padx=20)
        ctk.CTkLabel(sb, text=f"v{APP_VERSION} · 共建系统", font=ctk.CTkFont(size=10), text_color=C["muted"]).pack(anchor="w", padx=20, pady=(0, 20))

        nav_items = [
            ("overview", "概览", "◆"),
            ("detect", "问题检测", "●"),
            ("logs", "全部日志", "≡"),
            ("knowledge", "知识库", "📖"),
            ("tools", "修复工具", "🔧"),
            ("community", "共建反馈", "↗"),
        ]
        for pid, label, icon in nav_items:
            b = NavBtn(sb, label, icon, lambda p=pid: self._show_page(p))
            b.pack(fill="x", padx=12, pady=2)
            self._nav_btns.append((pid, b))

        ctk.CTkFrame(sb, height=1, fg_color=C["border"]).pack(fill="x", padx=16, pady=16)
        ctk.CTkButton(sb, text="  智能热修复", height=40, fg_color=C["teal"],
                      font=ctk.CTkFont(size=13, weight="bold"),
                      command=lambda: self._run("SmartFix")).pack(fill="x", padx=12, pady=4)
        ctk.CTkButton(sb, text="  导出诊断包", height=36, fg_color=C["accent"],
                      command=lambda: self._run("ExportReport")).pack(fill="x", padx=12, pady=4)
        ctk.CTkButton(sb, text="  GitHub 仓库", height=32, fg_color=C["card2"],
                      command=lambda: webbrowser.open(REPO)).pack(fill="x", padx=12, pady=(4, 16))

    def _show_page(self, page_id: str):
        for pid, btn in self._nav_btns:
            btn.set_active(pid == page_id)
        for pid, frame in self._pages.items():
            frame.grid_remove()
        self._pages[page_id].grid()

    def _build_log_bar(self):
        bar = ctk.CTkFrame(self._main, fg_color=C["card"], corner_radius=10, height=100)
        bar.grid(row=1, column=0, sticky="ew", pady=(8, 0))
        bar.grid_columnconfigure(0, weight=1)
        ctk.CTkLabel(bar, text="控制台", font=ctk.CTkFont(size=10, weight="bold"), text_color=C["muted"]).grid(
            row=0, column=0, sticky="w", padx=10, pady=(6, 0))
        self.console = ctk.CTkTextbox(bar, height=56, font=ctk.CTkFont(family="Consolas", size=10),
                                      fg_color="#0e1018", border_width=0)
        self.console.grid(row=1, column=0, sticky="ew", padx=8, pady=(2, 8))
        self.status = ctk.CTkLabel(bar, text="就绪", font=ctk.CTkFont(size=10), text_color=C["muted"])
        self.status.grid(row=2, column=0, sticky="w", padx=10, pady=(0, 2))
        self.progress = ctk.CTkProgressBar(bar, height=4, progress_color=C["accent"])
        self.progress.grid(row=3, column=0, sticky="ew", padx=10, pady=(0, 8))
        self.progress.set(0)

    def _log(self, msg: str):
        self.console.insert("end", msg + "\n")
        self.console.see("end")

    def _set_busy(self, busy: bool, msg: str = ""):
        self._busy = busy
        self.status.configure(text=msg or ("运行中…" if busy else f"就绪 · v{APP_VERSION}"))
        if busy:
            self.progress.start()
        else:
            self.progress.stop()
            self.progress.set(0)

    # ── Overview ──
    def _build_overview(self):
        p = self._pages["overview"]
        scroll = ctk.CTkScrollableFrame(p, fg_color="transparent")
        scroll.pack(fill="both", expand=True)
        scroll.grid_columnconfigure((0, 1, 2, 3, 4), weight=1)

        self.card_health = StatCard(scroll, "健康度", "—", C["green"])
        self.card_health.grid(row=0, column=0, padx=4, pady=4, sticky="ew")
        self.card_issues = StatCard(scroll, "匹配问题", "—", C["red"])
        self.card_issues.grid(row=0, column=1, padx=4, pady=4, sticky="ew")
        self.card_errors = StatCard(scroll, "日志报错", "—", C["orange"])
        self.card_errors.grid(row=0, column=2, padx=4, pady=4, sticky="ew")
        self.card_proc = StatCard(scroll, "Cursor 进程", "—", C["teal"])
        self.card_proc.grid(row=0, column=3, padx=4, pady=4, sticky="ew")
        self.card_db = StatCard(scroll, "DB 大小 MB", "—", C["accent"])
        self.card_db.grid(row=0, column=4, padx=4, pady=4, sticky="ew")

        flow = ctk.CTkFrame(scroll, fg_color=C["card"], corner_radius=14, border_width=1, border_color=C["border"])
        flow.grid(row=1, column=0, columnspan=5, sticky="ew", padx=4, pady=12)
        ctk.CTkLabel(flow, text="修复流程（尽量少重启）", font=ctk.CTkFont(size=14, weight="bold")).pack(
            anchor="w", padx=20, pady=(16, 8))
        steps = "① 智能热修复  →  ② Reload Window (Ctrl+Shift+P)  →  ③ 重启 Cursor  →  ④ 一键全修"
        ctk.CTkLabel(flow, text=steps, font=ctk.CTkFont(size=12), text_color=C["muted"]).pack(
            anchor="w", padx=20, pady=(0, 16))

        self.overview_issues = ctk.CTkFrame(flow, fg_color="transparent")
        self.overview_issues.pack(fill="x", padx=16, pady=(0, 16))

    # ── Detect ──
    def _build_detect(self):
        p = self._pages["detect"]
        top = ctk.CTkFrame(p, fg_color="transparent")
        top.pack(fill="x", pady=(0, 8))
        ctk.CTkButton(top, text="重新扫描", width=100, fg_color=C["card2"], command=self.refresh_all).pack(side="left", padx=4)
        ctk.CTkButton(top, text="打开日志目录", width=110, fg_color=C["card2"],
                      command=lambda: self._run("OpenLogs")).pack(side="left", padx=4)
        self.detect_info = ctk.CTkLabel(top, text="", text_color=C["muted"])
        self.detect_info.pack(side="left", padx=12)

        self.detect_scroll = ctk.CTkScrollableFrame(p, fg_color="transparent")
        self.detect_scroll.pack(fill="both", expand=True)
        self.detect_scroll.grid_columnconfigure(0, weight=1)
        self.detect_empty = ctk.CTkLabel(self.detect_scroll, text="扫描中…", text_color=C["muted"])
        self.detect_empty.grid(row=0, column=0, pady=40)

    # ── Logs ──
    def _build_logs(self):
        p = self._pages["logs"]
        top = ctk.CTkFrame(p, fg_color="transparent")
        top.pack(fill="x", pady=(0, 8))
        ctk.CTkLabel(top, text="从全部 Cursor 日志提取的报错（去重合并）", font=ctk.CTkFont(size=13, weight="bold")).pack(side="left")
        self.log_search = ctk.CTkEntry(top, width=180, placeholder_text="搜索报错…")
        self.log_search.pack(side="right", padx=4)
        self.log_search.bind("<KeyRelease>", lambda e: self._filter_logs())
        ctk.CTkButton(top, text="打开报错目录", width=100, fg_color=C["card2"],
                      command=lambda: self._run("OpenCatalog")).pack(side="right", padx=4)
        ctk.CTkButton(top, text="刷新", width=70, fg_color=C["accent"], command=self.refresh_all).pack(side="right")

        self.logs_box = ctk.CTkTextbox(p, font=ctk.CTkFont(family="Consolas", size=10),
                                       fg_color=C["card"], border_color=C["border"], border_width=1)
        self.logs_box.pack(fill="both", expand=True)

    # ── Knowledge ──
    def _build_knowledge(self):
        p = self._pages["knowledge"]
        top = ctk.CTkFrame(p, fg_color="transparent")
        top.pack(fill="x", pady=(0, 8))
        ctk.CTkLabel(top, text="已知问题与解决方案（issues.json）", font=ctk.CTkFont(size=13, weight="bold")).pack(side="left")
        self.knowledge_search = ctk.CTkEntry(top, width=160, placeholder_text="搜索知识库…")
        self.knowledge_search.pack(side="right", padx=4)
        self.knowledge_search.bind("<KeyRelease>", lambda e: self._filter_knowledge())
        ctk.CTkButton(top, text="编辑 JSON", width=90, fg_color=C["card2"], command=self._open_issues_json).pack(side="right")

        self.knowledge_scroll = ctk.CTkScrollableFrame(p, fg_color="transparent")
        self.knowledge_scroll.pack(fill="both", expand=True)
        self.knowledge_scroll.grid_columnconfigure(0, weight=1)
        self._knowledge_items = load_knowledge()
        self._render_knowledge(self._knowledge_items)

    # ── Tools ──
    def _build_tools(self):
        p = self._pages["tools"]
        scroll = ctk.CTkScrollableFrame(p, fg_color="transparent")
        scroll.pack(fill="both", expand=True)
        scroll.grid_columnconfigure((0, 1, 2), weight=1)
        groups = [
            ("不重启", [
                ("智能热修复", "SmartFix", C["teal"]),
                ("热修复", "FixLive", C["accent"]),
                ("Reload 说明", "ReloadWindowHelp", "#38bdf8"),
                ("修 SSH", "FixSsh", "#3b82f6"),
                ("修 settings", "FixSettings", "#6366f1"),
                ("清 /root", "CleanRoot", "#a855f7"),
            ]),
            ("需关 Cursor", [
                ("清理缓存", "CleanCache", "#8b5cf6"),
                ("清锁文件", "FixLocks", C["red"]),
                ("一键全修", "FixFull", C["green"]),
                ("修闪退", "FixFlashExit", C["orange"]),
                ("深度清理", "DeepClean", "#64748b"),
                ("换号清登录", "ClearAuthCache", "#dc2626"),
            ]),
            ("其他", [
                ("重启 Cursor", "RestartCursor", C["orange"]),
                ("修 hooks", "FixHooks", "#475569"),
                ("修远程 hooks", "FixRemote", "#0d9488"),
                ("诊断", "Diagnose", "#0891b2"),
                ("下载 Cursor", "OpenDownload", "#6b7280"),
                ("联系官方", "OpenSupport", "#6b7280"),
            ]),
        ]
        row = 0
        for gtitle, buttons in groups:
            ctk.CTkLabel(scroll, text=gtitle, font=ctk.CTkFont(size=12, weight="bold"),
                         text_color=C["accent"]).grid(row=row, column=0, columnspan=3, sticky="w", pady=(12, 6), padx=4)
            row += 1
            for i, (label, action, color) in enumerate(buttons):
                c = i % 3
                r = row + i // 3
                ctk.CTkButton(scroll, text=label, height=44, fg_color=color,
                              command=lambda a=action: self._tool_action(a)).grid(
                    row=r, column=c, padx=4, pady=4, sticky="ew")
            row += (len(buttons) + 2) // 3

    def _tool_action(self, action: str):
        confirms = {"CleanCache": "需先关闭 Cursor", "FixFull": "关闭并全面修复？",
                    "FixLocks": "关闭 Cursor 清锁？", "ClearAuthCache": "关闭并清登录？",
                    "DeepClean": "深度清理？", "FixFlashExit": "disable-gpu 重启？"}
        self._dispatch_fix(action, confirm=confirms.get(action))

    # ── Community ──
    def _build_community(self):
        p = self._pages["community"]
        scroll = ctk.CTkScrollableFrame(p, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="共建 Cursor 万能问题库", font=ctk.CTkFont(size=18, weight="bold")).pack(anchor="w", pady=(0, 4))
        ctk.CTkLabel(scroll, text="你的每一次报错，都会让下一个人一键修好", text_color=C["muted"]).pack(anchor="w", pady=(0, 16))

        card = ctk.CTkFrame(scroll, fg_color=C["card"], corner_radius=14, border_width=1, border_color=C["border"])
        card.pack(fill="x", pady=8)
        for t in [
            "1. 报错截图（清晰，含 Request ID）",
            "2. 导出诊断包 zip",
            "3. 本地保存 或 提交 GitHub Issue",
            "4. Cursor Agent 读日志 → 更新 issues.json → 发布",
        ]:
            ctk.CTkLabel(card, text=t, font=ctk.CTkFont(size=12)).pack(anchor="w", padx=20, pady=5)
        ctk.CTkLabel(card, text="").pack(pady=4)

        ctk.CTkLabel(scroll, text="补充说明（可选）", font=ctk.CTkFont(size=11), text_color=C["muted"]).pack(anchor="w", pady=(12, 4))
        self.note_box = ctk.CTkTextbox(scroll, height=70, fg_color=C["card2"], border_color=C["border"], border_width=1)
        self.note_box.pack(fill="x", pady=4)

        bf = ctk.CTkFrame(scroll, fg_color="transparent")
        bf.pack(fill="x", pady=12)
        ctk.CTkButton(bf, text="保存到本机", height=44, fg_color=C["teal"],
                      command=self._save_local).pack(side="left", fill="x", expand=True, padx=(0, 4))
        ctk.CTkButton(bf, text="导出 zip", height=44, fg_color=C["accent"],
                      command=lambda: self._run("ExportReport")).pack(side="left", fill="x", expand=True, padx=4)
        ctk.CTkButton(bf, text="GitHub Issue", height=44, fg_color="#24292f",
                      command=self._github_submit).pack(side="left", fill="x", expand=True, padx=(4, 0))

        ctk.CTkButton(scroll, text="打开本机提交记录", fg_color=C["card2"],
                      command=lambda: self._run("OpenSubmissions")).pack(fill="x", pady=4)
        ctk.CTkButton(scroll, text="复制 Cursor 维护提示词", fg_color=C["card2"],
                      command=self._copy_prompt).pack(fill="x", pady=4)

    # ── Data ──
    def refresh_all(self):
        if self._busy:
            return

        def worker():
            self._set_busy(True, "全量扫描 Cursor 日志…")
            data = scan_logs()
            self.after(0, lambda: self._apply_scan(data))
            self.after(0, lambda: self._set_busy(False))

        threading.Thread(target=worker, daemon=True).start()

    def _apply_scan(self, data: dict):
        self._scan = data
        ni = data.get("issue_count", 0)
        ne = data.get("error_count", 0)
        hs = health_score(data)
        hl, hc = health_label(hs)
        self.card_health.set(f"{hs}")
        self.card_health.val.configure(text_color=hc)
        self.card_issues.set(str(ni))
        self.card_errors.set(str(ne))
        self.card_proc.set(str(data.get("cursor_processes", "?")))
        self.card_db.set(str(data.get("state_vscdb_mb", "?")))
        self.detect_info.configure(text=f"健康 {hl} · 日志会话 {len(data.get('log_sessions') or [])} 个")
        self._all_errors = data.get("errors_sample") or []
        self._render_detect(data.get("issues") or [])
        self._render_overview(data.get("issues") or [], hs, hl)
        self._filter_logs()
        self._log(f"扫描完成：健康度 {hs} · {ni} 问题 · {ne} 类报错")

    def _render_overview(self, issues: list, score: int = 100, label: str = "健康"):
        for w in self.overview_issues.winfo_children():
            w.destroy()
        ctk.CTkLabel(self.overview_issues, text=f"当前状态：{label}（{score}/100）",
                     font=ctk.CTkFont(size=12, weight="bold"),
                     text_color=health_label(score)[1]).pack(anchor="w", pady=(0, 8))
        if not issues:
            ctk.CTkLabel(self.overview_issues, text="无匹配已知问题，可点「智能热修复」预防性维护",
                         text_color=C["green"]).pack(anchor="w")
            return
        for iss in issues[:6]:
            ctk.CTkLabel(self.overview_issues, text=f"• {iss['title']}",
                         text_color=SEV.get(iss.get("severity", "low"), C["text"]),
                         font=ctk.CTkFont(size=12)).pack(anchor="w", pady=2)

    def _render_detect(self, issues: list):
        for w in self._issue_widgets:
            w.destroy()
        self._issue_widgets.clear()
        if not issues:
            self.detect_empty.configure(text="未发现已知问题")
            self.detect_empty.grid(row=0, column=0, pady=40)
            return
        self.detect_empty.grid_remove()
        for i, iss in enumerate(issues):
            self._issue_widgets.append(self._make_issue_card(self.detect_scroll, i, iss))

    def _make_issue_card(self, parent, row: int, iss: dict) -> ctk.CTkFrame:
        sev = iss.get("severity", "low")
        color = SEV.get(sev, C["muted"])
        fm = iss.get("fix_mode", "hot")
        ml, mc = MODE.get(fm, ("", C["muted"]))

        card = ctk.CTkFrame(parent, fg_color=C["card"], corner_radius=12, border_width=1, border_color=C["border"])
        card.grid(row=row, column=0, sticky="ew", padx=2, pady=4)

        hdr = ctk.CTkFrame(card, fg_color="transparent")
        hdr.pack(fill="x", padx=16, pady=(12, 4))
        ctk.CTkLabel(hdr, text=iss["title"], font=ctk.CTkFont(size=14, weight="bold"), text_color=color).pack(side="left")
        ctk.CTkLabel(hdr, text=f" {ml} ", font=ctk.CTkFont(size=10), text_color=mc,
                     fg_color=C["card2"], corner_radius=6).pack(side="right")

        ctk.CTkLabel(card, text=iss.get("desc", ""), font=ctk.CTkFont(size=11),
                     text_color=C["muted"], wraplength=620, justify="left").pack(anchor="w", padx=16)
        if iss.get("note"):
            ctk.CTkLabel(card, text=iss["note"], font=ctk.CTkFont(size=10),
                         text_color=C["orange"], wraplength=620).pack(anchor="w", padx=16, pady=2)

        ctk.CTkButton(card, text=iss.get("fix_label", "修复"), width=120, height=32, fg_color=color,
                      command=lambda a=iss.get("fix_action", ""): self._dispatch_fix(a)).pack(
            anchor="w", padx=16, pady=(8, 12))
        return card

    def _filter_logs(self):
        q = (self.log_search.get() if hasattr(self, "log_search") else "").strip().lower()
        errs = self._all_errors
        if q:
            errs = [e for e in errs if q in e.get("message", "").lower() or q in e.get("source", "").lower()]
        self._render_logs(errs, self._scan.get("error_count", len(errs)))

    def _filter_knowledge(self):
        q = (self.knowledge_search.get() if hasattr(self, "knowledge_search") else "").strip().lower()
        items = self._knowledge_items
        if q:
            items = [i for i in items if q in i.get("title", "").lower() or q in i.get("desc", "").lower()
                     or q in i.get("category", "").lower()]
        self._render_knowledge(items)

    def _render_logs(self, errors: list, total: int):
        self.logs_box.delete("1.0", "end")
        if not errors:
            self.logs_box.insert("end", "暂无报错记录\n")
            return
        self.logs_box.insert("end", f"共 {total} 类报错（显示前 {len(errors)} 条）\n{'='*60}\n\n")
        for e in errors:
            cnt = e.get("count", 1)
            src = e.get("source", "")
            msg = e.get("message", "")
            self.logs_box.insert("end", f"[×{cnt}] {src}\n{msg}\n\n")

    def _render_knowledge(self, items: list | None = None):
        for w in self.knowledge_scroll.winfo_children():
            w.destroy()
        items = items if items is not None else self._knowledge_items
        if not items:
            ctk.CTkLabel(self.knowledge_scroll, text="无匹配条目", text_color=C["muted"]).grid(row=0, column=0, pady=20)
            return
        for i, iss in enumerate(items):
            fm = iss.get("fix_mode", "hot")
            ml, mc = MODE.get(fm, ("", C["muted"]))
            card = ctk.CTkFrame(self.knowledge_scroll, fg_color=C["card"], corner_radius=10,
                                border_width=1, border_color=C["border"])
            card.grid(row=i, column=0, sticky="ew", pady=3, padx=2)
            hdr = ctk.CTkFrame(card, fg_color="transparent")
            hdr.pack(fill="x", padx=14, pady=(10, 2))
            ctk.CTkLabel(hdr, text=iss.get("title", ""), font=ctk.CTkFont(size=13, weight="bold")).pack(side="left")
            ctk.CTkLabel(hdr, text=f"{iss.get('category','')} · {ml}", font=ctk.CTkFont(size=10),
                         text_color=mc).pack(side="right")
            ctk.CTkLabel(card, text=iss.get("desc", ""), font=ctk.CTkFont(size=11),
                         text_color=C["muted"], wraplength=640, justify="left").pack(anchor="w", padx=14, pady=(0, 10))

    def _dispatch_fix(self, action: str, *, confirm: str | None = None):
        from tkinter import messagebox
        if not action:
            return
        if confirm:
            if not messagebox.askyesno("确认", confirm):
                return
        if action == "TrialLimitHelp":
            self._run("TrialLimitHelp")
            messagebox.showinfo("试用限制", "本机试用过多，需 Pro 或联系官方（附 Request ID）")
        elif action == "UsageLimitHelp":
            self._run("UsageLimitHelp")
            messagebox.showinfo("额度用尽", "Agent 额度用完，等重置 / Pro / 换号")
        elif action == "FixRemote":
            if messagebox.askyesno("远程修复", "打开 SSH 修远程 hooks？"):
                self._run("FixRemote")
        elif action == "ReloadWindowHelp":
            self._run("ReloadWindowHelp", silent=True)
            messagebox.showinfo("Reload", "Ctrl+Shift+P → Reload Window")
        elif action == "SmartFix":
            self._run("SmartFix")
            messagebox.showinfo("完成", "已热修复 → 请在 Cursor Reload Window")
        else:
            self._run(action)

    def _run(self, action: str, *, silent: bool = False):
        if self._busy:
            return

        def worker():
            self._set_busy(True, f"{action}…")
            ok, lines = run_engine(action)

            def done():
                self._set_busy(False)
                for ln in lines:
                    self._log(ln)
                if not silent and lines:
                    self._log(f"--- {action} {'OK' if ok else 'FAIL'} ---")
                if action in ("FixLive", "FixFull", "SmartFix", "ExportReport", "CleanRoot"):
                    self.after(600, self.refresh_all)
            self.after(0, done)

        threading.Thread(target=worker, daemon=True).start()

    def _save_local(self):
        note = self.note_box.get("1.0", "end").strip()
        try:
            import importlib.util
            ep = app_dir() / "error_catalog.py"
            spec = importlib.util.spec_from_file_location("error_catalog", ep)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            path = mod.save_submission(self._scan, note, self._scan.get("errors_sample") or [])
            self._log(f"已保存本机报告: {path}")
            from tkinter import messagebox
            messagebox.showinfo("已保存", f"本机记录:\n{path}")
        except Exception as e:
            self._log(f"保存失败: {e}")

    def _github_submit(self):
        note = self.note_box.get("1.0", "end").strip()
        try:
            import importlib.util
            ep = app_dir() / "error_catalog.py"
            spec = importlib.util.spec_from_file_location("error_catalog", ep)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            body = mod.build_github_issue_body(self._scan, self._scan.get("errors_sample") or [], note)
            Path(os.environ.get("TEMP", ".")).joinpath("cursor-boost-github-issue.md").write_text(body, encoding="utf-8")
            self.clipboard_clear()
            self.clipboard_append(body[:8000])
        except Exception:
            pass
        self._run("ExportReport")
        self._run("OpenGitHubIssue")
        self._log("已复制 Issue 正文 + 打开 GitHub，请粘贴并上传 zip")

    def _copy_prompt(self):
        p = app_dir() / "docs" / "CURSOR_MAINTAIN_PROMPT.md"
        if p.exists():
            self.clipboard_clear()
            self.clipboard_append(p.read_text(encoding="utf-8"))
            self._log("维护提示词已复制")

    def _open_issues_json(self):
        p = app_dir() / "issues.json"
        if not p.exists():
            p = Path(__file__).resolve().parent / "issues.json"
        if p.exists():
            os.startfile(str(p))


def main():
    CursorBoostApp().mainloop()


if __name__ == "__main__":
    main()
