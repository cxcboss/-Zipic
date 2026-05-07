# Release Notes

## 当前仓库内容

- 源码
- 图标源文件
- 图标生成脚本
- `arm64` 打包脚本
- 已生成的 `dist/Zipic-arm64.zip`

## 重新发布流程

1. 确认图标源文件存在：`Assets/AppIcon-source.png`
2. 执行测试：`swift test`
3. 执行打包：`./build_app.sh`
4. 验证压缩包：

```bash
TMP_DIR=$(mktemp -d)
ditto -x -k dist/Zipic-arm64.zip "$TMP_DIR"
codesign --verify --deep --strict "$TMP_DIR/Zipic.app"
```

5. 将源码和新的 `dist/Zipic-arm64.zip` 一起提交到仓库

## 签名说明

- `dist/Zipic.app` 在当前工作目录里可能会被系统同步服务附加 Finder 元数据
- 最稳定的交付物是 `dist/Zipic-arm64.zip`
- 从 zip 解压出的 `.app` 更适合做分发验证
