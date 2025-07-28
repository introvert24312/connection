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
        case related = "关联"
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
                    RelatedWordsView(word: word)
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
    
    private var groupedTags: [Tag.TagType: [Tag]] {
        Dictionary(grouping: tags, by: { $0.type })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Tag.TagType.allCases, id: \.self) { type in
                if let tagsOfType = groupedTags[type], !tagsOfType.isEmpty {
                    TagTypeSection(type: type, tags: tagsOfType)
                }
            }
        }
    }
}

struct TagTypeSection: View {
    let type: Tag.TagType
    let tags: [Tag]
    
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
                ForEach(tags, id: \.id) { tag in
                    DetailTagCard(tag: tag)
                }
            }
        }
    }
}

struct DetailTagCard: View {
    let tag: Tag
    
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
                .fill(Color.from(tagType: tag.type).opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.from(tagType: tag.type).opacity(0.3), lineWidth: 1)
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

// MARK: - 关联单词视图

struct RelatedWordsView: View {
    let word: Word
    @EnvironmentObject private var store: WordStore
    
    private var relatedWords: [Word] {
        // 找到具有相同标签的其他单词
        let wordTags = Set(word.tags)
        return store.words.filter { otherWord in
            otherWord.id != word.id && !Set(otherWord.tags).isDisjoint(with: wordTags)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("相关单词")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(relatedWords.count) 个")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if relatedWords.isEmpty {
                    EmptyRelatedWordsView()
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200), spacing: 16)
                    ], spacing: 16) {
                        ForEach(relatedWords, id: \.id) { relatedWord in
                            RelatedWordCard(word: relatedWord, originalWord: word)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct RelatedWordCard: View {
    let word: Word
    let originalWord: Word
    @EnvironmentObject private var store: WordStore
    
    private var commonTags: [Tag] {
        let originalTags = Set(originalWord.tags)
        return word.tags.filter { originalTags.contains($0) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.text)
                    .font(.headline)
                
                if let meaning = word.meaning {
                    Text(meaning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            if !commonTags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("共同标签")
                        .font(.caption2)
                        .foregroundColor(Color.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 60), spacing: 4)
                    ], spacing: 4) {
                        ForEach(commonTags.prefix(3), id: \.id) { tag in
                            TagChip(tag: tag, searchQuery: "")
                        }
                        
                        if commonTags.count > 3 {
                            Text("+\(commonTags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
        .onTapGesture {
            store.selectWord(word)
        }
    }
}

struct EmptyRelatedWordsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "link")
                .font(.largeTitle)
                .foregroundColor(.gray)
            
            Text("暂无相关单词")
                .font(.body)
                .foregroundColor(.secondary)
            
            Text("当其他单词具有相同的标签时，它们会在这里显示")
                .font(.caption)
                .foregroundColor(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
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