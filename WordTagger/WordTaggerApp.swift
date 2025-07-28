import SwiftUI
import MapKit
import CoreLocation

// MARK: - Quick Add Sheet View

struct QuickAddSheetView: View {
    @EnvironmentObject private var store: WordStore
    @Environment(\.presentationMode) var presentationMode
    @State private var inputText: String = ""
    @State private var suggestions: [String] = []
    @State private var selectedSuggestionIndex: Int = -1
    @FocusState private var isInputFocused: Bool
    @State private var isWaitingForLocationSelection = false
    
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
        VStack(spacing: 20) {
            contentView
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 400)
        .navigationTitle("快速添加单词")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("添加") {
                    processInput()
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            // 自动聚焦到输入框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
            
            // 监听位置选择通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("locationSelected"),
                object: nil,
                queue: .main
            ) { notification in
                if let locationName = notification.object as? String {
                    insertLocationIntoInput(locationName)
                }
            }
        }
        // TODO: 修复onKeyPress API调用
        // .onKeyPress(KeyEquivalent("p"), modifiers: .command) { _ in
        //     if isInputFocused {
        //         openMapForLocationSelection()
        //         return .handled
        //     }
        //     return .ignored
        // }
    }
    
    private var contentView: some View {
        VStack(spacing: 16) {
            Text("快速添加单词")
                .font(.title2)
                .fontWeight(.semibold)
            
            instructionView
            inputSection
        }
    }
    
    private var instructionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("输入格式")
                .font(.headline)
            Text("单词 标签1 内容1 标签2 内容2...")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("例如: rotate root rot memory 旋转 time 2018年")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputField
            if !suggestions.isEmpty {
                suggestionsView
            }
        }
    }
    
    private var inputField: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.blue)
                .font(.title2)
            TextField("输入单词和标签...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16, weight: .medium))
                .focused($isInputFocused)
                .onSubmit { processInput() }
                .onChange(of: inputText) { _, newValue in 
                    updateSuggestions(for: newValue) 
                }
            
            Button(action: openMapForLocationSelection) {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("选择地点位置 (⌘P)")
            .keyboardShortcut("p", modifiers: .command)
        }
    }
    
    private var suggestionsView: some View {
        VStack(spacing: 4) {
            Text("建议标签:")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    suggestionButton(suggestion, index: index)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func suggestionButton(_ suggestion: String, index: Int) -> some View {
        Button(action: { selectSuggestion(suggestion) }) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text(suggestion)
                    .font(.system(size: 14, weight: .medium))
                Text("(\(tagMappings[suggestion]?.0 ?? "自定义"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedSuggestionIndex == index ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func updateSuggestions(for input: String) {
        let words = input.split(separator: " ")
        guard let lastWord = words.last?.lowercased() else { 
            suggestions = []
            selectedSuggestionIndex = -1
            return 
        }
        
        let matchingSuggestions = tagMappings.keys.filter { key in 
            key.lowercased().hasPrefix(String(lastWord)) && key.lowercased() != String(lastWord) 
        }.sorted()
        
        suggestions = matchingSuggestions
        selectedSuggestionIndex = matchingSuggestions.isEmpty ? -1 : 0
    }
    
    private func selectSuggestion(_ suggestion: String) {
        let words = inputText.split(separator: " ").map(String.init)
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
        var i = 1
        
        while i < components.count {
            let tagKey = components[i].lowercased()
            if let (_, tagType) = tagMappings[tagKey] {
                if i + 1 < components.count { 
                    let content = components[i + 1]
                    let tag = Tag(type: tagType, value: content)
                    tags.append(tag)
                    i += 2 
                } else { 
                    i += 1 
                }
            } else { 
                i += 1 
            }
        }
        
        let newWord = Word(text: wordText, tags: tags)
        store.addWord(newWord)
        inputText = ""
        presentationMode.wrappedValue.dismiss()
    }
    
    private func openMapForLocationSelection() {
        print("📍 QuickAddSheetView: Opening map for location selection...")
        isWaitingForLocationSelection = true
        
        // 打开地图窗口
        print("📍 QuickAddSheetView: Posting openMapWindow notification")
        NotificationCenter.default.post(name: .openMapWindow, object: nil)
        
        // 设置为位置选择模式
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("📍 QuickAddSheetView: About to post openMapForLocationSelection notification")
            NotificationCenter.default.post(name: NSNotification.Name("openMapForLocationSelection"), object: nil)
            print("📍 QuickAddSheetView: Posted openMapForLocationSelection notification")
        }
    }
    
    private func insertLocationIntoInput(_ locationName: String) {
        print("Inserting location into input: \(locationName)")
        
        // 在当前光标位置插入 "loc 地点名称 "
        let locationText = "loc \(locationName) "
        inputText += locationText
        isWaitingForLocationSelection = false
        
        print("Input text updated to: \(inputText)")
        
        // 重新聚焦到输入框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInputFocused = true
        }
    }
}

