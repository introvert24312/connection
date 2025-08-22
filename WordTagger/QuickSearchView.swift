import SwiftUI

struct QuickSearchView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFieldFocused: Bool
    let onDismiss: () -> Void
    let onNodeSelected: (Node) -> Void
    
    private var filteredNodes: [Node] {
        if searchText.isEmpty {
            return Array(store.nodes.prefix(10)) // 显示前10个
        } else {
            return store.nodes.filter { node in
                node.text.localizedCaseInsensitiveContains(searchText) ||
                node.meaning?.localizedCaseInsensitiveContains(searchText) == true ||
                node.tags.contains { tag in
                    tag.value.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 0) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    TextField("搜索单词、含义或标签...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            selectCurrentNode()
                        }
                        .onChange(of: isSearchFieldFocused) { _, newValue in
                            print("🔍 TextField焦点状态变化: \(newValue)")
                        }
                        .onAppear {
                            print("🔍 TextField出现")
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
                )
                
                // 搜索结果
                if !filteredNodes.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(filteredNodes.enumerated()), id: \.element.id) { index, word in
                                NodeSearchResultRow(
                                    word: word,
                                    searchText: searchText,
                                    isSelected: index == selectedIndex
                                )
                                .frame(maxWidth: .infinity)  // 填满可用宽度
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(index == selectedIndex ? 
                                              Color.blue.opacity(0.1) : Color.clear)
                                )
                                .padding(.horizontal, 4) // 给选项卡一些边距
                                .contentShape(Rectangle())  // 明确整个矩形区域可点击
                                .onTapGesture {
                                    print("🖱️ 点击了节点: \(word.text)")
                                    onNodeSelected(word)
                                    onDismiss()
                                }
                                .onAppear {
                                    print("🖱️ NodeSearchResultRow 出现: \(word.text)")
                                }
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
                    .frame(maxHeight: 400)
                    .padding(.top, 8)
                } else if !searchText.isEmpty {
                    VStack {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("没有找到匹配的结果")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(40)
                }
                
                // 帮助文本
                HStack {
                    Text("💡 输入关键词搜索单词")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+F")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: 600)
        }
        .task {
            print("🔍 QuickSearchView task: 异步任务开始")
            // 立即尝试聚焦
            await MainActor.run {
                isSearchFieldFocused = true
                print("🔍 QuickSearchView task: 立即设置焦点")
            }
            
            // 等待并重试
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            await MainActor.run {
                isSearchFieldFocused = true
                print("🔍 QuickSearchView task: 0.1秒后设置焦点")
            }
            
            try? await Task.sleep(nanoseconds: 200_000_000) // 再等0.2秒(总共0.3秒)
            await MainActor.run {
                isSearchFieldFocused = true
                print("🔍 QuickSearchView task: 0.3秒后设置焦点")
            }
        }
        .onAppear {
            print("🔍 QuickSearchView.onAppear: 视图出现")
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredNodes.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            selectCurrentNode()
            return .handled
        }
        .onChange(of: filteredNodes) { _, newNodes in
            selectedIndex = 0
        }
    }
    
    private func selectCurrentNode() {
        guard selectedIndex < filteredNodes.count else { return }
        let selectedNode = filteredNodes[selectedIndex]
        onNodeSelected(selectedNode)
        onDismiss()
    }
}

struct NodeSearchResultRow: View {
    let word: Node
    let searchText: String
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // 单词文本
                Text(highlightedText(word.text, searchText: searchText))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 标签
                HStack(spacing: 4) {
                    ForEach(word.tags.prefix(3), id: \.id) { tag in
                        Text(tag.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.from(tagType: tag.type).opacity(0.2))
                            )
                            .foregroundColor(Color.from(tagType: tag.type))
                    }
                    if word.tags.count > 3 {
                        Text("+\(word.tags.count - 3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 含义
            if let meaning = word.meaning, !meaning.isEmpty {
                Text(highlightedText(meaning, searchText: searchText))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)  // 确保填满可用宽度
        .contentShape(Rectangle())  // 明确定义点击区域为整个矩形
    }
    
    private func highlightedText(_ text: String, searchText: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        if !searchText.isEmpty {
            if let range = text.range(of: searchText, options: .caseInsensitive) {
                let nsRange = NSRange(range, in: text)
                if let attributedRange = Range(nsRange, in: attributedString) {
                    attributedString[attributedRange].backgroundColor = .yellow.opacity(0.3)
                    attributedString[attributedRange].foregroundColor = .primary
                }
            }
        }
        
        return attributedString
    }
}

#Preview {
    QuickSearchView(onDismiss: {}, onNodeSelected: { _ in })
        .environmentObject(NodeStore.shared)
}