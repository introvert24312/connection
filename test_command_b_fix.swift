// 测试Command+B修复的调试工具
// 此文件用于验证修复后的Command+B功能

import SwiftUI

struct CommandBTestView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Command+B 修复测试")
                .font(.title)
                .padding()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("修复前的问题:")
                    .font(.headline)
                
                Text("• Menu按钮发送: object: \"mainWindow\"")
                Text("• WordTaggerApp转发: object: \"notificationHandler\"") 
                Text("• ContentView只处理: source == \"mainWindow\"")
                Text("• 结果: 通知对象不匹配，窗口无法打开")
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("修复后的逻辑:")
                    .font(.headline)
                
                Text("• Menu按钮: 直接发送openNewWindow通知")
                Text("• WordTaggerApp: 接收后发送executeOpenWindow")
                Text("• ContentView: 监听executeOpenWindow并执行openWindow")
                Text("• 结果: 简化通知链，确保正确执行")
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(10)
            
            Button("测试手动触发Command+B") {
                print("🧪 [TEST] 手动触发Command+B通知")
                NotificationCenter.default.post(
                    name: Notification.Name("openNewWindow"), 
                    object: nil
                )
            }
            .padding()
        }
        .padding()
    }
}

// 调试日志检查清单
/*
期望看到的调试日志序列：

1. "🔔 [DEBUG] Command+B 被按下，直接发送openNewWindow通知"
2. "✅ 主窗口: 收到openNewWindow通知，直接打开独立窗口"
3. "✅ [DEBUG] 主窗口收到executeOpenWindow通知，打开窗口: layerView"

如果看到这个完整序列，说明修复成功。
*/