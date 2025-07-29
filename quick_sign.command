#!/bin/bash

# 快速签名脚本 - 直接签名已编译的应用

set -e

CERTIFICATE_NAME="尹舒哲"
APP_PATH="/Users/Patronum/Desktop/WordTagger/build/Debug/WordTagger.app"

echo "🔐 快速签名脚本"
echo "🎯 目标应用: $APP_PATH"
echo "🔑 使用证书: $CERTIFICATE_NAME"
echo ""

# 检查应用是否存在
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 应用不存在: $APP_PATH"
    echo "请先在Xcode中编译项目"
    exit 1
fi

# 检查应用结构
if [ ! -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "❌ 应用包损坏: 缺少 Info.plist"
    exit 1
fi

echo "✅ 找到应用包"

# 显示应用信息
echo "📋 应用信息:"
echo "   Bundle ID: $(defaults read "$APP_PATH/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo '未知')"
echo "   版本: $(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '未知')"
echo ""

# 清理现有签名
echo "🧹 清理现有签名..."
codesign --remove-signature "$APP_PATH" 2>/dev/null || true

# 签名
echo "✍️  正在签名..."
codesign --deep --force --sign "$CERTIFICATE_NAME" "$APP_PATH" --verbose

# 验证签名
echo "🔍 验证签名..."
codesign --verify --verbose "$APP_PATH"

# 清理隔离标志
echo "🔓 清理隔离标志..."
xattr -rd com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo ""
echo "🎉 签名完成！现在可以运行应用了"
echo ""

# 询问是否运行
read -p "是否现在运行应用？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 启动应用..."
    open "$APP_PATH"
else
    echo "💡 要手动运行应用，请执行: open '$APP_PATH'"
fi

echo "✨ 完成！"