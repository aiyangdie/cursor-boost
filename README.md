<p align="center"><img src="assets/covers/27-cursor-boost.jpg" alt="Cursor 修复 项目封面" width="100%"></p>

<h1 align="center">Cursor Boost</h1>

<p align="center">Windows 上 Cursor 打不开、登录失败、更新卡住的一键修复工具</p>

<p align="center">
  <a href="https://github.com/aiyangdie/cursor-boost/releases/latest">下载最新版</a> ·
  <a href="LICENSE">MIT 许可</a>
</p>

## 简介

Cursor 在 Windows 上的故障大多集中在几种：缓存损坏、配置冲突、更新目录残留、扩展拖慢启动。这个工具按「影响最小到大」的顺序逐项检查并提供修复动作，尽量少重启、少丢数据。

## 功能

- **按顺序修复**：从清理缓存、关闭冲突项到重装更新组件，逐步尝试
- **环境体检**：检查配置文件、更新目录与运行环境是否异常
- **一键执行**：每步给出说明与结果，可单独执行也可顺序跑完
- **问题库共建**：遇到的问题可提交，汇入远程问题库供下次自动识别

## 使用

1. 从 [Releases](https://github.com/aiyangdie/cursor-boost/releases/latest) 下载 exe
2. 关闭 Cursor 后双击运行
3. 按提示逐项修复，遇到不确定的项可先跳过

## 开发

```bash
git clone https://github.com/aiyangdie/cursor-boost.git
cd cursor-boost
pip install -r requirements.txt
python main.py
```

打包 exe：仓库内提供打包脚本，产物在 `dist/`。

## 免责声明

工具只做本地环境修复，不修改 Cursor 的授权与账号状态。

## 许可证

[MIT](LICENSE)