// MARK: - Quick Add View

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
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title2)
                        TextField("输入: 单词 root 词根内容 memory 记忆内容...", text: $inputText)
                            .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                            .onSubmit { processInput() }
                            .onChange(of: inputText) { _, newValue in updateSuggestions(for: newValue) }
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }.background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8))
                
                if !suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                            HStack {
                                Image(systemName: "tag.fill").foregroundColor(.blue).font(.caption)
                                Text(suggestion).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(tagMappings[suggestion]?.0 ?? "自定义").font(.caption).foregroundColor(.secondary)
                            }.padding(.horizontal, 16).padding(.vertical, 8)
                            .background(selectedSuggestionIndex == index ? Color.blue.opacity(0.1) : Color.clear)
                            .onTapGesture { selectSuggestion(suggestion) }
                        }
                    }.background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)).padding(.top, 8)
                }
                
                HStack {
                    Text("💡 格式: 单词 标签1 内容1 标签2 内容2...").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+I").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 12)
            }.padding(20).frame(maxWidth: 600)
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }
    
    private func updateSuggestions(for input: String) {
        let words = input.split(separator: " ")
        guard let lastWord = words.last?.lowercased() else { suggestions = []; selectedSuggestionIndex = -1; return }
        let matchingSuggestions = tagMappings.keys.filter { key in key.lowercased().hasPrefix(String(lastWord)) && key.lowercased() != String(lastWord) }.sorted()
        suggestions = matchingSuggestions; selectedSuggestionIndex = matchingSuggestions.isEmpty ? -1 : 0
    }
    
    private func selectSuggestion(_ suggestion: String) {
        let words = inputText.split(separator: " ").map(String.init)
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
        let components = inputText.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return }
        let wordText = components[0]; var tags: [Tag] = []; var i = 1
        while i < components.count {
            let tagKey = components[i].lowercased()
            if let (_, tagType) = tagMappings[tagKey] {
                if i + 1 < components.count { let content = components[i + 1]; let tag = Tag(type: tagType, value: content); tags.append(tag); i += 2 }
                else { i += 1 }
            } else { i += 1 }
        }
        let newWord = Word(text: wordText, tags: tags); store.addWord(newWord); inputText = ""; onDismiss()
    }
}

// MARK: - Quick Search View

struct QuickSearchView: View {
    @EnvironmentObject private var store: WordStore
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    let onDismiss: () -> Void
    let onWordSelected: (Word) -> Void
    
    private var filteredWords: [Word] {
        if searchText.isEmpty { return Array(store.words.prefix(10)) }
        else { return store.words.filter { word in
            word.text.localizedCaseInsensitiveContains(searchText) ||
            word.meaning?.localizedCaseInsensitiveContains(searchText) == true ||
            word.tags.contains { tag in tag.value.localizedCaseInsensitiveContains(searchText) }
        }}
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.blue).font(.title2)
                    TextField("搜索单词、含义或标签...", text: $searchText)
                        .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                        .onSubmit { selectCurrentWord() }
                }.padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8))
                
                if !filteredWords.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredWords.enumerated()), id: \.element.id) { index, word in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(word.text).font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                                        Spacer()
                                        HStack(spacing: 4) {
                                            ForEach(word.tags.prefix(3), id: \.id) { tag in
                                                Text(tag.value).font(.caption)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.from(tagType: tag.type).opacity(0.2)))
                                                    .foregroundColor(Color.from(tagType: tag.type))
                                            }
                                            if word.tags.count > 3 { Text("+\(word.tags.count - 3)").font(.caption).foregroundColor(.secondary) }
                                        }
                                    }
                                    if let meaning = word.meaning, !meaning.isEmpty {
                                        Text(meaning).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 10)
                                .onTapGesture { onWordSelected(word); onDismiss() }
                                .background(index == selectedIndex ? Color.blue.opacity(0.1) : Color.clear)
                            }
                        }
                    }.background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .frame(maxHeight: 400).padding(.top, 8)
                }
                
                HStack {
                    Text("💡 输入关键词搜索单词").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("⌘+F").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 12)
            }.padding(20).frame(maxWidth: 600)
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onChange(of: filteredWords) { _, _ in selectedIndex = 0 }
    }
    
    private func selectCurrentWord() {
        guard selectedIndex < filteredWords.count else { return }
        let selectedWord = filteredWords[selectedIndex]; onWordSelected(selectedWord); onDismiss()
    }
}

