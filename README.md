<p align="center"><img src="assets/covers/27-cursor-boost.jpg" alt="cursor-boost 项目封面" width="100%"></p>

<p align="center">
  <img src="https://img.shields.io/badge/Cursor-Boost-6366f1?style=for-the-badge" alt="Cursor Boost"/>
  <img src="https://img.shields.io/badge/platform-Windows-0078d4?style=for-the-badge" alt="Windows"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="MIT"/>
</p>

<h1 align="center">Cursor Boost</h1>

<p align="center"><strong>万能 Cursor 问题修复系统</strong> — 读日志 · 认问题 · 一键修 · 共建 GitHub</p>

<p align="center">
  <a href="https://github.com/aiyangdie/cursor-boost/releases">下载 exe</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#共建问题库">共建</a> ·
  <a href="CONTRIBUTING.md">贡献指南</a>
</p>

---

## 为什么需要它？

Cursor 基于 Electron，用久了会遇到：

| 问题 | 表现 |
|------|------|
| 缓存膨胀 | 打开慢、卡顿 |
| hooks 损坏 | Agent 转圈、连不上 |
| SSH /root | 远程 Agent 写文件失败 |
| HTTP2 断连 | ECONNRESET |
| 进程过多 | SQLITE_BUSY |
| 账号限制 | trial / usage limit |

**Cursor Boost 在 Cursor 挂了时也能独立运行**，不依赖 Agent。

---

## 下载

👉 [Releases 页面](https://github.com/aiyangdie/cursor-boost/releases) 下载 `CursorBoost.exe`（约 30MB，Windows 10/11）

或源码运行：

```bash
git clone https://github.com/aiyangdie/cursor-boost.git
cd cursor-boost
pip install -r requirements.txt
python app.py
```

---

## 功能一览

| 模块 | 说明 |
|------|------|
| **概览** | 健康度 0–100、问题数、报错数、进程、DB 大小 |
| **问题检测** | 自动匹配 `issues.json`，一键修复 |
| **全部日志** | 从 `%APPDATA%\Cursor\logs` 提取全部报错（去重） |
| **知识库** | 19+ 已知问题与解法，可搜索 |
| **修复工具** | 热修复 / 清缓存 / SSH / hooks / 闪退 |
| **共建反馈** | 导出 zip、本机保存、GitHub Issue |

### 修复顺序（尽量少重启）

```
智能热修复 → Reload Window → 重启 Cursor → 一键全修
```

---

## 共建问题库

```mermaid
flowchart LR
    A[用户报错] --> B[导出诊断包]
    B --> C[GitHub Issue]
    C --> D[维护者 / Cursor Agent]
    D --> E[更新 issues.json]
    E --> F[发布 Release]
    F --> G[所有人一键能修]
```

1. 打开 Cursor Boost → **共建反馈** → **导出 zip**
2. 到 [New Issue](https://github.com/aiyangdie/cursor-boost/issues/new?template=cursor-error.yml) 提交
3. 维护者更新 `issues.json`，用户运行 `scripts/sync-issues-from-github.ps1` 同步

---

## 开发

```powershell
# 打包 exe
.\打包.bat

# 同步远程问题库
powershell -File scripts\sync-issues-from-github.ps1
```

---

## 免责声明

- 不能绕过 Cursor 试用 / 付费限制
- 与 Anysphere / Cursor **无官方关联**
- 不删除聊天记录（除非用户主动深度清理）

---

## License

MIT © [aiyangdie](https://github.com/aiyangdie)
