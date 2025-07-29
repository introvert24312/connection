import SwiftUI

struct GraphView: View {
    @EnvironmentObject private var store: WordStore
    @State private var searchQuery: String = ""
    @State private var displayedWords: [Word] = []
    @State private var cachedNodes: [WordGraphNode] = []
    @State private var cachedEdges: [WordGraphEdge] = []
    
    // 生成所有单词的图谱数据 - 统一计算节点和边
    private func calculateGraphData() -> (nodes: [WordGraphNode], edges: [WordGraphEdge]) {
        var nodes: [WordGraphNode] = []
        var edges: [WordGraphEdge] = []
        var addedTagKeys: Set<String> = []
        
        let wordsToShow = displayedWords.isEmpty ? store.words : displayedWords
        
        // 首先添加所有单词节点
        for word in wordsToShow {
            nodes.append(WordGraphNode(word: word))
        }
        
        // 然后添加所有标签节点（去重）
        for word in wordsToShow {
            for tag in word.tags {
                let tagKey = "\(tag.type.rawValue):\(tag.value)"
                if !addedTagKeys.contains(tagKey) {
                    nodes.append(WordGraphNode(tag: tag))
                    addedTagKeys.insert(tagKey)
                }
            }
        }
        
        // 现在使用同一批节点创建边
        
        print("🔍 调试信息:")
        print("🔹 总节点数: \(nodes.count)")
        print("🔹 单词数: \(wordsToShow.count)")
        print("🔹 单词节点数: \(nodes.filter { $0.word != nil }.count)")
        print("🔹 标签节点数: \(nodes.filter { $0.tag != nil }.count)")
        
        // 为每个单词与其标签创建连接
        for word in wordsToShow {
            guard let wordNode = nodes.first(where: { $0.word?.id == word.id }) else { 
                print("❌ 找不到单词节点: \(word.text)")
                continue 
            }
            
            print("🔹 处理单词: \(word.text), 标签数: \(word.tags.count)")
            
            for tag in word.tags {
                if let tagNode = nodes.first(where: { 
                    $0.tag?.type.rawValue == tag.type.rawValue && $0.tag?.value == tag.value 
                }) {
                    edges.append(WordGraphEdge(
                        from: wordNode,
                        to: tagNode,
                        relationshipType: tag.type.displayName
                    ))
                    print("✅ 创建连接: \(word.text) -> \(tag.value)")
                } else {
                    print("❌ 找不到标签节点: \(tag.type.rawValue):\(tag.value)")
                }
            }
        }
        
        print("🔹 单词-标签连接数: \(edges.count)")
        
        // 额外连接：为有相同标签的单词创建连接
        let initialEdgeCount = edges.count
        for i in 0..<nodes.count {
            for j in (i+1)..<nodes.count {
                guard let word1 = nodes[i].word,
                      let word2 = nodes[j].word else { continue }
                
                let tags1 = Set(word1.tags.map { "\($0.type.rawValue):\($0.value)" })
                let tags2 = Set(word2.tags.map { "\($0.type.rawValue):\($0.value)" })
                let commonTags = tags1.intersection(tags2)
                
                if !commonTags.isEmpty {
                    edges.append(WordGraphEdge(
                        from: nodes[i],
                        to: nodes[j], 
                        relationshipType: "关联"
                    ))
                    print("✅ 创建单词关联: \(word1.text) <-> \(word2.text)")
                }
            }
        }
        
        print("🔹 单词间连接数: \(edges.count - initialEdgeCount)")
        print("🔹 总连接数: \(edges.count)")
        
        return (nodes: nodes, edges: edges)
    }
    
    // 更新缓存的图数据
    private func updateGraphData() {
        let data = calculateGraphData()
        cachedNodes = data.nodes
        cachedEdges = data.edges
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("节点关系图谱")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 搜索框
                TextField("搜索单词或标签...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        performSearch()
                    }
                
                // 搜索按钮
                Button("搜索") {
                    performSearch()
                }
                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                // 重置按钮
                if !displayedWords.isEmpty {
                    Button("显示全部") {
                        displayedWords = []
                        searchQuery = ""
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 图谱内容
            if cachedNodes.isEmpty {
                EmptyGraphView()
            } else {
                UniversalRelationshipGraphView(
                    nodes: cachedNodes,
                    edges: cachedEdges,
                    title: "节点关系图谱",
                    onNodeSelected: { nodeId in
                        // 当点击节点时，选择对应的单词（只有单词节点才会触发选择）
                        if let selectedNode = cachedNodes.first(where: { $0.id == nodeId }),
                           let selectedWord = selectedNode.word {
                            store.selectWord(selectedWord)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onKeyPress(.init("k"), phases: .down) { _ in
            NotificationCenter.default.post(name: Notification.Name("fitGraph"), object: nil)
            return .handled
        }
        .onAppear {
            // 初始显示所有单词
            if displayedWords.isEmpty && !store.words.isEmpty {
                displayedWords = Array(store.words.prefix(20)) // 限制初始显示数量
            }
            updateGraphData()
        }
        .onChange(of: store.words) { _ in
            updateGraphData()
        }
        .onChange(of: displayedWords) { _ in
            updateGraphData()
        }
    }
    
    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedWords = []
            return
        }
        
        // 搜索匹配的单词
        let matchedWords = store.words.filter { word in
            word.text.localizedCaseInsensitiveContains(query) ||
            word.meaning?.localizedCaseInsensitiveContains(query) == true ||
            word.tags.contains { tag in
                tag.value.localizedCaseInsensitiveContains(query)
            }
        }
        
        // 获取相关单词（有共同标签的）
        var relatedWords = Set<Word>()
        for matchedWord in matchedWords {
            let wordTags = Set(matchedWord.tags)
            let related = store.words.filter { otherWord in
                otherWord.id != matchedWord.id && !Set(otherWord.tags).isDisjoint(with: wordTags)
            }
            relatedWords.formUnion(related)
        }
        
        // 组合结果
        var finalWords = Set(matchedWords)
        finalWords.formUnion(relatedWords)
        
        displayedWords = Array(finalWords).sorted { $0.text < $1.text }
    }
}

// MARK: - Empty Graph View

struct EmptyGraphView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.hexagonpath")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("暂无图谱数据")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("添加一些单词来生成关系图谱")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    GraphView()
        .environmentObject(WordStore.shared)
}