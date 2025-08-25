# WordTagger

**WordTagger** 是一个功能丰富的 macOS 标签和地图导航应用，基于 SwiftUI 构建，具备完整的工程治理体系。

## 🚀 快速开始

### 系统要求
- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

### 启动应用
```bash
# 直接启动
./启动WordTagger.command

# 或者使用 Xcode 打开项目
open WordTagger.xcodeproj
```

## ✨ 核心功能

- **🗺️ 交互式地图** - 基于 MapKit 的 3D 地图视图，支持地理位置标记
- **🏷️ 智能标签系统** - 复合标签支持，层级管理和快速导航
- **🔍 高级搜索** - 模糊搜索，多字段权重匹配和性能优化
- **📊 关系图谱** - 节点关系可视化，相似度计算和聚类分析
- **🔄 Git 集成** - 完整的版本控制，自动同步和冲突解决
- **⌨️ 命令面板** - 键盘驱动的快速操作和导航
- **📱 响应式UI** - 现代 SwiftUI 界面，支持深色模式

## 🏗️ 工程治理框架 (六件套)

本项目实现了完整的工程治理体系，包含以下六个核心组件：

1. **📐 架构图** - 完整的系统架构可视化和服务依赖关系
2. **📋 服务清单** - 轻量级服务注册中心，包含元数据和健康监控
3. **📋 接口契约** - OpenAPI/AsyncAPI 规范和自动化验证
4. **🔍 CI 护栏** - 自动化验证，防止文档漂移
5. **🔗 分布式追踪** - TraceID 在所有服务边界的完整传播
6. **🎛️ 特性管理** - 功能开关和回滚策略

## 📁 项目结构

```
WordTagger/
├── WordTagger/            # Swift 源码
│   ├── WordTaggerApp.swift          # 应用入口
│   ├── ContentView.swift            # 主界面
│   ├── Store.swift                  # 中央状态管理
│   ├── DataManager.swift            # 数据持久化
│   ├── Services/                    # 服务层
│   │   ├── GitService.swift         # Git 版本控制
│   │   ├── SearchService.swift      # 搜索服务
│   │   ├── GraphService.swift       # 图谱服务
│   │   └── ExternalDataService.swift # 外部数据同步
│   ├── Views/                       # UI 组件
│   │   ├── MapContainer.swift       # 地图容器
│   │   ├── DetailPanel.swift        # 详情面板
│   │   ├── CommandPaletteView.swift # 命令面板
│   │   └── ...
│   └── Models/                      # 数据模型
│       └── Models.swift
├── docs/                  # 完整的工程治理文档
│   ├── architecture/      # 架构图和依赖关系图
│   │   ├── wordtagger-complete-architecture.mmd  # 完整架构图
│   │   ├── service-dependency-mapping.md          # 服务依赖映射
│   │   ├── data-flow-patterns.mmd                 # 数据流程图
│   │   └── ArchitectureVisualization.swift        # 运行时架构监控
│   ├── services/          # 服务目录 (16个服务的完整定义)
│   │   ├── node-store.yaml           # 中央状态服务
│   │   ├── git-service.yaml          # Git 服务
│   │   ├── search-service.yaml       # 搜索服务
│   │   ├── ServiceRegistry.swift     # 服务注册中心
│   │   └── ServiceHealthDashboard.swift # 健康监控仪表板
│   ├── contracts/         # 接口契约
│   │   ├── swift/service-protocols.swift     # Swift 协议定义
│   │   ├── events/wordtagger-events.asyncapi.yaml # 事件规范 (40+ 事件)
│   │   ├── schemas/       # JSON Schema 数据验证
│   │   └── tools/         # 契约验证工具
│   ├── observability/     # 可观测性系统
│   │   ├── TracingInfrastructure.swift       # 追踪基础设施
│   │   ├── TracedServices.swift              # 服务监控包装
│   │   ├── ObservabilityDashboard.swift      # 可观测性仪表板
│   │   └── TracingIntegrationExamples.swift  # 集成示例
│   └── runbooks/          # 运维手册
└── scripts/               # 自动化脚本
    └── validate-governance.js  # 治理验证脚本
```

