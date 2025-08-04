import SwiftUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: WordStore
    @AppStorage("searchThreshold") private var searchThreshold: Double = 0.3
    @AppStorage("enableDebugMode") private var enableDebugMode: Bool = false
    @AppStorage("maxSearchResults") private var maxSearchResults: Int = 50
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    
    var body: some View {
        TabView {
            // 常规设置
            GeneralSettingsView()
                .tabItem {
                    Label("常规", systemImage: "gear")
                }
            
            // 搜索设置
            SearchSettingsView(
                searchThreshold: $searchThreshold,
                maxSearchResults: $maxSearchResults
            )
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            
            // 层管理
            LayerManagementView()
                .tabItem {
                    Label("层管理", systemImage: "square.stack.3d.up")
                }
                .environmentObject(store)
            
            // 数据管理
            DataManagementView()
                .tabItem {
                    Label("数据", systemImage: "externaldrive")
                }
            
            // 关于
            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - 常规设置

struct GeneralSettingsView: View {
    @AppStorage("enableDebugMode") private var enableDebugMode: Bool = false
    @AppStorage("enableGraphDebug") private var enableGraphDebug: Bool = false
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    @AppStorage("showPhoneticByDefault") private var showPhoneticByDefault: Bool = true
    @AppStorage("defaultTagType") private var defaultTagType: String = "memory"
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @AppStorage("detailGraphInitialScale") private var detailGraphInitialScale: Double = 1.0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 界面设置
                GroupBox("界面设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "默认显示音标",
                            description: "在单词列表中自动显示音标信息"
                        ) {
                            Toggle("", isOn: $showPhoneticByDefault)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("默认标签类型")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            Picker("", selection: $defaultTagType) {
                                ForEach(Tag.TagType.predefinedCases, id: \.self) { type in
                                    Text(type.displayName).tag(type.rawValue)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            
                            Text("新建单词时默认使用的标签类型")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "全局图谱初始缩放",
                            description: "全局图谱窗口打开时的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", globalGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $globalGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "详情图谱初始缩放",
                            description: "单词详情图谱的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", detailGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $detailGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 性能设置
                GroupBox("性能设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "自动保存间隔",
                            description: "自动保存数据的时间间隔（秒）"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(Int(autoSaveInterval))秒")
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                                
                                Stepper("", 
                                       value: $autoSaveInterval, 
                                       in: 10...300, 
                                       step: 10)
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 开发设置
                GroupBox("开发选项") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "调试模式",
                            description: "显示调试信息和性能指标"
                        ) {
                            Toggle("", isOn: $enableDebugMode)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "图谱调试信息",
                            description: "在WebView中显示图谱数据验证信息"
                        ) {
                            Toggle("", isOn: $enableGraphDebug)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        if enableGraphDebug {
                            Text("⚠️ 启用后会在图谱中显示详细的节点和边数据，用于调试数据传递问题")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 4)
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - 搜索设置

struct SearchSettingsView: View {
    @Binding var searchThreshold: Double
    @Binding var maxSearchResults: Int
    @AppStorage("enableFuzzySearch") private var enableFuzzySearch: Bool = true
    @AppStorage("searchInPhonetic") private var searchInPhonetic: Bool = true
    @AppStorage("searchInMeaning") private var searchInMeaning: Bool = true
    @AppStorage("searchInTags") private var searchInTags: Bool = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 搜索范围
                GroupBox("搜索范围") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "搜索音标",
                            description: "在音标字段中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInPhonetic)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "搜索含义",
                            description: "在单词含义中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInMeaning)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "搜索标签",
                            description: "在标签内容中搜索匹配内容"
                        ) {
                            Toggle("", isOn: $searchInTags)
                                .toggleStyle(SwitchToggleStyle())
                        }
                    }
                    .padding(12)
                }
                
                // 搜索算法
                GroupBox("搜索算法") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "模糊搜索",
                            description: "允许拼写错误和近似匹配"
                        ) {
                            Toggle("", isOn: $enableFuzzySearch)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        if enableFuzzySearch {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("匹配阈值")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(String(format: "%.1f", searchThreshold))
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $searchThreshold, in: 0.1...0.9, step: 0.1)
                                
                                Text("较低的值需要更精确的匹配")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                }
                
                // 结果限制
                GroupBox("结果设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "最大搜索结果",
                            description: "限制单次搜索返回的最大结果数量"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(maxSearchResults)")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Stepper("", 
                                       value: $maxSearchResults, 
                                       in: 10...200, 
                                       step: 10)
                            }
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - 层管理

struct LayerManagementView: View {
    @EnvironmentObject private var store: WordStore
    @State private var showingCreateLayerSheet = false
    @State private var showingDeleteAlert = false
    @State private var layerToDelete: Layer?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 当前活跃层
                GroupBox("当前活跃层") {
                    if let currentLayer = store.currentLayer {
                        HStack {
                            Circle()
                                .fill(Color.from(currentLayer.color))
                                .frame(width: 16, height: 16)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentLayer.displayName)
                                    .font(.headline)
                                Text(currentLayer.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(store.getNodesInCurrentLayer().count)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("节点")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("未选择活跃层")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 所有层列表
                GroupBox("所有层") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("层列表")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                showingCreateLayerSheet = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("创建新层")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.bottom, 12)
                        
                        if store.layers.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("暂无层")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("创建第一个层来开始组织您的数据")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 100)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(store.layers, id: \.id) { layer in
                                    LayerRowView(
                                        layer: layer,
                                        nodeCount: store.nodes.filter { $0.layerId == layer.id }.count,
                                        isActive: store.currentLayer?.id == layer.id,
                                        onActivate: {
                                            Task {
                                                await store.switchToLayer(layer)
                                            }
                                        },
                                        onDelete: {
                                            layerToDelete = layer
                                            showingDeleteAlert = true
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showingCreateLayerSheet) {
            CreateLayerSheet()
                .environmentObject(store)
        }
        .alert("删除层", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {
                layerToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let layer = layerToDelete {
                    store.deleteLayer(layer)
                    layerToDelete = nil
                }
            }
        } message: {
            if let layer = layerToDelete {
                let nodeCount = store.nodes.filter { $0.layerId == layer.id }.count
                Text("确定要删除层 \"\(layer.displayName)\" 吗？\n这将同时删除该层中的 \(nodeCount) 个节点，此操作无法撤销。")
            }
        }
    }
}

struct LayerRowView: View {
    let layer: Layer
    let nodeCount: Int
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 颜色指示器
            Circle()
                .fill(Color.from(layer.color))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
                )
            
            // 层信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(layer.displayName)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .medium)
                    
                    if isActive {
                        Text("活跃")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(layer.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(nodeCount) 个节点")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 8) {
                if !isActive {
                    Button("激活") {
                        onActivate()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
}

struct CreateLayerSheet: View {
    @EnvironmentObject private var store: WordStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var displayName: String = ""
    @State private var selectedColor: String = "blue"
    
    let availableColors = [
        ("blue", Color.blue),
        ("green", Color.green),
        ("orange", Color.orange),
        ("red", Color.red),
        ("purple", Color.purple),
        ("pink", Color.pink),
        ("yellow", Color.yellow),
        ("teal", Color.teal),
        ("indigo", Color.indigo),
        ("brown", Color.brown)
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section("层信息") {
                    TextField("层名称（英文）", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("显示名称（中文）", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("层颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(availableColors, id: \.0) { colorName, color in
                            Button(action: {
                                selectedColor = colorName
                            }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == colorName ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("创建新层")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let newLayer = store.createLayer(
                            name: name.isEmpty ? displayName.lowercased() : name,
                            displayName: displayName.isEmpty ? name : displayName,
                            color: selectedColor
                        )
                        
                        // 如果这是第一个层，自动激活
                        if store.layers.count == 1 {
                            Task {
                                await store.switchToLayer(newLayer)
                            }
                        }
                        
                        dismiss()
                    }
                    .disabled(name.isEmpty && displayName.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}


// MARK: - 数据管理

struct DataManagementView: View {
    @EnvironmentObject private var store: WordStore
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @State private var showingClearDataAlert = false
    @State private var showingResultAlert = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 外部数据存储设置
                ExternalDataStoragePanel()
                
                // 数据统计
                GroupBox("数据统计") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("数据概览")
                                .fontWeight(.semibold)
                                .gridColumnAlignment(.leading)
                            Spacer()
                        }
                        
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                        
                        GridRow {
                            Text("层数量")
                                .foregroundColor(.secondary)
                            Text("\(store.layers.count)")
                                .fontWeight(.medium)
                        }
                        
                        GridRow {
                            Text("节点总数")
                                .foregroundColor(.secondary)
                            Text("\(store.nodes.count)")
                                .fontWeight(.medium)
                        }
                        
                        GridRow {
                            Text("单词总数")
                                .foregroundColor(.secondary)
                            Text("\(store.words.count)")
                                .fontWeight(.medium)
                        }
                        
                        GridRow {
                            Text("标签总数")
                                .foregroundColor(.secondary)
                            Text("\(store.allTags.count)")
                                .fontWeight(.medium)
                        }
                        
                        GridRow {
                            Text("地点标签")
                                .foregroundColor(.secondary)
                            Text("\(store.allTags.filter { $0.hasCoordinates }.count)")
                                .fontWeight(.medium)
                        }
                        
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                        
                        ForEach(Tag.TagType.predefinedCases, id: \.self) { type in
                            GridRow {
                                Text("\(type.displayName)标签")
                                    .foregroundColor(.secondary)
                                Text("\(store.wordsCount(forTagType: type)) 个单词")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(12)
                }
                
                
                // 危险操作区域
                GroupBox("危险操作") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("数据重置")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        Text("此操作将删除所有单词和标签数据，且无法撤销")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if dataManager.isDataPathSelected {
                            Text("⚠️ 同时会清除外部存储文件中的所有数据")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                        }
                        
                        Button("清除所有数据") {
                            showingClearDataAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                        .disabled(store.words.isEmpty && store.nodes.isEmpty)
                    }
                    .padding(12)
                }
                
                Spacer()
            }
            .padding()
        }
        .alert("确认清除数据", isPresented: $showingClearDataAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("此操作将删除所有单词和标签数据，且无法撤销。")
        }
        .alert(isSuccess ? "成功" : "错误", isPresented: $showingResultAlert) {
            Button("确定") { }
        } message: {
            Text(resultMessage)
        }
    }
    
    private func clearAllData() {
        // 清除内存数据
        store.clearAllData()
        
        // 如果有外部数据存储，清除所有外部文件（包括标签映射）
        if dataManager.isDataPathSelected {
            Task {
                do {
                    // 使用新的清理方法，彻底删除所有外部数据文件
                    try await dataService.clearAllExternalData()
                    await MainActor.run {
                        resultMessage = "所有数据已完全清除（包括外部存储和标签设置）"
                        isSuccess = true
                        showingResultAlert = true
                    }
                } catch {
                    await MainActor.run {
                        resultMessage = "数据已清除，但清理外部存储失败: \(error.localizedDescription)"
                        isSuccess = false
                        showingResultAlert = true
                    }
                }
            }
        } else {
            resultMessage = "所有数据已清除"
            isSuccess = true
            showingResultAlert = true
        }
    }
}

struct SettingRow<Content: View>: View {
    let title: String
    let description: String
    let content: () -> Content
    
    init(title: String, description: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                content()
            }
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - 关于页面

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("单词标签管理器")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("版本 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("功能特点:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    FeatureRow(icon: "tag.fill", text: "智能标签系统")
                    FeatureRow(icon: "magnifyingglass", text: "模糊搜索功能")
                    FeatureRow(icon: "map", text: "地图可视化")
                    FeatureRow(icon: "command", text: "命令面板快捷操作")
                    FeatureRow(icon: "icloud", text: "数据导入导出")
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("基于 SwiftUI 构建")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("© 2024 WordTagger. All rights reserved.")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - 外部数据存储面板

struct ExternalDataStoragePanel: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @EnvironmentObject private var store: WordStore
    
    var body: some View {
        GroupBox(label: Text("外部数据存储").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                
                if dataManager.isDataPathSelected {
                    // 当前路径
                    VStack(alignment: .leading, spacing: 4) {
                        Text("存储位置:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(dataManager.currentDataPath?.path ?? "未设置")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(4)
                    }
                    
                    // 同步状态
                    HStack {
                        Circle()
                            .fill(store.isLoading ? .blue : (dataService.isSaving ? .orange : .green))
                            .frame(width: 6, height: 6)
                        
                        Text(store.isLoading ? "加载数据..." : (dataService.isSaving ? "同步中..." : "已同步"))
                            .font(.caption)
                        
                        Spacer()
                        
                        if let lastSync = dataService.lastSyncTime {
                            Text(formatTime(lastSync))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未设置外部数据存储位置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("📁 选择文件夹来启用外部数据存储")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                // 错误提示
                if let error = dataManager.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }
                
                // 操作按钮
                HStack {
                    Button(dataManager.isDataPathSelected ? "更改位置" : "设置存储") {
                        Task {
                            // 清除之前的错误
                            dataManager.lastError = nil
                            dataManager.selectDataFolder()
                            
                            // 选择完成后自动保存并刷新
                            if dataManager.isDataPathSelected {
                                await store.forceSaveToExternalStorage()
                                // 触发数据重新加载
                                NotificationCenter.default.post(
                                    name: .dataPathChanged,
                                    object: dataManager,
                                    userInfo: ["newPath": dataManager.currentDataPath ?? URL(fileURLWithPath: "")]
                                )
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading || dataService.isSaving)
                    
                    if dataManager.isDataPathSelected {
                        Button("清除") {
                            dataManager.clearDataPath()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // 如果有错误，显示重试按钮
                    if dataManager.lastError != nil {
                        Button("重试") {
                            Task {
                                dataManager.lastError = nil
                                dataManager.selectDataFolder()
                                
                                // 重试成功后也自动保存并刷新
                                if dataManager.isDataPathSelected {
                                    await store.forceSaveToExternalStorage()
                                    NotificationCenter.default.post(
                                        name: .dataPathChanged,
                                        object: dataManager,
                                        userInfo: ["newPath": dataManager.currentDataPath ?? URL(fileURLWithPath: "")]
                                    )
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 数据文件夹设置弹窗

struct DataFolderSetupView: View {
    @StateObject private var dataManager = ExternalDataManager.shared
    @StateObject private var dataService = ExternalDataService.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("设置数据存储位置")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("选择一个文件夹来存储WordTagger的数据")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // 当前路径显示
            if let currentPath = dataManager.currentDataPath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前数据路径:")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        
                        Text(currentPath.path)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            // 错误信息
            if let error = dataManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // 同步状态
            if dataManager.isDataPathSelected {
                HStack {
                    Circle()
                        .fill(dataService.isSaving ? .orange : .green)
                        .frame(width: 8, height: 8)
                    
                    Text(dataService.isSaving ? "同步中..." : "已同步")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastSync = dataService.lastSyncTime {
                        Text("• 上次同步: \(formatTime(lastSync))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            VStack(spacing: 12) {
                // 选择文件夹按钮
                Button(action: {
                    dataManager.selectDataFolder()
                }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text(dataManager.isDataPathSelected ? "更改数据文件夹" : "选择数据文件夹")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                // 完成按钮
                if dataManager.isDataPathSelected {
                    Button(action: {
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("完成设置")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                // 取消按钮
                Button(action: {
                    isPresented = false
                }) {
                    Text("取消")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
        }
        .padding(32)
        .frame(width: 500, height: 600)
        .background(Color(.windowBackgroundColor))
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
}

#Preview {
    SettingsView()
        .environmentObject(WordStore.shared)
}