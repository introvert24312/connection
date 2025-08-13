import SwiftUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: NodeStore
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
    @AppStorage("globalGraphInitialScale") private var globalGraphInitialScale: Double = 1.0
    @AppStorage("detailGraphInitialScale") private var detailGraphInitialScale: Double = 1.0
    @AppStorage("fullscreenGraphInitialScale") private var fullscreenGraphInitialScale: Double = 1.0
    @AppStorage("layerStructureGraphInitialScale") private var layerStructureGraphInitialScale: Double = 0.9
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 界面设置
                GroupBox("界面设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingRow(
                            title: "默认显示音标",
                            description: "在节点列表中自动显示音标信息"
                        ) {
                            Toggle("", isOn: $showPhoneticByDefault)
                                .toggleStyle(SwitchToggleStyle())
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
                            description: "节点详情图谱的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", detailGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $detailGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        SettingRow(
                            title: "全屏图谱初始缩放",
                            description: "Command+L打开的全屏图谱默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", fullscreenGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $fullscreenGraphInitialScale, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 120)
                            }
                        }
                        
                        Divider()
                        
                        SettingRow(
                            title: "层结构图谱初始缩放",
                            description: "命令面板中层结构图谱的默认缩放级别"
                        ) {
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", layerStructureGraphInitialScale))x")
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                
                                Slider(value: $layerStructureGraphInitialScale, in: 0.5...3.0, step: 0.1)
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
                            description: "在节点含义中搜索匹配内容"
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
    @EnvironmentObject private var store: NodeStore
    @State private var showingCreateLayerSheet = false
    @State private var showingDeleteAlert = false
    @State private var layerToDelete: Layer?
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部：当前活跃层状态条
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundColor(.blue)
                        .font(.body)
                    
                    Text("当前活跃层:")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if let currentLayer = store.currentLayer {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.from(currentLayer.color))
                                .frame(width: 12, height: 12)
                            
                            Text(currentLayer.displayName)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("(\(currentLayer.name))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    } else {
                        Text("未选择")
                            .font(.body)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                
                Spacer()
                
                // 快速统计
                if store.currentLayer != nil {
                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text("\(store.getNodesInCurrentLayer().count)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("节点")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 2) {
                            Text("\(store.getNodesInCurrentLayer().count)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("节点")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 主内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 层管理区域
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("层管理")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button(action: {
                                showingCreateLayerSheet = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("创建新层")
                                }
                                .font(.body)
                                .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        
                        // 层列表
                        if store.layers.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                VStack(spacing: 8) {
                                    Text("暂无层级")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text("创建第一个层来开始组织您的节点和数据")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                
                                Button(action: {
                                    showingCreateLayerSheet = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("创建第一个层")
                                    }
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(store.layers, id: \.id) { layer in
                                    LayerRowView(
                                        layer: layer,
                                        wordCount: store.nodes.filter { $0.layerId == layer.id }.count,
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
                                        },
                                        onEdit: { newName in
                                            store.updateLayerDisplayName(layer: layer, newDisplayName: newName)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
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
    let wordCount: Int
    let nodeCount: Int
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void
    let onEdit: (String) -> Void
    
    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    
    var body: some View {
        HStack(spacing: 16) {
            // 左侧：颜色指示器和状态
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.from(layer.color))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if isEditing {
                            TextField("层名称", text: $editingName)
                                .font(.headline)
                                .fontWeight(isActive ? .bold : .semibold)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    saveEdit()
                                }
                                .onAppear {
                                    editingName = layer.displayName
                                }
                        } else {
                            Text(layer.displayName)
                                .font(.headline)
                                .fontWeight(isActive ? .bold : .semibold)
                                .foregroundColor(.primary)
                        }
                        
                        if isActive {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("活跃")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                    
                    Text(layer.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 中间：数据统计
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("\(wordCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("节点")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 2) {
                    Text("\(nodeCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("节点")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // 右侧：操作按钮
            HStack(spacing: 8) {
                if isEditing {
                    // 编辑模式下的按钮
                    Button(action: saveEdit) {
                        Image(systemName: "checkmark")
                            .font(.body)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("保存")
                    
                    Button(action: cancelEdit) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("取消")
                } else {
                    // 正常模式下的按钮
                    if !isActive {
                        Button(action: onActivate) {
                            HStack(spacing: 4) {
                                Image(systemName: "target")
                                    .font(.caption)
                                Text("激活")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    Button(action: startEdit) {
                        Image(systemName: "pencil")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("编辑名称")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("删除层")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
        )
        .shadow(color: isActive ? Color.blue.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
    }
    
    private func startEdit() {
        isEditing = true
        editingName = layer.displayName
    }
    
    private func saveEdit() {
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != layer.displayName {
            onEdit(trimmedName)
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
        editingName = layer.displayName
    }
}

struct CreateLayerSheet: View {
    @EnvironmentObject private var store: NodeStore
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
    
    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 层信息区域
                    GroupBox("层信息") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("层名称（英文）")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("例如: work, study, hobby", text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("显示名称（中文）")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("例如: 工作, 学习, 爱好", text: $displayName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding()
                    }
                    
                    // 层颜色区域
                    GroupBox("层颜色") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("选择用于标识此层的颜色")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                                ForEach(availableColors, id: \.0) { colorName, color in
                                    ColorButton(
                                        colorName: colorName,
                                        color: color,
                                        isSelected: selectedColor == colorName,
                                        onTap: { selectedColor = colorName }
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                    
                    // 预览区域
                    if isFormValid {
                        GroupBox("预览") {
                            LayerPreviewRow(
                                selectedColor: selectedColor,
                                displayName: !displayName.isEmpty ? displayName : (!name.isEmpty ? name : "新层"),
                                name: !name.isEmpty ? name : (!displayName.isEmpty ? displayName.lowercased() : "new_layer")
                            )
                            .padding()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(20)
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
                            name: name.isEmpty ? displayName.lowercased().replacingOccurrences(of: " ", with: "_") : name,
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
                    .disabled(!isFormValid)
                }
            }
        }
        .frame(width: 480, height: 500)
    }
}

// MARK: - Helper Views for CreateLayerSheet

struct ColorButton: View {
    let colorName: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .help(colorName.capitalized)
    }
}

struct LayerPreviewRow: View {
    let selectedColor: String
    let displayName: String
    let name: String
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.from(selectedColor))
                .frame(width: 14, height: 14)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 数据管理

struct DataManagementView: View {
    @EnvironmentObject private var store: NodeStore
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
                
                // 图片管理
                GroupBox("图片管理") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "photo.stack")
                                .foregroundColor(.blue)
                            Text("Markdown 图片存储")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        Text("所有通过编辑器上传的图片都保存在此文件夹中")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Button("打开图片文件夹") {
                                openImagesFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("在 Finder 中显示") {
                                showInFinder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                }
                
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
                            Text("节点总数")
                                .foregroundColor(.secondary)
                            Text("\(store.nodes.count)")
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
                                Text("\(store.nodesCount(forTagType: type)) 个节点")
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
                        
                        Text("此操作将删除所有节点和标签数据，且无法撤销")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if dataManager.isDataPathSelected {
                            Text("⚠️ 同时会清除外部存储文件中的所有数据")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                        }
                        
                        HStack(spacing: 8) {
                            Button("清除所有数据") {
                                showingClearDataAlert = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.red)
                            .disabled(store.nodes.isEmpty && store.nodes.isEmpty)
                            
                            Button("强制刷新界面") {
                                store.forceRefreshUI()
                                resultMessage = "界面已强制刷新"
                                isSuccess = true
                                showingResultAlert = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
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
            Text("此操作将删除所有节点和标签数据，且无法撤销。")
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
    
    private func openImagesFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        
        // 打开文件夹
        NSWorkspace.shared.open(imagesURL)
    }
    
    private func showInFinder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let imagesURL = documentsURL.appendingPathComponent("WordTagger/Images")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        
        // 在 Finder 中显示
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: imagesURL.path)
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
                
                Text("节点标签管理器")
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
    @EnvironmentObject private var store: NodeStore
    
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
        .environmentObject(NodeStore.shared)
}