## 🛠️ 开发者快速上手

### 1. 环境准备
```bash
# 安装依赖
npm install

# 初始化开发环境
./install.sh
```

### 2. 启动应用
```bash
# 方式一：命令行启动
./启动WordTagger.command

# 方式二：Xcode 开发
open WordTagger.xcodeproj
```

### 3. 验证治理框架
```bash
# 验证所有治理文档
npm run validate

# 验证特定组件
npm run validate:services    # 服务目录
npm run validate:contracts   # 接口契约
npm run validate:dependencies # 依赖关系
```

### 4. 启用可观测性功能

**添加追踪到现有服务：**
```swift
// 在任何服务中启用追踪
import TracingInfrastructure

class YourService {
    func performOperation() async {
        let trace = TracingService.shared.startTrace(
            operation: "your-operation",
            service: "your-service"
        )
        defer { trace.end() }
        
        // 你的业务逻辑
        await doWork()
    }
}
```

**启动可观测性仪表板：**
```swift
// 在你的 SwiftUI 视图中
import SwiftUI

struct DebugView: View {
    var body: some View {
        ObservabilityDashboard()
    }
}
```

## 📚 架构和服务说明

### 🏛️ 核心架构模式
- **MVVM + Service Layer** - 清晰的架构分层
- **Reactive Programming** - 基于 Combine 和 @Published 的响应式编程
- **NotificationCenter** - 解耦的服务间通信
- **Async/await** - 现代异步编程模式

### 🎯 核心服务

**数据层服务：**
- `NodeStore` - 中央状态管理，所有数据的单一数据源
- `DataManager` - 数据持久化和 I/O 操作
- `ExternalDataService` - 外部数据同步和备份

**业务服务：**
- `SearchService` - 高级搜索，支持模糊匹配和权重评分
- `GraphService` - 节点关系分析和图谱生成
- `GitService` - Git 版本控制集成
- `MapContainer` - 地理信息和地图可视化

**基础设施服务：**
- `TagMappingManager` - 标签系统管理
- `KeyboardEventManager` - 键盘事件处理
- `KeychainManager` - 安全凭据管理

### 🔗 通信模式
- **直接调用** - UI → NodeStore 即时操作
- **通知系统** - 服务间解耦通信
- **响应式属性** - @Published 属性的 UI 更新
- **异步操作** - 非阻塞的持久化和网络操作

## 📈 监控和调试

### 服务健康监控
```swift
// 查看服务状态
let registry = ServiceRegistry.shared
let healthReport = registry.generateHealthReport()
```

### 架构可视化
```swift
// 运行时架构监控
struct ArchitectureDebugView: View {
    var body: some View {
        ArchitectureVisualization()
    }
}
```

### 契约验证
```bash
# 验证所有接口契约
cd docs/contracts/tools
npm test

# 验证特定服务契约
node contract-validator.js NodeStore
```

## 🚀 扩展指南

### 添加新服务
1. 在 `docs/services/` 创建服务 YAML 定义
2. 实现服务协议 (参考 `service-protocols.swift`)
3. 在 ServiceRegistry 中注册服务
4. 添加健康检查和监控

### 添加新接口契约
1. 在 `docs/contracts/` 定义接口规范
2. 添加 JSON Schema 验证规则
3. 更新 AsyncAPI 事件定义
4. 运行契约验证测试

### 集成追踪功能
1. 导入 `TracingInfrastructure`
2. 在关键操作中添加 trace span
3. 配置性能指标收集
4. 使用可观测性仪表板监控

## 🤝 贡献指南

1. **Fork 项目** 并创建功能分支
2. **遵循现有代码风格** 和架构模式
3. **添加适当的测试** 和文档
4. **运行治理验证** 确保合规性
5. **提交 Pull Request** 并描述更改

## 📄 许可证

本项目采用 MIT 许可证 - 详见 LICENSE 文件。

---

🎉 **欢迎来到 WordTagger！** 这是一个具备企业级工程治理的现代 Swift 应用。如有问题，请查看 `docs/` 目录中的详细文档。