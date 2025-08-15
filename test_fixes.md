# 层管理修复测试

## 修复内容

### 1. Command+R 快捷键支持
- ✅ 在 CommandPaletteView.swift 中添加了 Command+R 的 onKeyPress 处理
- ✅ 添加了 handleCreateNewLayer() 函数来处理新层创建逻辑
- ✅ 在 NSEvent 监听器中添加了对 Command+R (keyCode=15) 的支持
- ✅ 创建新层后自动添加到过滤器并清空搜索框

### 2. 创建新层UI布局修复
- ✅ 移除了 NavigationView，改用 VStack 布局
- ✅ 添加了自定义的顶部标题栏
- ✅ 修复了内容区域的布局约束
- ✅ 调整了窗口尺寸为 500x550

## 使用方法

### Command+R 创建新层
1. 打开命令面板（Command+K）
2. 在搜索框中输入新层的名称（例如："层A"）
3. 按下 Command+R
4. 新层将被创建并自动添加到图谱显示中

### 设置中创建新层
1. 打开设置 → 层管理
2. 点击"创建新层"按钮
3. UI现在应该正确显示，不会挤在左边

## 测试步骤
1. 测试 Command+R 快捷键是否能正确创建新层
2. 测试设置界面中的创建新层UI是否正常显示
3. 验证新创建的层是否出现在图谱中