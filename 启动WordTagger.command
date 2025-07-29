#!/bin/bash

# WordTagger 启动脚本
# 双击即可运行WordTagger应用

APP_PATH="/Users/Patronum/Desktop/WordTagger/build/Debug/WordTagger.app"

echo "🚀 启动 WordTagger..."

# 检查应用是否存在
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 应用不存在，请先编译项目"
    read -p "按任意键退出..."
    exit 1
fi

# 启动应用
open "$APP_PATH"

echo "✅ WordTagger 已启动！"

# 等待3秒后自动关闭终端窗口
sleep 3