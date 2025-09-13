import SwiftUI
import CoreLocation
import MapKit
import AppKit

struct TagSidebarView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var filter: String = ""
    @State private var tagTypeSearchQuery: String = ""
    @State private var selectedTagTypes: Set<Tag.TagType> = []
    @State private var expandedGroups: Set<Tag.TagType> = []
    @State private var hiddenTagTypes: Set<Tag.TagType> = [
        .custom("child"),     // 子节点引用标签，系统内部使用
        .custom("compound")   // 复合节点标签，系统内部使用
    ] // 隐藏系统级别的标签类型
    @State private var searchParsedTagTypes: Set<Tag.TagType> = [] // 跟踪从搜索解析出的标签类型
    @Binding var selectedNode: Node?
    @State private var selectedIndex: Int = -1
    @FocusState private var isListFocused: Bool
    @FocusState private var isTagTypeSearchFocused: Bool
    
    // 模块切换状态
    enum SidebarMode {
        case tagFiltering  // 标签筛选模块
        case tagSearch     // 标签搜索模块
    }
    @State private var currentMode: SidebarMode = .tagFiltering  // 默认显示标签筛选模块
    // 注意：expandedTagTypes 现在使用 Store 中的状态，不再是本地 @State
    
    // 标签图谱相关状态（保留以兼容现有代码，但不再使用sheet模式）
    
    // 窗口焦点管理
    @StateObject private var focusManager = WindowFocusManager.shared
    @State private var windowId = UUID()
    
    // 窗口激活状态检查
    private var isWindowActive: Bool {
        return focusManager.isActiveWindow(windowId)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 当前层级指示器
            if let currentLayer = store.currentLayer {
                HStack {
                    Circle()
                        .fill(Color.from(currentLayer.color))
                        .frame(width: 12, height: 12)
                    
                    Text(currentLayer.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(store.getNodesInCurrentLayer().count) 个节点")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.from(currentLayer.color).opacity(0.1))
                
                Divider()
            }
            
            // 模块切换按钮
            HStack(spacing: 0) {
                // 标签筛选模块按钮
                Button(action: { currentMode = .tagFiltering }) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                        VStack(spacing: 0) {
                            Text("标签")
                            Text("筛选")
                        }
                    }
                    .font(.system(size: 14, weight: currentMode == .tagFiltering ? .semibold : .regular))
                    .foregroundColor(currentMode == .tagFiltering ? .blue : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(currentMode == .tagFiltering ? Color.blue.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                
                // 标签搜索模块按钮
                Button(action: { currentMode = .tagSearch }) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        VStack(spacing: 0) {
                            Text("标签")
                            Text("搜索")
                        }
                    }
                    .font(.system(size: 14, weight: currentMode == .tagSearch ? .semibold : .regular))
                    .foregroundColor(currentMode == .tagSearch ? .blue : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(currentMode == .tagSearch ? Color.blue.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 根据选择的模块显示不同内容
            if currentMode == .tagFiltering {
                // 模块1: 标签筛选常驻展示
                tagFilteringModule()
            } else {
                // 模块2: 标签搜索功能
                tagSearchModule()
            }
        }
        .focusable(false)
        // 添加窗口级快捷键处理
        .onKeyPress(.init("1"), phases: .down, action: { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            print("🔑 TagSidebarView: Command+1 - 切换到标签筛选模式")
            currentMode = .tagFiltering
            return .handled
        })
        .onKeyPress(.init("2"), phases: .down, action: { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            print("🔑 TagSidebarView: Command+2 - 切换到标签搜索模式")
            currentMode = .tagSearch
            return .handled
        })
        .onKeyPress(.init("g"), phases: .down, action: { keyPress in
            print("🔑 Key 'g' pressed with modifiers: command=\(keyPress.modifiers.contains(.command)), shift=\(keyPress.modifiers.contains(.shift))")
            guard keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) else { 
                print("🔑 Ignoring - wrong modifiers")
                return .ignored 
            }
            print("🔑 TagSidebarView: Command+Shift+G - 打开标签图谱")
            openTagTypeGraphShortcut()
            return .handled
        })
        .onKeyPress(.escape) {
            // 按ESC键隐藏标签管理侧边栏
            print("🔑 TagSidebarView: ESC键按下，隐藏标签管理")
            NotificationCenter.default.post(name: Notification.Name("toggleSidebar"), object: nil)
            return .handled
        }
        .onAppear {
            print("🔑 TagSidebarView 出现")
            // TagSidebarView 是主窗口的组件，不需要单独注册窗口
            // 窗口注册由 WordTaggerApp 统一管理
        }
        .onDisappear {
            print("🔑 TagSidebarView 消失")
            // 不需要单独注销窗口
        }
        // 添加额外的ESC键处理层
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            print("🔑 窗口获得键盘焦点")
            // 如果是当前窗口获得焦点，更新活跃状态
            if let window = notification.object as? NSWindow,
               window.isKeyWindow {
                focusManager.setActiveWindow(windowId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openTagSearch"))) { _ in
            print("🏷️ TagSidebarView: 收到打开标签搜索通知")
            
            // TagSidebarView作为ContentView的子视图，不需要单独检查窗口状态
            // 如果能收到通知，说明父窗口已经是活跃的
            
            // Command+F 在两个模块之间切换
            if currentMode == .tagFiltering {
                print("🏷️ TagSidebarView: 从标签筛选切换到标签搜索")
                currentMode = .tagSearch
                // 延迟一下确保UI切换完成后再设置焦点
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTagTypeSearchFocused = true
                    print("🏷️ TagSidebarView: 切换到标签搜索模式并聚焦搜索框")
                }
            } else {
                print("🏷️ TagSidebarView: 从标签搜索切换到标签筛选")
                currentMode = .tagFiltering
                print("🏷️ TagSidebarView: 切换到标签筛选模式")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("restorePreviousTagFilterState"))) { _ in
            print("🔄 TagSidebarView: 收到恢复标签筛选状态通知")
            
            // 确保处于标签筛选模式
            currentMode = .tagFiltering
            
            // 延迟同步所有UI状态，确保Store的状态已经恢复
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // 1. 同步展开的标签类型
                expandedGroups = store.expandedTagTypes
                
                // 2. 如果有选中的标签类型，也要同步到搜索模块的选中状态
                if !store.expandedTagTypes.isEmpty {
                    selectedTagTypes = store.expandedTagTypes
                }
                
                print("🔄 TagSidebarView: 完整同步UI状态完成")
                print("   - currentMode: \(currentMode)")
                print("   - expandedGroups: \(expandedGroups.map { $0.displayName })")
                print("   - selectedTagTypes: \(selectedTagTypes.map { $0.displayName })")
                print("   - store.selectedTag: '\(store.selectedTag?.value ?? "nil")'")
                print("   - store.expandedTagTypes: \(store.expandedTagTypes.map { $0.displayName })")
                print("   - store.showAllTagTypeNodes: \(store.showAllTagTypeNodes)")
            }
        }
        .onChange(of: store.selectedNode) { _, newNode in
            // 🔧 当store中的节点被选中时（如从地图选择），不清除标签筛选状态
            // 因为我们现在希望地图选择能触发标签展开
            if newNode != nil {
                print("🗺️ TagSidebarView: 检测到节点选择，保持标签筛选状态")
                currentMode = .tagFiltering
                
                // 🔄 同步expandedGroups状态与store的expandedTagTypes
                // 确保UI反映store中的标签展开状态
                if let selectedTag = store.selectedTag {
                    expandedGroups.insert(selectedTag.type)
                    print("🔄 同步UI展开状态: 展开标签类型 '\(selectedTag.type.displayName)'")
                }
            }
        }
        .onChange(of: store.expandedTagTypes) { _, newExpandedTypes in
            // 当展开的标签类型改变时，同步UI的展开状态
            print("🔄 TagSidebarView: store.expandedTagTypes 改变，同步UI展开状态")
            print("   - store展开的类型: \(newExpandedTypes.map { $0.displayName })")
            
            // 同步expandedGroups与store的expandedTagTypes（用于标签搜索模块）
            expandedGroups = newExpandedTypes
            
            // 🔄 完全同步selectedTagTypes与store的expandedTagTypes状态
            if newExpandedTypes.isEmpty {
                // 如果store清空了展开状态，也清空本地选中状态
                selectedTagTypes.removeAll()
                tagTypeSearchQuery = ""
                currentMode = .tagFiltering
                print("🧹 清空本地UI状态以匹配store的清空状态")
            } else {
                // 如果有展开的标签类型，同步到selectedTagTypes
                for tagType in newExpandedTypes {
                    selectedTagTypes.insert(tagType)
                }
                print("🔄 同步搜索模块选中状态: \(selectedTagTypes.map { $0.displayName })")
            }
            
            updateDisplayedNodesForExpandedTypes(newExpandedTypes)
        }
    }
    
    // MARK: - 模块1: 标签筛选
    @ViewBuilder
    private func tagFilteringModule() -> some View {
        VStack(spacing: 0) {
            // 标签类型搜索框
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                    TextField("输入标签类型快速定位...", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onChange(of: filter) { _, newValue in
                            // 🆕 输入变化时自动展开匹配的标签类型
                            // 使用 DispatchQueue 确保计算在下一个运行循环中进行
                            DispatchQueue.main.async {
                                print("🔍 搜索词变化: '\(newValue)'")
                                print("🔍 当前层可用标签类型: \(self.uniqueTagTypes.map { $0.displayName })")
                                
                                if !newValue.isEmpty {
                                    let matchedTypes = self.filteredTagTypes
                                    print("🔍 匹配到的标签类型: \(matchedTypes.map { $0.displayName })")
                                    
                                    if !matchedTypes.isEmpty {
                                        let matchedTypesSet = Set(matchedTypes)
                                        store.setExpandedTagTypes(matchedTypesSet)
                                        print("🔍 自动展开 \(matchedTypes.count) 个匹配的标签类型: \(matchedTypes.map { $0.displayName })")
                                    } else {
                                        print("🔍 没有匹配的标签类型，保持当前状态")
                                    }
                                } else {
                                    // 清空搜索时，折叠所有标签类型
                                    store.setExpandedTagTypes(Set<Tag.TagType>())
                                    print("🔍 清空搜索，折叠所有标签类型")
                                }
                            }
                        }
                        .onSubmit {
                            // 回车时也展开（保持兼容性）
                            if !filteredTagTypes.isEmpty {
                                let matchedTypesSet = Set(filteredTagTypes)
                                store.setExpandedTagTypes(matchedTypesSet)
                                print("🔍 回车展开 \(filteredTagTypes.count) 个匹配的标签类型: \(filteredTagTypes.map { $0.displayName })")
                            }
                        }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                if !filter.isEmpty {
                    let searchTerms = filter.components(separatedBy: .whitespaces)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    if searchTerms.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("匹配 \(filteredTagTypes.count) 个标签类型（多词搜索）")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            // 显示搜索词
                            HStack(spacing: 4) {
                                ForEach(searchTerms, id: \.self) { term in
                                    Text(term)
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("匹配 \(filteredTagTypes.count) 个标签类型")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // "全部标签"选项
                    Button(action: {
                        store.selectTag(nil)
                        print("🏷️ 选择了全部标签")
                    }) {
                        HStack {
                            Text("全部标签")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            if store.selectedTag == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(store.selectedTag == nil ? Color.blue.opacity(0.1) : Color.clear)
                        )
                        .foregroundColor(store.selectedTag == nil ? .blue : .primary)
                    }
                    .buttonStyle(.plain)
                    
                    // 各个标签类型 - 优先显示匹配的标签类型
                    ForEach(orderedTagTypes, id: \.self) { tagType in
                        tagTypeSection(tagType)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    // MARK: - 标签类型组件
    @ViewBuilder
    private func tagTypeSection(_ tagType: Tag.TagType) -> some View {
        let isExpanded = store.expandedTagTypes.contains(tagType)
        let tags = tagsOfType(tagType)
        let isMatched = !filter.isEmpty && filteredTagTypes.contains(tagType)
        
        VStack(spacing: 0) {
            // 标签类型头部
            Button(action: {
                print("🖱️ TagSidebarView: 标签类型按钮被点击 - \(tagType.displayName)")
                print("🖱️ TagSidebarView: 当前展开状态: \(isExpanded)")
                
                // 总是切换展开/折叠状态
                store.toggleExpandedTagType(tagType)
                
                // 如果展开了，选择标签类型显示该类型下的所有节点
                if !isExpanded {
                    store.selectTagType(tagType)
                    print("🏷️ 展开并选择标签类型: \(tagType.displayName)，显示该类型下的所有节点")
                } else {
                    print("🏷️ 折叠标签类型: \(tagType.displayName)")
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text(tagType.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isMatched ? .blue : .primary)
                    
                    // 搜索匹配指示器
                    if isMatched {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                            .opacity(0.8)
                    }
                    
                    Spacer()
                    
                    // 图谱按钮
                    Button(action: {
                        print("🖱️ Network button clicked for tag type: \(tagType.displayName)")
                        openTagTypeGraphInNewWindow(tagType)
                    }) {
                        Image(systemName: "network")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                            .opacity(0.8)
                    }
                    .buttonStyle(.plain)
                    .help("查看标签类型关系图谱 (⌘⇧G)")
                    
                    Text("(\(tags.count))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Color(NSColor.controlBackgroundColor)
                        .opacity(isMatched ? 0.8 : 0.3)
                        .overlay(
                            // 匹配时添加左侧蓝色边框
                            isMatched ? 
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: 3)
                                .frame(maxWidth: .infinity, alignment: .leading) :
                            nil
                        )
                )
            }
            .buttonStyle(.plain)
            
            // 该类型下的标签列表
            if isExpanded {
                ForEach(tags, id: \.id) { tag in
                    Button(action: {
                        // 显示该标签类型的所有节点，但高亮显示包含这个具体标签的节点
                        store.selectTagWithFocus(tag)
                        print("🏷️ 选择了具体标签: \(tag.type.displayName) - \(tag.value)，显示标签类型所有节点但高亮此标签对应的节点")
                    }) {
                        HStack {
                            Text(tag.value)
                                .font(.system(size: 14))
                            Spacer()
                            if store.selectedTag?.id == tag.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 32) // 缩进显示层级
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(store.selectedTag?.id == tag.id ? Color.blue.opacity(0.1) : Color.clear)
                        )
                        .foregroundColor(store.selectedTag?.id == tag.id ? .blue : .primary)
                        .contentShape(Rectangle()) // 确保整个区域都可点击
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 模块2: 标签搜索
    @ViewBuilder  
    private func tagSearchModule() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标签类型多选器
            VStack(alignment: .leading, spacing: 12) {
                Text("选择标签类型")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    
                    // 标签类型搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                        TextField("搜索标签类型...", text: $tagTypeSearchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .focused($isTagTypeSearchFocused)
                            .onChange(of: tagTypeSearchQuery) { _, newValue in
                                // 🔍 只用于更新搜索结果预览，不自动选择标签类型
                                print("🔍 TagSidebarView: 搜索查询变更为 '\(newValue)'，更新预览结果")
                            }
                            .onSubmit {
                                // 🎯 回车键确认选择 - 保持在标签搜索模式
                                print("⏎ 检测到回车键，确认选择标签类型")
                                if !searchableTagTypes.isEmpty {
                                    let firstType = searchableTagTypes[0]
                                    print("🎯 确认选择标签类型: \(firstType.displayName)")
                                    
                                    // 🆕 沿用标签筛选的逻辑：选择标签类型并展开
                                    store.selectTagType(firstType)
                                    store.toggleExpandedTagType(firstType)
                                    
                                    // 清空搜索框，但保持在标签搜索模式
                                    tagTypeSearchQuery = ""
                                    
                                    // 🔄 不再自动切换到标签筛选模式，保持在当前搜索模式
                                    print("🔄 保持在标签搜索模式")
                                } else {
                                    print("⚠️ 没有搜索结果可以选择")
                                }
                            }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    
                    // 隐藏选项
                    
                    // 搜索结果和添加按钮
                    if !tagTypeSearchQuery.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(searchableTagTypes, id: \.rawValue) { type in
                                    TagTypeSearchResultButton(
                                        type: type,
                                        isAlreadySelected: store.expandedTagTypes.contains(type),
                                        onAdd: {
                                            // 🆕 沿用标签筛选逻辑，不是添加到选中列表
                                            store.selectTagType(type)
                                            store.toggleExpandedTagType(type)
                                            
                                            // 清空搜索框，但保持在标签搜索模式
                                            tagTypeSearchQuery = ""
                                            // 🔄 不再自动切换到标签筛选模式
                                            print("🔄 标签类型已选择，保持在标签搜索模式")
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxHeight: 40)
                        
                        // 🆕 标签值搜索结果
                        if !searchableTagValues.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("匹配的标签值 (\(searchableTagValues.count))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.green)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(searchableTagValues.prefix(10), id: \.id) { tag in
                                            TagValueSearchResultButton(
                                                tag: tag,
                                                onSelect: {
                                                    // 🎯 选择具体标签值 - 沿用标签筛选逻辑
                                                    store.selectTagWithFocus(tag)
                                                    
                                                    // 清空搜索框，但保持在标签搜索模式
                                                    tagTypeSearchQuery = ""
                                                    // 🔄 不再自动切换到标签筛选模式
                                                    print("🔄 标签值已选择，保持在标签搜索模式")
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                                .frame(maxHeight: 60)
                            }
                            .padding(.top, 4)
                        }
                        
                        // 🆕 多标签类型解析提示
                        let searchTerms = tagTypeSearchQuery.components(separatedBy: .whitespaces)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        
                        if searchTerms.count > 1 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("多标签类型搜索")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                                
                                HStack {
                                    Text("解析到 \(searchTerms.count) 个搜索词:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(searchTerms, id: \.self) { term in
                                        Text("'\(term)'")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.blue.opacity(0.1))
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                    }
                    
                    // 已选择的标签类型
                    if !selectedTagTypes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("已选择的标签类型")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                ForEach(Array(selectedTagTypes.sorted(by: { $0.displayName < $1.displayName })), id: \.self) { type in
                                    SelectedTagTypeChip(
                                        type: type,
                                        isSearchParsed: searchParsedTagTypes.contains(type),
                                        onRemove: {
                                            removeTagType(type)
                                        }
                                    )
                                }
                            }
                            
                            HStack {
                                Text("\(selectedTagTypes.count) 种标签类型")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("清空") {
                                    selectedTagTypes.removeAll()
                                    expandedGroups.removeAll()
                                    searchParsedTagTypes.removeAll()
                                    print("🧹 清空所有选中的标签类型")
                                }
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 标签组列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if selectedTagTypes.isEmpty {
                        // 未选择标签类型时的提示
                        VStack(spacing: 16) {
                            Image(systemName: "tag.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("请选择标签类型")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("选择上方的标签类型来查看相关标签")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        // 显示选中的标签类型组
                        ForEach(Array(selectedTagTypes.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { tagType in
                            TagGroupView(
                                tagType: tagType,
                                tags: tagsOfType(tagType), // Use our working method
                                isExpanded: expandedGroups.contains(tagType),
                                onToggleExpanded: {
                                    toggleGroup(tagType)
                                },
                                onSelectTag: { tag in
                                    store.selectTag(tag) // Direct call to store
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    
    // MARK: - 标签筛选相关计算属性
    // 获取当前层实际存在的唯一标签类型
    private var uniqueTagTypes: [Tag.TagType] {
        let currentLayerTagTypes = store.currentLayerTags.map { $0.type }
        let uniqueTypes = Array(Set(currentLayerTagTypes))
        // 过滤掉系统级别的标签类型
        let visibleTypes = uniqueTypes.filter { !hiddenTagTypes.contains($0) }
        // 按类型名称排序，确保consistent显示顺序
        return visibleTypes.sorted { $0.displayName < $1.displayName }
    }
    
    // 根据搜索过滤的标签类型 - 支持空格分隔的多标签类型搜索
    private var filteredTagTypes: [Tag.TagType] {
        guard !filter.isEmpty else { return [] }
        
        // 🆕 支持多标签类型搜索语法
        let searchTerms = filter.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var allMatchingTypes = Set<Tag.TagType>()
        
        // 对每个搜索词查找匹配的标签类型
        for searchTerm in searchTerms {
            let matchingTypes = uniqueTagTypes.filter { tagType in
                // 搜索显示名称
                if tagType.displayName.localizedCaseInsensitiveContains(searchTerm) {
                    return true
                }
                
                // 搜索rawValue
                if tagType.rawValue.localizedCaseInsensitiveContains(searchTerm) {
                    return true
                }
                
                // 搜索该类型下的标签值
                let tagsOfThisType = store.currentLayerTags.filter { $0.type == tagType }
                for tag in tagsOfThisType {
                    if tag.value.localizedCaseInsensitiveContains(searchTerm) {
                        return true
                    }
                }
                
                return false
            }
            
            allMatchingTypes.formUnion(matchingTypes)
        }
        
        return Array(allMatchingTypes)
    }
    
    // 按匹配优先级排序的标签类型：匹配的在前，非匹配的在后
    private var orderedTagTypes: [Tag.TagType] {
        if filter.isEmpty {
            return uniqueTagTypes
        }
        
        let matchingTypes = filteredTagTypes
        let nonMatchingTypes = uniqueTagTypes.filter { !matchingTypes.contains($0) }
        
        // 匹配的标签类型在前面，非匹配的在后面
        return matchingTypes + nonMatchingTypes
    }
    
    // MARK: - 标签图谱相关方法
    
    /// 通过快捷键打开标签图谱
    private func openTagTypeGraphShortcut() {
        print("🔍 openTagTypeGraphShortcut() called")
        
        // 检查是否有选中的标签类型
        if let currentTagType = getCurrentSelectedTagType() {
            print("🕸️ Found current tag type: \(currentTagType.displayName)")
            openTagTypeGraphInNewWindow(currentTagType)
        } else {
            print("⚠️ 没有选中的标签类型，尝试使用第一个可用的标签类型")
            
            // 如果没有选中的，尝试使用第一个可用的标签类型
            if let firstType = uniqueTagTypes.first {
                print("🔄 Using first available tag type: \(firstType.displayName)")
                openTagTypeGraphInNewWindow(firstType)
            } else {
                print("❌ No tag types available at all")
            }
        }
    }
    
    /// 在新窗口中打开标签图谱
    private func openTagTypeGraphInNewWindow(_ tagType: Tag.TagType) {
        print("🕸️ 在新窗口中打开标签图谱: \(tagType.displayName)")
        NotificationCenter.default.post(
            name: NSNotification.Name("openTagTypeGraph"),
            object: tagType
        )
    }
    
    /// 获取当前选中的标签类型
    private func getCurrentSelectedTagType() -> Tag.TagType? {
        // 如果有选中的具体标签，返回其类型
        if let selectedTag = store.selectedTag {
            return selectedTag.type
        }
        
        // 如果没有选中具体标签，可以考虑返回第一个展开的标签类型
        if let firstExpandedType = store.expandedTagTypes.first {
            return firstExpandedType
        }
        
        // 如果都没有，返回第一个可用的标签类型
        return uniqueTagTypes.first
    }
    
    // 获取当前层指定类型的所有标签
    private func tagsOfType(_ tagType: Tag.TagType) -> [Tag] {
        return store.currentLayerTags.filter { $0.type == tagType }
            .sorted { $0.value < $1.value } // 按值排序
    }
    
    // 当前标签筛选显示文本
    private var currentTagFilterDisplay: String {
        if let selectedTag = store.selectedTag {
            return "\(selectedTag.type.displayName): \(selectedTag.value)"
        }
        return "全部标签"
    }
    
    // 搜索匹配的标签类型 - 支持双语搜索
    private var searchableTagTypes: [Tag.TagType] {
        guard !tagTypeSearchQuery.isEmpty else { return [] }
        
        // 获取当前层实际存在的标签类型（不仅仅是预定义的）
        let allExistingTypes = Set(store.currentLayerTags.map { $0.type })
        let tagManager = TagMappingManager.shared
        
        print("🔍 TagSidebarView: 搜索标签类型 '\(tagTypeSearchQuery)'")
        print("🔍 现有标签类型数量: \(allExistingTypes.count)")
        for type in allExistingTypes {
            print("  - \(type.displayName) (rawValue: \(type.rawValue))")
        }
        
        let matchingTypes = allExistingTypes.filter { tagType in
            // 过滤掉隐藏的标签类型
            guard !hiddenTagTypes.contains(tagType) else { 
                print("  ❌ 跳过隐藏标签类型: \(tagType.displayName)")
                return false 
            }
            
            _ = tagTypeSearchQuery.lowercased() // 预留给未来的小写搜索需求
            
            // 1. 搜索displayName（显示名称，如"牛肉类型"）
            if tagType.displayName.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                print("  ✅ 匹配displayName: \(tagType.displayName)")
                return true
            }
            
            // 2. 搜索rawValue（标签代码，如"beef"）
            if tagType.rawValue.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                print("  ✅ 匹配rawValue: \(tagType.rawValue)")
                return true
            }
            
            // 3. 对于自定义标签类型，从TagMappingManager搜索所有相关映射
            if case .custom(let key) = tagType {
                print("  🔍 检查自定义标签类型: key=\(key)")
                
                // 搜索该key对应的所有可能的映射
                let matchingMappings = tagManager.tagMappings.filter { mapping in
                    mapping.key.lowercased() == key.lowercased()
                }
                
                print("    - 找到 \(matchingMappings.count) 个映射")
                for mapping in matchingMappings {
                    print("      映射: \(mapping.key) -> \(mapping.typeName)")
                }
                
                // 检查映射中的typeName是否匹配搜索查询
                for mapping in matchingMappings {
                    if mapping.typeName.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                        print("  ✅ 匹配映射typeName: \(mapping.typeName)")
                        return true
                    }
                    if mapping.key.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                        print("  ✅ 匹配映射key: \(mapping.key)")
                        return true
                    }
                }
                
                // 4. 额外搜索：检查该类型下是否有标签值匹配搜索查询
                let tagsOfThisType = store.currentLayerTags.filter { $0.type == tagType }
                for tag in tagsOfThisType {
                    if tag.value.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                        print("  ✅ 匹配标签值: \(tag.value)")
                        return true
                    }
                }
            }
            
            print("  ❌ 无匹配: \(tagType.displayName)")
            return false
        }.sorted { $0.displayName < $1.displayName }
        
        print("🔍 搜索结果: \(matchingTypes.count) 个匹配的标签类型")
        for type in matchingTypes {
            print("  ✅ \(type.displayName)")
        }
        
        return matchingTypes
    }
    
    // 🆕 搜索匹配的标签值 - 支持标签值模糊匹配
    private var searchableTagValues: [Tag] {
        guard !tagTypeSearchQuery.isEmpty else { return [] }
        
        let currentLayerTags = store.currentLayerTags
        print("🔍 TagSidebarView: 搜索标签值 '\(tagTypeSearchQuery)'")
        print("🔍 当前层标签总数: \(currentLayerTags.count)")
        
        let matchingTags = currentLayerTags.filter { tag in
            // 过滤掉系统级别的标签类型
            if hiddenTagTypes.contains(tag.type) {
                return false
            }
            
            // 1. 搜索标签值（如"牛肉片"、"beef slice"）
            if tag.value.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                print("  ✅ 匹配标签值: \(tag.value) (\(tag.type.displayName))")
                return true
            }
            
            // 2. 搜索标签类型显示名称中包含查询词的标签
            if tag.type.displayName.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                print("  ✅ 匹配标签类型: \(tag.type.displayName) - \(tag.value)")
                return true
            }
            
            // 3. 🆕 搜索快捷键（TagMapping的key）
            if case .custom(let key) = tag.type {
                if key.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                    print("  ✅ 匹配快捷键: \(key) -> \(tag.value) (\(tag.type.displayName))")
                    return true
                }
                
                // 4. 🆕 通过TagMappingManager搜索相关映射
                let tagManager = TagMappingManager.shared
                let matchingMappings = tagManager.tagMappings.filter { mapping in
                    mapping.key.lowercased() == key.lowercased()
                }
                
                for mapping in matchingMappings {
                    // 搜索映射中的key
                    if mapping.key.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                        print("  ✅ 匹配映射key: \(mapping.key) -> \(tag.value)")
                        return true
                    }
                    // 搜索映射中的typeName
                    if mapping.typeName.localizedCaseInsensitiveContains(tagTypeSearchQuery) {
                        print("  ✅ 匹配映射类型名: \(mapping.typeName) -> \(tag.value)")
                        return true
                    }
                }
            }
            
            return false
        }.sorted { tag1, tag2 in
            // 按标签值排序，确保一致的显示顺序
            tag1.value < tag2.value
        }
        
        print("🔍 标签值搜索结果: \(matchingTags.count) 个匹配的标签")
        for tag in matchingTags.prefix(5) {
            print("  - \(tag.type.displayName): '\(tag.value)'")
        }
        
        return matchingTags
    }
    
    private func addTagType(_ tagType: Tag.TagType) {
        selectedTagTypes.insert(tagType)
        expandedGroups.insert(tagType)
        // 清空搜索框
        tagTypeSearchQuery = ""
    }
    
    private func removeTagType(_ tagType: Tag.TagType) {
        selectedTagTypes.remove(tagType)
        expandedGroups.remove(tagType)
        // 如果移除的是搜索解析的标签类型，也要从搜索解析记录中移除
        searchParsedTagTypes.remove(tagType)
        print("🗑️ 手动移除标签类型: \(tagType.displayName)")
    }
    
    private func toggleTagType(_ tagType: Tag.TagType) {
        if selectedTagTypes.contains(tagType) {
            removeTagType(tagType)
        } else {
            addTagType(tagType)
        }
    }
    
    private func toggleGroup(_ tagType: Tag.TagType) {
        if expandedGroups.contains(tagType) {
            expandedGroups.remove(tagType)
        } else {
            expandedGroups.insert(tagType)
        }
    }
    
    private func getTagsForType(_ tagType: Tag.TagType) -> [Tag] {
        var tags: [Tag]
        
        // 根据搜索状态和当前层获取标签
        if !store.searchQuery.isEmpty {
            tags = store.getRelevantTags(for: store.searchQuery)
        } else {
            // Always use current layer tags for layer-based filtering
            tags = store.currentLayerTags
        }
        
        // 按类型过滤
        tags = tags.filter { $0.type == tagType }
        
        // 过滤掉内部管理标签
        tags = tags.filter { tag in
            if case .custom(let key) = tag.type {
                return !(key == "compound" || key == "child")
            }
            return true
        }
        
        // 按本地搜索文本过滤
        if !filter.isEmpty {
            tags = tags.filter { $0.value.localizedCaseInsensitiveContains(filter) }
        }
        
        print("🏷️ TagSidebarView: getTagsForType(\(tagType.displayName)) 返回 \(tags.count) 个标签")
        for tag in tags {
            print("  - \(tag.value)")
        }
        
        // 按值排序
        return tags.sorted { $0.value < $1.value }
    }
    
    // FIXME: Temporarily disabled - will be fixed in next commit
    /*
    private func selectTag(_ tag: Tag) {
        DispatchQueue.main.async {
            print("🏷️ TagSidebarView.selectTag: 点击标签 \(tag.value) (类型: \(tag.type.displayName))")
            
            // 🧹 先清除之前的选中状态，避免多个节点同时被选中
            print("🧹 清除之前的选中状态")
            self.selectedNode = nil
            store.setSelectedNode(nil)
            
            // 使用新的标签类型模式：显示同标签类型的所有节点
            store.setSelectedTagWithTypeMode(tag)
        }
    }
    */
    
    // 当展开的标签类型改变时，更新显示的节点
    private func updateDisplayedNodesForExpandedTypes(_ newExpandedTypes: Set<Tag.TagType>) {
        print("🔄 TagSidebarView: updateDisplayedNodesForExpandedTypes called with \(newExpandedTypes.count) types")
        
        // 新逻辑：展开标签类型不直接触发节点显示
        // 只有当用户点击具体标签值时才显示节点
        print("📋 标签类型展开状态已更新，等待用户点击具体标签值")
    }
    
    // 处理标签类型搜索，支持空格分隔的多标签类型语法
    private func handleTagTypeSearch(_ query: String) {
        print("🔍 TagSidebarView: handleTagTypeSearch('\(query)')")
        
        // 如果搜索查询为空，清空自动选择的标签类型
        guard !query.isEmpty else { 
            // 清空所有从搜索解析出的标签类型
            clearSearchParsedTagTypes()
            return 
        }
        
        // 🆕 多标签类型语法：按空格分隔搜索词
        let searchTerms = query.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        print("🔍 解析出 \(searchTerms.count) 个搜索词: \(searchTerms)")
        
        // 跟踪从当前搜索解析出的标签类型
        var newlyParsedTagTypes = Set<Tag.TagType>()
        
        // 对每个搜索词进行匹配
        for searchTerm in searchTerms {
            let matchedTypes = findMatchingTagTypes(for: searchTerm)
            newlyParsedTagTypes.formUnion(matchedTypes)
            
            print("🎯 搜索词 '\(searchTerm)' 匹配到 \(matchedTypes.count) 个标签类型: \(matchedTypes.map { $0.displayName })")
        }
        
        // 🔄 同步标签类型选择状态
        syncTagTypeSelections(newlyParsedTypes: newlyParsedTagTypes)
    }
    
    // 查找匹配指定搜索词的标签类型
    private func findMatchingTagTypes(for searchTerm: String) -> Set<Tag.TagType> {
        let currentLayerTags = store.currentLayerTags
        let allExistingTypes = Set(currentLayerTags.map { $0.type })
        let tagManager = TagMappingManager.shared
        var matchingTypes = Set<Tag.TagType>()
        
        print("🔍 为搜索词 '\(searchTerm)' 查找匹配的标签类型")
        
        for tagType in allExistingTypes {
            // 过滤掉隐藏的标签类型
            guard !hiddenTagTypes.contains(tagType) else { continue }
            
            var isMatch = false
            
            // 1. 匹配显示名称（如"牛肉类型"）
            if tagType.displayName.localizedCaseInsensitiveContains(searchTerm) {
                print("  ✅ 匹配displayName: \(tagType.displayName)")
                isMatch = true
            }
            
            // 2. 匹配rawValue（如"beef"）
            if tagType.rawValue.localizedCaseInsensitiveContains(searchTerm) {
                print("  ✅ 匹配rawValue: \(tagType.rawValue)")
                isMatch = true
            }
            
            // 3. 对于自定义标签类型，搜索映射
            if case .custom(let key) = tagType {
                let matchingMappings = tagManager.tagMappings.filter { mapping in
                    mapping.key.lowercased() == key.lowercased()
                }
                
                for mapping in matchingMappings {
                    if mapping.typeName.localizedCaseInsensitiveContains(searchTerm) ||
                       mapping.key.localizedCaseInsensitiveContains(searchTerm) {
                        print("  ✅ 匹配映射: \(mapping.typeName)")
                        isMatch = true
                        break
                    }
                }
            }
            
            // 4. 智能搜索：搜索该类型下的标签值
            if !isMatch {
                let tagsOfThisType = currentLayerTags.filter { $0.type == tagType }
                for tag in tagsOfThisType {
                    if tag.value.localizedCaseInsensitiveContains(searchTerm) {
                        print("  ✅ 匹配标签值: \(tag.value) -> \(tagType.displayName)")
                        isMatch = true
                        break
                    }
                }
            }
            
            if isMatch {
                matchingTypes.insert(tagType)
            }
        }
        
        return matchingTypes
    }
    
    // 同步标签类型选择状态
    private func syncTagTypeSelections(newlyParsedTypes: Set<Tag.TagType>) {
        print("🔄 同步标签类型选择状态")
        print("  - 新解析的类型: \(newlyParsedTypes.map { $0.displayName })")
        print("  - 当前选中的类型: \(selectedTagTypes.map { $0.displayName })")
        print("  - 之前搜索解析的类型: \(searchParsedTagTypes.map { $0.displayName })")
        
        // 🔄 更新选中的标签类型
        for tagType in newlyParsedTypes {
            if !selectedTagTypes.contains(tagType) {
                print("  ➕ 添加标签类型: \(tagType.displayName)")
                selectedTagTypes.insert(tagType)
                expandedGroups.insert(tagType)
            }
        }
        
        // 🗑️ 移除不再匹配的搜索解析的标签类型
        let searchParsedTypesToRemove = searchParsedTagTypes.filter { parsedType in
            !newlyParsedTypes.contains(parsedType)
        }
        
        for tagType in searchParsedTypesToRemove {
            print("  ➖ 移除搜索解析的标签类型: \(tagType.displayName)")
            selectedTagTypes.remove(tagType)
            expandedGroups.remove(tagType)
        }
        
        // 🔄 更新搜索解析的标签类型记录
        searchParsedTagTypes = newlyParsedTypes
        
        print("🔄 同步完成")
        print("  - 当前选中类型: \(selectedTagTypes.map { $0.displayName })")
        print("  - 当前搜索解析类型: \(searchParsedTagTypes.map { $0.displayName })")
    }
    
    
    // 清空从搜索解析出的标签类型
    private func clearSearchParsedTagTypes() {
        print("🧹 清空搜索解析的标签类型")
        print("  - 将移除的类型: \(searchParsedTagTypes.map { $0.displayName })")
        
        // 只移除从搜索解析出的标签类型，保留用户手动选择的
        for tagType in searchParsedTagTypes {
            selectedTagTypes.remove(tagType)
            expandedGroups.remove(tagType)
        }
        
        // 清空搜索解析记录
        searchParsedTagTypes.removeAll()
        
        print("🧹 清空完成，当前选中类型: \(selectedTagTypes.map { $0.displayName })")
    }

// MARK: - 标签值搜索结果按钮

struct TagValueSearchResultButton: View {
    let tag: Tag
    let onSelect: () -> Void
    
    // 获取快捷键信息
    private var shortcutKey: String? {
        if case .custom(let key) = tag.type {
            return key
        }
        return nil
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // 标签类型指示器
                    Circle()
                        .fill(Color.from(tagType: tag.type))
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        // 标签值（主要显示）
                        Text(tag.value)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        // 标签类型名称
                        Text(tag.type.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                
                // 快捷键信息
                if let shortcut = shortcutKey {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        
                        Text("快捷键: \(shortcut)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.1))
                            )
                        
                        Spacer()
                    }
                }
                
                // 额外信息（如果是快捷键类型）
                if tag.isShortcutType {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        
                        Text("快捷格式")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签类型搜索结果按钮

struct TagTypeSearchResultButton: View {
    let type: Tag.TagType
    let isAlreadySelected: Bool
    let onAdd: () -> Void
    
    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.from(tagType: type))
                    .frame(width: 8, height: 8)
                
                Text(type.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isAlreadySelected ? .secondary : .primary)
                
                if !isAlreadySelected {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isAlreadySelected ? Color(NSColor.controlBackgroundColor) : Color.blue.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isAlreadySelected ? Color(NSColor.tertiaryLabelColor) : Color.blue, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAlreadySelected)
    }
}

// MARK: - 已选择标签类型芯片

struct SelectedTagTypeChip: View {
    let type: Tag.TagType
    let isSearchParsed: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            // 搜索解析指示器
            if isSearchParsed {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
            }
            
            Circle()
                .fill(Color.from(tagType: type))
                .frame(width: 8, height: 8)
            
            Text(type.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSearchParsed ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSearchParsed ? Color.green : Color.blue, lineWidth: 1)
        )
    }
}

// MARK: - 标签类型多选按钮

struct TagTypeMultiSelectButton: View {
    let type: Tag.TagType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // 选择状态指示
                ZStack {
                    Circle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                
                // 标签类型指示和名称
                Circle()
                    .fill(Color.from(tagType: type))
                    .frame(width: 12, height: 12)
                
                Text(type.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color(NSColor.tertiaryLabelColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签组视图

struct TagGroupView: View {
    let tagType: Tag.TagType
    let tags: [Tag]
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onSelectTag: (Tag) -> Void
    @EnvironmentObject private var store: NodeStore
    
    var body: some View {
        VStack(spacing: 0) {
            // 组标题头部
            Button(action: onToggleExpanded) {
                HStack(spacing: 12) {
                    // 展开/折叠箭头
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    // 标签类型指示器
                    Circle()
                        .fill(Color.from(tagType: tagType))
                        .frame(width: 12, height: 12)
                    
                    // 标签类型名称和数量
                    Text(tagType.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("(\(tags.count))")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            .buttonStyle(.plain)
            
            // 标签列表（展开时显示）
            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tags.enumerated()), id: \.0) { index, tag in
                        TagValueRow(
                            tag: tag,
                            isSelected: store.selectedTag?.id == tag.id,
                            onSelect: { onSelectTag(tag) }
                        )

                        if index < tags.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.tertiaryLabelColor), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - 标签值行视图

struct TagValueRow: View {
    let tag: Tag
    let isSelected: Bool
    let onSelect: () -> Void
    @EnvironmentObject private var store: NodeStore
    
    private var nodeCount: Int {
        store.nodes(withTag: tag).count
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 缩进空间
                Spacer()
                    .frame(width: 32)
                
                // 选择状态指示
                Circle()
                    .fill(isSelected ? Color.blue : Color(NSColor.tertiaryLabelColor))
                    .frame(width: 8, height: 8)
                
                // 标签值
                Text(tag.value)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .blue : .primary)
                
                Spacer()
                
                // 节点数量
                Text("\(nodeCount)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
            .contentShape(Rectangle()) // 🎯 关键修复：让整个区域都可以点击
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签行视图

struct TagRowView: View {
    let tag: Tag
    let isHighlighted: Bool
    let onTap: () -> Void
    @EnvironmentObject private var store: NodeStore
    
    init(tag: Tag, isHighlighted: Bool = false, onTap: @escaping () -> Void) {
        self.tag = tag
        self.isHighlighted = isHighlighted
        self.onTap = onTap
    }
    
    private var wordsCount: Int {
        store.nodes(withTag: tag).count
    }
    
    var body: some View {
        let isCurrentlySelected = store.selectedTag?.id == tag.id
        let _ = print("🏷️ TagRowView: 渲染标签 value='\(tag.value)', type=\(tag.type), displayName='\(tag.type.displayName)', selected=\(isCurrentlySelected), highlighted=\(isHighlighted)")
        return Button(action: onTap) {
            HStack(spacing: 16) {
                // 标签类型指示器
                Circle()
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Text(tag.type.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if tag.hasCoordinates {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                // 单词数量
                VStack {
                    Text("\(wordsCount)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text("单词")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    // 只有在有标签且实际选中时才高亮
                    (isHighlighted && !store.currentLayerTags.isEmpty) ? Color.blue.opacity(0.2) : 
                    (isCurrentlySelected ? Color.blue.opacity(0.1) : Color.clear)
                )
        )
    }
}

// Preview temporarily disabled due to @FocusState initialization complexity
// #Preview {
//     NavigationSplitView {
//         TagSidebarView(selectedNode: .constant(nil))
//             .environmentObject(NodeStore.shared)
//     } content: {
//         Text("Content")
//     } detail: {
//         Text("Detail")
//     }
// }
}
