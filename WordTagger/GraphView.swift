import SwiftUI

struct GraphView: View {
    @EnvironmentObject private var store: WordStore
    @State private var searchQuery: String = ""
    @State private var displayedWords: [Word] = []
    
    // 生成所有单词的图谱数据
    private var allGraphNodes: [WordGraphNode] {
        var nodes: [WordGraphNode] = []
        
        let wordsToShow = displayedWords.isEmpty ? store.words : displayedWords
        
        for word in wordsToShow {
            nodes.append(WordGraphNode(word: word))
        }
        
        return nodes
    }
    
    private var allGraphEdges: [WordGraphEdge] {
        var edges: [WordGraphEdge] = []
        let nodes = allGraphNodes
        
        // 为有共同标签的单词创建连接
        for i in 0..<nodes.count {
            for j in (i+1)..<nodes.count {
                guard let word1 = nodes[i].word,
                      let word2 = nodes[j].word else { continue }
                
                let tags1 = Set(word1.tags)
                let tags2 = Set(word2.tags)
                let commonTags = tags1.intersection(tags2)
                
                if !commonTags.isEmpty {
                    let relationshipType = commonTags.first!.type.displayName
                    edges.append(WordGraphEdge(
                        from: nodes[i],
                        to: nodes[j],
                        relationshipType: relationshipType
                    ))
                }
            }
        }
        
        return edges
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
            if allGraphNodes.isEmpty {
                EmptyGraphView()
            } else {
                UniversalRelationshipGraphView(
                    nodes: allGraphNodes,
                    edges: allGraphEdges,
                    title: "节点关系图谱",
                    onNodeSelected: { nodeId in
                        // 当点击节点时，选择对应的单词（只有单词节点才会触发选择）
                        if let selectedNode = allGraphNodes.first(where: { $0.id == nodeId }),
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