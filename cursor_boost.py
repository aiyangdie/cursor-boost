# -*- coding: utf-8 -*-
"""Cursor Boost - one-click cleanup GUI"""
import json
import os
import subprocess
import sys
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

ROOT = Path(__file__).resolve().parent
BOOST_PS1 = ROOT / "boost.ps1"
REPORT = Path(os.environ.get("TEMP", ".")) / "cursor-boost-last.json"
CURSOR_EXE = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "cursor" / "Cursor.exe"


class CursorBoostApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Cursor Boost - 一键好起来")
        self.geometry("480x420")
        self.resizable(False, False)
        self.configure(bg="#1e1e2e")

        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("TCheckbutton", background="#1e1e2e", foreground="#cdd6f4")
        style.configure("TProgressbar", troughcolor="#313244", background="#89b4fa")

        tk.Label(
            self, text="Cursor Boost", font=("Segoe UI", 20, "bold"),
            fg="#89b4fa", bg="#1e1e2e",
        ).pack(pady=(18, 4))
        tk.Label(
            self, text="点一下，清缓存、解锁数据库、修好 hooks",
            font=("Microsoft YaHei UI", 10), fg="#a6adc8", bg="#1e1e2e",
        ).pack()

        self.log = tk.Text(
            self, height=12, width=54, font=("Consolas", 9),
            bg="#11111b", fg="#cdd6f4", relief=tk.FLAT, padx=8, pady=8,
        )
        self.log.pack(pady=12)
        self.log.insert(tk.END, self._why_text())
        self.log.configure(state=tk.DISABLED)

        frm = tk.Frame(self, bg="#1e1e2e")
        frm.pack()
        self.var_deep = tk.BooleanVar(value=False)
        self.var_restart = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="深度清理（删全部日志）", variable=self.var_deep).grid(row=0, column=0, sticky="w", padx=4)
        ttk.Checkbutton(frm, text="完成后自动打开 Cursor", variable=self.var_restart).grid(row=1, column=0, sticky="w", padx=4)

        self.btn = tk.Button(
            self, text="一键清理，让 Cursor 好起来", font=("Microsoft YaHei UI", 12, "bold"),
            bg="#89b4fa", fg="#1e1e2e", activebackground="#74c7ec", relief=tk.FLAT,
            padx=16, pady=10, cursor="hand2", command=self.run_boost,
        )
        self.btn.pack(pady=14)

        self.progress = ttk.Progressbar(self, mode="indeterminate", length=360)
        self.progress.pack(pady=(0, 16))

    def _why_text(self):
        return (
            "【为什么会卡】\n"
            "1. 缓存膨胀：GPUCache/Code Cache 越大越慢\n"
            "2. 进程过多：多窗口=多进程，SQLite 锁竞争\n"
            "3. hooks.json 损坏：Agent 连不上、一直转圈\n"
            "4. 日志堆积：启动时要扫描大量旧日志\n"
            "5. 网络 HTTP/2：国内环境易 ECONNRESET\n\n"
            "【预防】每周点一次本工具；少开窗口；SSH 别开 /root\n"
        )

    def _log(self, msg):
        self.log.configure(state=tk.NORMAL)
        self.log.insert(tk.END, msg + "\n")
        self.log.see(tk.END)
        self.log.configure(state=tk.DISABLED)
        self.update_idletasks()

    def run_boost(self):
        if not messagebox.askyesno(
            "确认",
            "将关闭所有 Cursor 窗口并清理缓存。\n请先保存未保存的文件。\n\n继续？",
        ):
            return

        self.btn.configure(state=tk.DISABLED)
        self.progress.start(12)
        self.log.configure(state=tk.NORMAL)
        self.log.delete("1.0", tk.END)
        self.log.configure(state=tk.DISABLED)
        self._log("正在清理，请稍候…")

        args = [
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(BOOST_PS1), "-Force",
        ]
        if self.var_deep.get():
            args.append("-Deep")

        try:
            proc = subprocess.run(args, check=False, cwd=str(ROOT))
            if proc.returncode == 2:
                self.progress.stop()
                self.btn.configure(state=tk.NORMAL)
                messagebox.showwarning(
                    "请先完全关闭 Cursor",
                    "检测到你还有 Cursor 进程在运行。\n\n"
                    "请关闭所有 Cursor 窗口，在任务管理器里确认没有 Cursor.exe，\n"
                    "然后再点清理。\n\n"
                    "在 Cursor 开着的时候删缓存，可能短暂变卡或连不上，"
                    "这就是刚才「突然坏了又好了」的原因之一。",
                )
                return
        except Exception as e:
            self.progress.stop()
            self.btn.configure(state=tk.NORMAL)
            messagebox.showerror("失败", str(e))
            return

        report = {}
        if REPORT.exists():
            try:
                report = json.loads(REPORT.read_text(encoding="utf-8"))
            except Exception:
                pass

        self.progress.stop()
        self.btn.configure(state=tk.NORMAL)

        freed = report.get("freedMB", "?")
        killed = report.get("killed", 0)
        locks = report.get("clearedLocks", 0)
        hooks = report.get("fixedHooks", 0)

        self._log(f"完成：释放约 {freed} MB")
        self._log(f"关闭进程 {killed} 个，清理锁文件 {locks} 个，修复 hooks {hooks} 处")

        if self.var_restart.get() and CURSOR_EXE.exists():
            subprocess.Popen([str(CURSOR_EXE)], shell=False)
            self._log("已启动 Cursor")
        elif self.var_restart.get():
            self._log("未找到 Cursor.exe，请手动打开")

        messagebox.showinfo(
            "清理完成",
            f"释放约 {freed} MB 缓存\n"
            f"关闭 {killed} 个进程，清理 {locks} 个锁文件\n\n"
            "Cursor 应该流畅多了。若 Agent 仍异常，请 Sign out 再 Sign in。",
        )


def main():
    app = CursorBoostApp()
    app.mainloop()


if __name__ == "__main__":
    main()
