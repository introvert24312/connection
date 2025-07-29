import SwiftUI
import CoreLocation
import MapKit
import MapKit

struct DetailPanel: View {
    let word: Word
    @State private var tab: Tab = .detail
    @State private var showingEditSheet = false
    
    enum Tab: String, CaseIterable {
        case detail = "详情"
        case map = "地图"
        case related = "图谱"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标签栏
            HStack {
                Picker("视图", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                
                Spacer()
                
                Button(action: { showingEditSheet = true }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("编辑单词")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 内容区域
            Group {
                switch tab {
                case .detail:
                    WordDetailView(word: word)
                case .map:
                    WordMapView(word: word)
                case .related:
                    WordGraphView(word: word)
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditWordSheet(word: word)
        }
    }
}

// MARK: - 单词详情视图

struct WordDetailView: View {
    let word: Word
    @EnvironmentObject private var store: WordStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 单词信息
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(word.text)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        if let phonetic = word.phonetic {
                            Text(phonetic)
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                    
                    if let meaning = word.meaning {
                        Text(meaning)
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
                
                Divider()
                
                // 标签部分
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("标签")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(word.tags.count) 个标签")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if word.tags.isEmpty {
                        EmptyTagsView()
                    } else {
                        TagsByTypeView(tags: word.tags)
                    }
                }
                
                // 移除了无效的元数据信息（创建时间、更新时间、单词ID）
            }
            .padding(24)
        }
    }
}

// MARK: - 按类型分组的标签视图

struct TagsByTypeView: View {
    let tags: [Tag]
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    
    private var groupedTags: [Tag.TagType: [Tag]] {
        Dictionary(grouping: tags, by: { $0.type })
    }
    
    private var flattenedTags: [Tag] {
        var result: [Tag] = []
        for type in Tag.TagType.allCases {
            if let tagsOfType = groupedTags[type], !tagsOfType.isEmpty {
                result.append(contentsOf: tagsOfType)
            }
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Tag.TagType.allCases, id: \.self) { type in
                if let tagsOfType = groupedTags[type], !tagsOfType.isEmpty {
                    TagTypeSection(
                        type: type, 
                        tags: tagsOfType,
                        selectedIndex: $selectedIndex,
                        flattenedTags: flattenedTags
                    )
                }
            }
        }
        .focused($isFocused)
        .onKeyPress(.upArrow) {
            navigateVertically(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateVertically(direction: 1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            navigateHorizontally(direction: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateHorizontally(direction: 1)
            return .handled
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private func navigateVertically(direction: Int) {
        let newIndex = selectedIndex + direction
        if newIndex >= 0 && newIndex < flattenedTags.count {
            selectedIndex = newIndex
        }
    }
    
    private func navigateHorizontally(direction: Int) {
        let newIndex = selectedIndex + direction * 2 // 每行假设有2个元素
        if newIndex >= 0 && newIndex < flattenedTags.count {
            selectedIndex = newIndex
        }
    }
}

struct TagTypeSection: View {
    let type: Tag.TagType
    let tags: [Tag]
    @Binding var selectedIndex: Int
    let flattenedTags: [Tag]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.from(tagType: type))
                    .frame(width: 12, height: 12)
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(tags.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120), spacing: 8)
            ], spacing: 8) {
                ForEach(Array(tags.enumerated()), id: \.offset) { localIndex, tag in
                    let globalIndex = flattenedTags.firstIndex(where: { $0.id == tag.id }) ?? 0
                    DetailTagCard(
                        tag: tag,
                        isHighlighted: globalIndex == selectedIndex
                    )
                }
            }
        }
    }
}

struct DetailTagCard: View {
    let tag: Tag
    let isHighlighted: Bool
    
    init(tag: Tag, isHighlighted: Bool = false) {
        self.tag = tag
        self.isHighlighted = isHighlighted
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.from(tagType: tag.type))
                    .frame(width: 8, height: 8)
                
                Spacer()
                
                if tag.hasCoordinates {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Text(tag.value)
                .font(.body)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            
            if tag.hasCoordinates, let lat = tag.latitude, let lon = tag.longitude {
                Text("\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.from(tagType: tag.type).opacity(isHighlighted ? 0.3 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            Color.from(tagType: tag.type).opacity(isHighlighted ? 0.8 : 0.3), 
                            lineWidth: isHighlighted ? 2 : 1
                        )
                )
        )
    }
}

// MARK: - 空标签状态

struct EmptyTagsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag.slash")
                .font(.largeTitle)
                .foregroundColor(.gray)
            
            Text("暂无标签")
                .font(.body)
                .foregroundColor(.secondary)
            
            Text("为这个单词添加标签来更好地组织和记忆")
                .font(.caption)
                .foregroundColor(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// MARK: - 元数据行

struct MetadataRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - 地图视图

struct WordMapView: View {
    let word: Word
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    
    private var locationTags: [Tag] {
        word.locationTags
    }
    
    var body: some View {
        Group {
            if locationTags.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("该单词暂无地点标签")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text("添加地点标签来在地图上显示相关位置")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(position: $cameraPosition) {
                    ForEach(locationTags, id: \.id) { tag in
                        Annotation(
                            tag.value,
                            coordinate: CLLocationCoordinate2D(
                                latitude: tag.latitude!,
                                longitude: tag.longitude!
                            ),
                            anchor: .center
                        ) {
                            MapPinView(tag: tag)
                        }
                    }
                }
                .mapStyle(.standard)
                .onAppear {
                    if let firstTag = locationTags.first {
                        let newRegion = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(
                                latitude: firstTag.latitude!,
                                longitude: firstTag.longitude!
                            ),
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                        region = newRegion
                        cameraPosition = .region(newRegion)
                    }
                }
            }
        }
    }
}

