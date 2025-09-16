#!/usr/bin/swift

// 测试窗口点击追踪修复
// 使用方式: swift test_window_click_tracking.swift

import Foundation

print("🧪 窗口点击追踪测试")
print("=" * 50)
print("\n修复内容:")
print("1. ✅ WindowClickTracker在viewDidMoveToWindow时立即建立NSWindow<->UUID映射")
print("2. ✅ WindowFocusManager增加从视图层次结构查找WindowId的能力") 
print("3. ✅ LayerGraphWindow验证保存的窗口ID是否有效")
print("4. ✅ 增强调试日志，显示所有注册的窗口")
print("\n测试步骤:")
print("1. 打开多个窗口 (A, B, C)")
print("2. 点击窗口C")
print("3. 使用Command+K打开层图谱")
print("4. 在层图谱中切换层")
print("5. 验证是否切换了窗口C的层（而不是窗口B）")
print("\n期望结果:")
print("✅ WindowClickTracker正确检测到窗口C的点击")
print("✅ LayerGraphWindow保存窗口C的ID")
print("✅ 层切换通知发送到窗口C")
print("✅ 窗口C的层被正确切换")
print("\n关键日志标记:")
print("🔗 WindowClickTracker: 建立窗口映射 - 表示窗口与UUID的映射建立")
print("🎯 LayerGraphWindow: 用户真实点击了窗口 - 表示检测到用户点击")
print("📡 LayerGraphWindow: 发送层切换通知到窗口 - 表示层切换目标")
print("📊 LayerGraphWindow: 当前注册的所有窗口 - 显示窗口注册状态")

print("\n如果问题仍然存在，请检查:")
print("1. 日志中的窗口ID映射是否一致")
print("2. 是否有多个窗口使用了相同的UUID")
print("3. SwiftUI的WindowGroup是否正确创建了新的窗口实例")