// MARK: - Tag Manager View

struct TagManagerView: View {
    @State private var tagMappings: [TagMapping] = [
        TagMapping(key: "root", displayName: "词根", type: .root),
        TagMapping(key: "memory", displayName: "记忆", type: .memory),
        TagMapping(key: "loc", displayName: "地点", type: .location),
        TagMapping(key: "time", displayName: "时间", type: .custom),
        TagMapping(key: "shape", displayName: "形状", type: .shape),
        TagMapping(key: "sound", displayName: "声音", type: .sound)
    ]
    @State private var newKey: String = ""
    @State private var newDisplayName: String = ""
    @State private var newType: Tag.TagType = .custom
    @State private var editingMapping: TagMapping?
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 0) {
                HStack {
                    Text("标签管理").font(.title2).fontWeight(.semibold)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title2)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.vertical, 16).background(.ultraThinMaterial)
                
                Divider()
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tagMappings) { mapping in
                            HStack {
                                Circle().fill(Color.from(tagType: mapping.type)).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mapping.displayName).font(.system(size: 14, weight: .medium))
                                    Text(mapping.key).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(mapping.type.displayName).font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.from(tagType: mapping.type).opacity(0.2)))
                                    .foregroundColor(Color.from(tagType: mapping.type))
                                Button(action: { editingMapping = mapping; newKey = mapping.key; newDisplayName = mapping.displayName; newType = mapping.type }) {
                                    Image(systemName: "pencil").font(.caption).foregroundColor(.blue)
                                }.buttonStyle(.plain)
                                Button(action: { tagMappings.removeAll { $0.id == mapping.id } }) {
                                    Image(systemName: "trash").font(.caption).foregroundColor(.red)
                                }.buttonStyle(.plain)
                            }.padding(.horizontal, 20).padding(.vertical, 8)
                        }
                    }
                }.frame(maxHeight: 300)
                
                Divider()
                
                VStack(spacing: 12) {
                    Text(editingMapping != nil ? "编辑标签" : "添加新标签").font(.headline).foregroundColor(.primary)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("快捷键").font(.caption).foregroundColor(.secondary)
                            TextField("例如: root", text: $newKey).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("显示名称").font(.caption).foregroundColor(.secondary)
                            TextField("例如: 词根", text: $newDisplayName).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("类型").font(.caption).foregroundColor(.secondary)
                            Picker("类型", selection: $newType) {
                                ForEach(Tag.TagType.allCases, id: \.self) { type in Text(type.displayName).tag(type) }
                            }.pickerStyle(.menu)
                        }
                    }
                    HStack {
                        if editingMapping != nil {
                            Button("取消") { resetForm() }.buttonStyle(.bordered)
                        }
                        Button(editingMapping != nil ? "保存" : "添加") { saveMapping() }
                            .buttonStyle(.borderedProminent).disabled(newKey.isEmpty || newDisplayName.isEmpty)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 16).background(.ultraThinMaterial)
            }.background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 10)
            .frame(maxWidth: 700, maxHeight: 600).padding(20)
        }.onKeyPress(.escape) { onDismiss(); return .handled }
    }
    
    private func saveMapping() {
        if let editingMapping = editingMapping {
            if let index = tagMappings.firstIndex(where: { $0.id == editingMapping.id }) {
                tagMappings[index] = TagMapping(id: editingMapping.id, key: newKey.lowercased(), displayName: newDisplayName, type: newType)
            }
        } else {
            let newMapping = TagMapping(key: newKey.lowercased(), displayName: newDisplayName, type: newType)
            tagMappings.append(newMapping)
        }
        resetForm()
    }
    
    private func resetForm() { newKey = ""; newDisplayName = ""; newType = .custom; editingMapping = nil }
}

