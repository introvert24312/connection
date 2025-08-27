#!/usr/bin/env swift

import Foundation

/*
Command+B 调试诊断工具
====================

此文件用于分析Command+B无法工作的可能原因。

现在的修复状态：
1. ✅ 简化了通知处理链
2. ✅ 移除了复杂的对象匹配逻辑  
3. ✅ 添加了详细的调试日志

预期的执行流程：
1. Menu按钮被点击 -> 发送"openNewWindow"通知
2. WordTaggerApp.onReceive -> WindowFocusManager检查
3. 如果通过检查 -> 发送"executeOpenWindow"通知
4. ContentView.observer -> 执行openWindow(id: "layerView")

可能的失败点：
1. WindowFocusManager.shouldHandleNotification返回false
2. hasActiveKeyWindow()返回false
3. KeyboardEventManager阻止命令执行
4. 通知处理器未正确注册

调试步骤：
1. 运行应用
2. 按Command+B
3. 检查控制台输出是否包含以下日志：

预期日志序列：
```
🔔 [DEBUG] Command+B 被按下，直接发送openNewWindow通知
🏠 WindowFocusManager: 全局通知允许执行  
✅ 主窗口: 收到openNewWindow通知，直接打开独立窗口
🔔 [DEBUG] 主窗口已注册executeOpenWindow通知监听
✅ [DEBUG] 主窗口收到executeOpenWindow通知，打开窗口: layerView
```

如果某个步骤的日志缺失，则问题出现在该步骤。

可能需要添加的额外调试：
- 在WindowFocusManager中添加更多日志
- 在KeyboardEventManager中检查command-b的处理
- 验证通知监听器是否正确注册
*/

print("Command+B 调试信息已记录到此文件")
print("请运行应用并按Command+B，然后检查控制台输出")
print("对比上面的预期日志序列来诊断问题")