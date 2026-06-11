# Cursor 安装包归档

本目录用于存放 **Cursor 官方安装包** 的版本记录，方便社区在出问题时对照版本。

> Cursor 安装包版权归 Anysphere 所有。请从官方渠道下载。

## 官方下载

- https://www.cursor.com/download
- Windows: `Cursor Setup x.x.x.exe`

## 本地缓存脚本

```powershell
powershell -ExecutionPolicy Bypass -File scripts/download-cursor.ps1
```

会在 `releases/` 生成 `cursor-version.txt` 记录当前检测到的版本，**不会自动上传大文件到 Git**。

## GitHub Releases 建议

每次发布 Cursor Boost 时附带：
- `CursorBoost.exe`（本工具）
- `issues.json` 变更说明
- 测试过的 Cursor 版本号（如 3.7.27）
