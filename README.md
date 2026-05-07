# Zipic

Zipic 是一个使用 `SwiftUI + AppKit + ImageIO` 编写的原生 macOS 图片压缩工具，交互和操作流程参考了图压官网产品，但工程本身是一个独立实现，面向 Apple Silicon 的本地运行场景。

## 功能

- 拖拽或手动选择图片后自动开始压缩
- 批量处理 `JPG / PNG / GIF / SVG / WebP / HEIC / TIFF / BMP`
- 支持设置宽度、高度，并可保持原始宽高比
- 支持按压缩强度或目标文件大小压缩
- 支持输出为原格式、`WebP`、`PNG`、`JPG`
- 支持输出到原文件夹、覆盖原文件、自定义文件夹
- 自动跟随系统浅色和深色模式
- 使用逐张处理和会话级临时备份，避免批量任务时不必要的内存占用

## 图标

- App 图标源文件: [Assets/AppIcon-source.png](Assets/AppIcon-source.png)
- 当前默认使用官网公开产品图形资源生成 `.icns`
- 重新生成图标: `./scripts/generate_icon.sh`

## 运行要求

- macOS 14 或更高版本
- Apple Silicon (`arm64`)
- Xcode 26.4.1 或兼容的 Swift 6.3 工具链

## 本地开发

```bash
swift build
swift test
open .build/arm64-apple-macosx/debug/Zipic
```

## 打包

```bash
./build_app.sh
```

打包完成后会产出：

- `dist/Zipic.app`
- `dist/Zipic-arm64.zip`

仓库中已经提交了一个现成可用的 `arm64` 打包版本，方便直接下载验证。

## 实现说明

- 核心压缩逻辑在 [Sources/TuyaCore/CompressionEngine.swift](Sources/TuyaCore/CompressionEngine.swift)
- 界面状态管理在 [Sources/Zipic/AppState.swift](Sources/Zipic/AppState.swift)
- 主窗口布局在 [Sources/Zipic/MainWindowView.swift](Sources/Zipic/MainWindowView.swift)
- 打包脚本会自动生成图标、复制 Swift 运行时、写入 `Info.plist` 并执行 ad-hoc 签名

## 说明修正

- 仓库对外项目名统一为 `Zipic`
- App 产物统一为 `Zipic.app` 和 `Zipic-arm64.zip`
- 文档中的运行与打包路径全部按当前仓库结构更新

## 发布备注

由于当前使用的是本地 ad-hoc 签名，若要面向更多机器分发，后续仍建议补充 Developer ID 签名和 notarization。现有 zip 包已验证可在本机解压后通过本地签名校验。
