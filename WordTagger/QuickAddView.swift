import SwiftUI

struct QuickAddView: View {
    @EnvironmentObject private var store: WordStore
    @State private var inputText: String = ""
    @State private var suggestions: [String] = []
    @State private var selectedSuggestionIndex: Int = -1
    let onDismiss: () -> Void
    
    // 预设标签映射
    private let tagMappings: [String: (String, Tag.TagType)] = [
        "root": ("词根", .root),
        "memory": ("记忆", .memory),
        "loc": ("地点", .location),
        "time": ("时间", .custom),
        "shape": ("形状", .shape),
        "sound": ("声音", .sound)
    ]
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 0) {
                // 主输入框
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        TextField("输入: 单词 root 词根内容 memory 记忆内容...", text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium))
                            .onSubmit {
                                processInput()
                            }
                            .onChange(of: inputText) { _, newValue in
                                updateSuggestions(for: newValue)
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
                )
                
                // 建议列表
                if !suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                
                                Text(suggestion)
                                    .font(.system(size: 14, weight: .medium))
                                
                                Spacer()
                                
                                Text(tagMappings[suggestion]?.0 ?? "自定义")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedSuggestionIndex == index ? 
                                Color.blue.opacity(0.1) : Color.clear
                            )
                            .onTapGesture {
                                selectSuggestion(suggestion)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.top, 8)
                }
                
                // 帮助文本
                HStack {
                    Text("💡 格式: 单词 标签1 内容1 标签2 内容2...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+I")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: 600)
        }
        .onAppear {
            // 自动聚焦输入框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // 这里可以设置焦点，但SwiftUI在macOS上需要特殊处理
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedSuggestionIndex > 0 {
                selectedSuggestionIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedSuggestionIndex < suggestions.count - 1 {
                selectedSuggestionIndex += 1
            }
            return .handled
        }
        .onKeyPress(.tab) {
            if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
                selectSuggestion(suggestions[selectedSuggestionIndex])
            }
            return .handled
        }
    }
    
    private func updateSuggestions(for input: String) {
        let words = input.split(separator: " ")
        guard let lastWord = words.last?.lowercased() else {
            suggestions = []
            selectedSuggestionIndex = -1
            return
        }
        
        // 只在最后一个词是部分标签时显示建议
        let matchingSuggestions = tagMappings.keys.filter { key in
            key.lowercased().hasPrefix(String(lastWord)) && key.lowercased() != String(lastWord)
        }.sorted()
        
        suggestions = matchingSuggestions
        selectedSuggestionIndex = matchingSuggestions.isEmpty ? -1 : 0
    }
    
    private func selectSuggestion(_ suggestion: String) {
        let words = inputText.split(separator: " ")
        if !words.isEmpty {
            let newWords = words.dropLast() + [suggestion]
            inputText = newWords.joined(separator: " ") + " "
        } else {
            inputText = suggestion + " "
        }
        suggestions = []
        selectedSuggestionIndex = -1
    }
    
    private func processInput() {
        let components = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        
        guard !components.isEmpty else { return }
        
        let wordText = components[0]
        var tags: [Tag] = []
        
        // 解析标签
        var i = 1
        while i < components.count {
            let tagKey = components[i].lowercased()
            
            if let (displayName, tagType) = tagMappings[tagKey] {
                // 找到下一个内容
                if i + 1 < components.count {
                    let content = components[i + 1]
                    let tag = Tag(type: tagType, value: content)
                    tags.append(tag)
                    i += 2
                } else {
                    // 只有标签没有内容，跳过
                    i += 1
                }
            } else {
                // 不是预设标签，跳过
                i += 1
            }
        }
        
        // 创建单词
        let newWord = Word(text: wordText, tags: tags)
        store.addWord(newWord)
        
        // 清空输入并关闭
        inputText = ""
        onDismiss()
    }
}

#Preview {
    QuickAddView(onDismiss: {})
        .environmentObject(WordStore.shared)
}