struct TagMapping: Identifiable, Codable {
    let id: UUID
    let key: String
    let displayName: String
    let type: Tag.TagType
    
    init(id: UUID = UUID(), key: String, displayName: String, type: Tag.TagType) {
        self.id = id
        self.key = key
        self.displayName = displayName
        self.type = type
    }
}

// MARK: - Geographic Data

struct GeographicData {
    static let commonLocations: [CommonLocation] = [
        CommonLocation(name: "北京", coordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)),
        CommonLocation(name: "上海", coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)),
        CommonLocation(name: "纽约", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)),
        CommonLocation(name: "伦敦", coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)),
        CommonLocation(name: "东京", coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)),
        CommonLocation(name: "故宫", coordinate: CLLocationCoordinate2D(latitude: 39.9163, longitude: 116.3972)),
        CommonLocation(name: "西湖", coordinate: CLLocationCoordinate2D(latitude: 30.2489, longitude: 120.1292)),
        CommonLocation(name: "埃菲尔铁塔", coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945)),
        CommonLocation(name: "清华大学", coordinate: CLLocationCoordinate2D(latitude: 40.0031, longitude: 116.3262)),
        CommonLocation(name: "哈佛大学", coordinate: CLLocationCoordinate2D(latitude: 42.3770, longitude: -71.1167))
    ]
    
    static func searchLocations(query: String) -> [CommonLocation] {
        guard !query.isEmpty else { return [] }
        return commonLocations.filter { location in location.name.localizedCaseInsensitiveContains(query) }
    }
    
    static func createMKMapItem(from location: CommonLocation) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: location.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = location.name
        return mapItem
    }
}

struct CommonLocation: Identifiable, Hashable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    
    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CommonLocation, rhs: CommonLocation) -> Bool { lhs.id == rhs.id }
}

@main
struct WordTaggerApp: App {
    @StateObject private var store = WordStore.shared
    @State private var showPalette = false
    @State private var showQuickAdd = false
    @State private var showQuickSearch = false
    @State private var showTagManager = false

    var body: some Scene {
        WindowGroup("单词标签管理器") {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .frame(minWidth: 800, minHeight: 600)
                
                if showPalette {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showPalette = false
                        }
                    
                    CommandPaletteView(isPresented: $showPalette)
                        .environmentObject(store)
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                }
                
                
                if showQuickSearch {
                    QuickSearchView(
                        onDismiss: { showQuickSearch = false },
                        onWordSelected: { word in
                            store.selectWord(word)
                        }
                    )
                    .environmentObject(store)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                }
                
                if showTagManager {
                    TagManagerView {
                        showTagManager = false
                    }
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showPalette)
            .animation(.easeInOut(duration: 0.2), value: showQuickSearch)
            .animation(.easeInOut(duration: 0.2), value: showTagManager)
            .sheet(isPresented: $showQuickAdd) {
                QuickAddSheetView()
                    .environmentObject(store)
            }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {}
            CommandMenu("单词标签") {
                Button("命令面板") { 
                    showPalette = true 
                }
                .keyboardShortcut("k", modifiers: [.command])
                
                Divider()
                
                Button("快速添加单词") {
                    showQuickAdd = true
                }
                .keyboardShortcut("i", modifiers: [.command])
                
                Button("快速搜索") {
                    showQuickSearch = true
                }
                .keyboardShortcut("f", modifiers: [.command])
                
                Button("标签管理") {
                    showTagManager = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Divider()
                
                Button("添加单词") {
                    // 触发添加单词对话框
                    NotificationCenter.default.post(name: Notification.Name("addNewWord"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                
                Divider()
                
                Button("打开地图") {
                    NotificationCenter.default.post(name: Notification.Name("openMapWindow"), object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command])
                
                Button("打开图谱") {
                    NotificationCenter.default.post(name: Notification.Name("openGraphWindow"), object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command])
            }
        }
        
        // 地图窗口
        WindowGroup("地图视图", id: "map") {
            MapWindow()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        
        // 图谱窗口
        WindowGroup("节点关系图谱", id: "graph") {
            GraphView()
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1200, height: 800)
        
        // 设置窗口
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}