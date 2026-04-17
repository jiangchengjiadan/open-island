# Open Island 发布清单

## 发布前

- 确认目标版本号
- 如果安装方式或限制说明有变化，更新 `README.md` 和 `README.zh-CN.md`
- 更新 `CHANGELOG.md`
- 本地构建原生 app：`cd native/NotchMonitor && swift build`
- 检查 bridge 脚本：
  - `node --check bridge/server.js`
  - `node --check bridge/hook.js`
  - `node --check bridge/codex-wrapper.js`
- 进行本地 smoke check：
  - `open-island start`
  - 确认 panel 能正常显示
  - 确认 Claude Code 会话能出现
  - 确认 Codex 会话能出现
  - 确认至少一个权限交互流程
  - 确认终端跳转可用
- 重新构建分发用 DMG：
  - `bash scripts/package-dmg.sh <version>`

## 打包检查

- 确认 `dist/` 下已经生成 DMG
- 尽量在一个干净的 macOS 用户环境里，从 DMG 打开 `.app`
- 检查首次运行时的 Accessibility 引导
- 检查打包后的 app 是否能正常 bootstrap bridge runtime
- 确认 app 图标和显示名称都正确

## Release 文案

- 总结用户可见的变化
- 明确写出已知限制，尤其是 JetBrains 路由相关限制
- 如果还没做 notarization，要明确写出 DMG 是未签名的

## 发布

- 为版本创建 Git tag
- 创建 GitHub Release
- 上传 DMG
- 粘贴 release notes
- 如果构建物未签名，附上未签名安装说明链接
