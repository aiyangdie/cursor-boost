# 本机数据（运行时自动生成，勿提交 git）

用户运行 Cursor Boost 后，数据保存在：

`%LOCALAPPDATA%\CursorBoost\`

| 文件 | 说明 |
|------|------|
| error-catalog.json | 全量报错目录（去重合并） |
| submissions/report-*.json | 用户本机提交的诊断报告 |

GitHub 上只同步 `issues.json` 知识库，不包含用户隐私。
