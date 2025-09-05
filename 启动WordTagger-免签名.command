#!/bin/bash
cd "$(dirname "$0")"

echo "🏗️ 编译WordTagger (免签名版本)..."
xcodebuild -project WordTagger.xcodeproj -scheme WordTagger -configuration Debug build > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ 编译成功！正在启动应用..."
    
    # 查找构建产品
    BUILD_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "WordTagger.app" -type d 2>/dev/null | head -1)
    
    if [ -n "$BUILD_PATH" ]; then
        echo "🚀 启动: $BUILD_PATH"
        open "$BUILD_PATH"
        
        echo ""
        echo "🎉 WordTagger已启动！"
        echo "✅ 已成功绕过开发者账号签名要求"
        echo ""
        echo "🔍 测试WebView修复效果："
        echo "1. 点击节点选择是否正常工作"
        echo "2. 图谱是否不再闪退"
        echo "3. 应用是否保持响应性"
        echo "4. 键盘快捷键是否正常"
    else
        echo "❌ 找不到构建产品"
        echo "尝试手动运行: xcodebuild -project WordTagger.xcodeproj -scheme WordTagger -configuration Debug build"
    fi
else
    echo "❌ 编译失败"
    echo "请检查Xcode项目设置"
fi

echo ""
echo "按回车键退出..."
read