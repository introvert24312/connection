#!/bin/bash

# Emergency fix for stuck WordTagger dialogs
# This script forces the app to close all uncloseable dialogs

echo "🚨 WordTagger 紧急对话框修复工具"
echo "================================"

# Check if WordTagger is running
WORDTAGGER_PID=$(ps aux | grep -i "WordTagger\|Connection" | grep -v grep | awk '{print $2}' | head -1)

if [ -z "$WORDTAGGER_PID" ]; then
    echo "❌ WordTagger 应用未运行"
    exit 1
fi

echo "✅ 发现 WordTagger 进程 (PID: $WORDTAGGER_PID)"

# Method 1: Send notification to force close all sheets
echo "📡 方法1: 发送紧急清理通知..."
osascript -e 'tell application "System Events" to tell process "Connection" to key code 8 using {command down, option down}' 2>/dev/null

sleep 1

# Method 2: Send escape key sequence
echo "⌨️  方法2: 发送Escape键序列..."
for i in {1..3}; do
    osascript -e 'tell application "System Events" to tell process "Connection" to key code 53' 2>/dev/null
    sleep 0.2
done

# Method 3: Force window close
echo "🪟 方法3: 强制关闭所有窗口..."
osascript -e '
tell application "System Events"
    tell application process "Connection"
        set windowList to every window
        repeat with currentWindow in windowList
            try
                click button 1 of currentWindow
            on error
                try
                    key code 53 -- Escape key
                end try
            end try
        end repeat
    end tell
end tell
' 2>/dev/null

echo "✅ 紧急修复完成！"
echo "💡 如果对话框仍然无法关闭，请尝试："
echo "   1. 按 Command+Option+C 键"
echo "   2. 按 Escape 键"
echo "   3. 重启 WordTagger 应用"