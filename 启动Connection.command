#!/bin/bash

# Connection APP 启动脚本
# 自动启动Release版本的Connection应用

cd "$(dirname "$0")"

echo "🚀 启动 Connection APP (Release版本)..."
echo "📍 位置: $(pwd)/Connection.app"
echo "📏 大小: $(du -sh Connection.app | cut -f1)"
echo "⚡ 版本: Release (无调试日志)"

# 启动应用
open "./Connection.app"

echo "✅ Connection 应用已启动！"
echo ""
echo "🎯 Release版本特性："
echo "   • 完全移除所有调试日志"
echo "   • 优化性能和启动速度"
echo "   • 搜索缓存系统已启用"
echo "   • 生产环境配置"
echo ""

# 等待一下让用户看到信息
sleep 2