# 调试计划

## 问题1: Command+P位置选择器失效

**症状**: 在QuickAddSheetView的输入框中按Command+P无法打开位置选择器

**可能原因**:
1. 窗口分离后通知路由问题
2. 时序问题：地图窗口还没完全加载就收到openMapForLocationSelection通知
3. WindowFocusManager的shouldHandleNotification逻辑问题

**调试步骤**:
1. 检查openMapWindow通知是否正确发送
2. 检查独立窗口是否正确处理通知
3. 检查地图窗口是否收到openMapForLocationSelection通知
4. 验证时序 - 延迟从0.5秒增加到0.8秒

## 问题2: 地图点击后精确定位失败

**症状**: 点击地图后切换层成功，展开标签类型成功，但没有选中具体标签值和节点

**可能原因**:
1. expandLocationTagAndSelect在独立窗口的store实例中工作不正常
2. selectedTag或selectedNode的设置被覆盖
3. UI更新时序问题

**调试步骤**:
1. 验证expandLocationTagAndSelect的每个步骤
2. 检查selectedTag是否正确设置
3. 检查selectedNode是否正确设置
4. 验证UI是否正确响应状态变化

## 测试方案

### 测试1: Command+P
1. 打开主窗口 -> Command+I -> Command+P (应该工作)
2. 打开独立窗口 -> Command+I -> Command+P (可能失效)

### 测试2: 地图点击定位
1. 主窗口：点击地图标注 -> 检查是否精确定位
2. 独立窗口：点击地图标注 -> 检查是否精确定位