struct MapPinView: View {
    let tag: Tag
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 24, height: 24)
                
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            
            Text(tag.value)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.9))
                        .shadow(radius: 2)
                )
        }
    }
}

// MARK: - 单词图谱节点数据模型

struct WordGraphNode: UniversalGraphNode {
    let id: Int
    let label: String
    let subtitle: String?
    let word: Word?
    let tag: Tag?
    let nodeType: NodeType
    let isCenter: Bool
    
    enum NodeType {
        case word
        case tag(Tag.TagType)
    }
    
    init(word: Word, isCenter: Bool = false) {
        // 使用word的UUID字符串的前8位加随机数确保唯一性
        let wordPrefix = String(word.id.uuidString.prefix(8))
        self.id = abs((wordPrefix + "_word").hashValue) % 2147483647
        self.label = word.text
        self.subtitle = word.meaning
        self.word = word
        self.tag = nil
        self.nodeType = .word
        self.isCenter = isCenter
    }
    
    init(tag: Tag) {
        // 为标签生成唯一ID，使用标签ID加随机后缀
        let tagPrefix = String(tag.id.uuidString.prefix(8))
        let tagString = "\(tagPrefix)_tag_\(tag.type.rawValue)_\(tag.value.prefix(5))"
        self.id = abs(tagString.hashValue) % 2147483647
        self.label = tag.value
        self.subtitle = tag.type.displayName
        self.word = nil
        self.tag = tag
        self.nodeType = .tag(tag.type)
        self.isCenter = false
    }
}

struct WordGraphEdge: UniversalGraphEdge {
    let fromId: Int
    let toId: Int
    let label: String?
    
    init(from: WordGraphNode, to: WordGraphNode, relationshipType: String) {
        self.fromId = from.id
        self.toId = to.id
        self.label = relationshipType
    }
}

// MARK: - 单词关系图谱视图

struct WordGraphView: View {
    let word: Word
    @EnvironmentObject private var store: WordStore
    
    private var relatedWords: [Word] {
        // 返回空数组，因为我们要显示标签关系而不是单词关系
        return []
    }
    
    private var graphNodes: [WordGraphNode] {
        var nodes: [WordGraphNode] = []
        
        // 添加中心节点（当前单词）
        nodes.append(WordGraphNode(word: word, isCenter: true))
        
        // 添加当前单词的所有标签作为节点
        for tag in word.tags {
            nodes.append(WordGraphNode(tag: tag))
        }
        
        // 添加位置标签作为节点
        for locationTag in word.locationTags {
            nodes.append(WordGraphNode(tag: locationTag))
        }
        
        // 调试信息（可选：在release版本中移除）
        #if DEBUG
        print("🔍 Word: \(word.text), Tags: \(word.tags.count), Graph nodes: \(nodes.count)")
        #endif
        
        return nodes
    }
    
    private var graphEdges: [WordGraphEdge] {
        var edges: [WordGraphEdge] = []
        let centerNode = graphNodes.first { $0.isCenter }!
        
        // 为每个标签节点创建与中心单词的连接
        for node in graphNodes where !node.isCenter {
            if let tag = node.tag {
                edges.append(WordGraphEdge(
                    from: centerNode,
                    to: node,
                    relationshipType: tag.type.displayName
                ))
            }
        }
        
        return edges
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("关系图谱")
                    .font(.headline)
                
                Spacer()
                
                Text("\(graphNodes.count) 个节点")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 图谱内容
            if graphNodes.count <= 1 {
                EmptyGraphView()
            } else {
                UniversalRelationshipGraphView(
                    nodes: graphNodes,
                    edges: graphEdges,
                    title: "单词关系图谱",
                    onNodeSelected: { nodeId in
                        // 当点击节点时，选择对应的单词（只有单词节点才会触发选择）
                        if let selectedNode = graphNodes.first(where: { $0.id == nodeId }),
                           let selectedWord = selectedNode.word {
                            store.selectWord(selectedWord)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - 编辑单词表单

struct EditWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WordStore
    
    let word: Word
    @State private var text: String
    @State private var phonetic: String
    @State private var meaning: String
    
    init(word: Word) {
        self.word = word
        self._text = State(initialValue: word.text)
        self._phonetic = State(initialValue: word.phonetic ?? "")
        self._meaning = State(initialValue: word.meaning ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("单词信息") {
                    TextField("单词", text: $text)
                    TextField("音标（可选）", text: $phonetic)
                    TextField("含义（可选）", text: $meaning, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("编辑单词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.updateWord(
                            word.id,
                            text: text.isEmpty ? nil : text,
                            phonetic: phonetic.isEmpty ? nil : phonetic,
                            meaning: meaning.isEmpty ? nil : meaning
                        )
                        dismiss()
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}

#Preview {
    let sampleWord = Word(
        text: "example",
        phonetic: "/ɪɡˈzæmpəl/",
        meaning: "例子，示例"
    )
    
    return DetailPanel(word: sampleWord)
        .environmentObject(WordStore.shared)
}