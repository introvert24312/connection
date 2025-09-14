#!/bin/bash

# 设置变量
APP_NAME="Connection"
DMG_NAME="Connection-Installer"
BUILD_PATH="/Users/Patronum/Library/Developer/Xcode/DerivedData/WordTagger-bhactxeabaanpsgrwffqabngxjck/Build/Products/Release"
OUTPUT_PATH="/Users/Patronum/Desktop/Connection"

# 创建临时文件夹
TEMP_DIR=$(mktemp -d)
echo "创建临时目录: $TEMP_DIR"

# 复制应用到临时文件夹
cp -R "$BUILD_PATH/$APP_NAME.app" "$TEMP_DIR/"

# 创建 Applications 符号链接
ln -s /Applications "$TEMP_DIR/Applications"

# 创建 DMG
echo "正在创建 DMG..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$TEMP_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_PATH/$DMG_NAME.dmg"

# 清理临时文件夹
rm -rf "$TEMP_DIR"

echo "DMG 创建完成: $OUTPUT_PATH/$DMG_NAME.dmg"