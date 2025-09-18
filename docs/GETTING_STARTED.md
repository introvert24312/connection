# 快速开始指南

## 5分钟上手 Connection

### 第一步：运行应用
```bash
# 最简单的方式
open ~/Desktop/Connection.app
```

### 第二步：创建第一个节点
1. 打开应用后，按 `Cmd+K` 打开命令面板
2. 输入：`苹果` 然后按回车
3. 你就创建了第一个节点！

### 第三步：添加标签
1. 再次按 `Cmd+K`
2. 输入：`苹果[水果]` 
3. 这会给"苹果"节点添加"水果"标签

### 第四步：添加位置信息
1. 按 `Cmd+K`
2. 输入：`超市 loc @39.9042,116.4074[北京天安门]`
3. 这会创建一个带位置信息的节点

### 第五步：查看地图
1. 点击左侧的地图图标
2. 你会看到刚才创建的位置节点显示在地图上

## 核心快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd+K` | 打开命令面板 |
| `Cmd+R` | 创建新层 |
| `Cmd+N` | 新建窗口 |
| `Escape` | 关闭当前面板 |

## 开发环境设置

### 从源码运行
```bash
cd /Users/Patronum/Desktop/Connection
open WordTagger.xcodeproj
# 在 Xcode 中按 Cmd+R 运行
```

### 代码结构理解
- 打开 `WordTagger/Store.swift` - 这是数据的核心
- 查看 `WordTagger/ContentView.swift` - 这是主界面
- 看看 `WordTagger/Models.swift` - 理解数据模型

### 修改和测试
1. 修改代码
2. 在 Xcode 中按 `Cmd+R` 重新运行
3. 测试你的修改

就这么简单！🎉