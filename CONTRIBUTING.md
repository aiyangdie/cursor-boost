# 共建 Cursor 问题库

## 用户怎么反馈

1. 打开 **Cursor Boost** → **反馈共建** → **导出诊断包**
2. 截图报错（清晰，含 Request ID）
3. 发 Issue 或发给维护者（微信/群）

## 维护者怎么处理

1. 解压 `CursorReport-*.zip`
2. 看 `scan-result.json` + `error-excerpts.log`
3. 把新关键字写入 `issues.json`
4. 本地测试：`python app.py` 或 `打包.bat`
5. 提交 PR 或发布 Release

## 用 Cursor Agent 自动维护

复制 `docs/CURSOR_MAINTAIN_PROMPT.md` 全文，粘贴给 Cursor，并附上诊断包 zip。

Agent 应自动：
- 分析日志
- 更新 `issues.json`
- 说明能否一键修、要不要重启

## issues.json 字段说明

| 字段 | 说明 |
|------|------|
| `patterns` | 日志匹配关键字 |
| `check` | 本地状态检测：`proc_count` / `stale_locks` / `state_vscdb_mb` / `broken_hooks` |
| `fix_action` | 对应 `engine.ps1` 动作名 |
| `fix_mode` | `hot` / `reload` / `restart` / `manual` |

## 无法本地解决的问题

请标注 `manual_only: true`，并在 `note` 写清楚正规途径，方便反馈给 Cursor 官方。
