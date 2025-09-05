#!/bin/bash
cd "$(dirname "$0")"

echo "🏗️ 开始编译WordTagger..."
xcodebuild -project WordTagger.xcodeproj -scheme WordTagger -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

if [ $? -eq 0 ]; then
    echo "✅ 编译成功！"
    
    # 查找构建产品
    BUILD_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "WordTagger.app" -type d 2>/dev/null | head -1)
    
    if [ -n "$BUILD_PATH" ]; then
        echo "🚀 启动应用: $BUILD_PATH"
        open "$BUILD_PATH"
        echo ""
        echo "🔍 测试项目："
        echo "1. 点击节点选择功能是否正常"
        echo "2. 图谱是否不再闪退"
        echo "3. 应用焦点是否保持"
        echo "4. WebView是否稳定运行"
        echo ""
        echo "📊 如果需要调试信息，可以查看控制台输出中的WebView相关日志"
    else
        echo "❌ 找不到构建产品，请检查编译结果"
    fi
else
    echo "❌ 编译失败，请检查错误信息"
fi

echo ""
echo "按任意键退出..."
read -n 1