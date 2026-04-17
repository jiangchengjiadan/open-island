# 安装未签名的 Open Island DMG

当前 DMG 构建物是未签名、未 notarize 的。这对于开发者预览版分发是可接受的，但 macOS 在首次打开时会给出安全提示。

## 推荐安装方式

1. 下载 `Open-Island-<version>.dmg`
2. 打开 DMG，把 `Open Island.app` 拖到 `Applications`
3. 在 Finder 中打开 `Applications`
4. 对 `Open Island.app` 执行右键或按住 Control 点击
5. 选择 `Open`
6. 在 macOS 弹窗中确认打开

第一次成功打开之后，后续就可以正常启动。

## 如果 macOS 仍然阻止打开

进入：

- `System Settings -> Privacy & Security`

在页面靠下的位置找到被拦截应用的提示，然后点击 `Open Anyway`。

## Accessibility 权限

为了让跳转和权限交互正常工作，还需要开启：

- `System Settings -> Privacy & Security -> Accessibility`

允许你用于启动 Open Island 的终端或应用。

## 分发说明

如果你准备把它作为更广泛的公开版本分发，建议补上 Developer ID 签名和 Apple notarization。
