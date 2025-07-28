import SwiftUI

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
            // 背景遮罩
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Text("标签管理")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                
                Divider()
                
                // 现有标签列表
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tagMappings) { mapping in
                            TagMappingRow(
                                mapping: mapping,
                                onEdit: {
                                    editingMapping = mapping
                                    newKey = mapping.key
                                    newDisplayName = mapping.displayName
                                    newType = mapping.type
                                },
                                onDelete: {
                                    tagMappings.removeAll { $0.id == mapping.id }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
                
                Divider()
                
                // 添加新标签
                VStack(spacing: 12) {
                    Text(editingMapping != nil ? "编辑标签" : "添加新标签")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("快捷键")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("例如: root", text: $newKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("显示名称")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("例如: 词根", text: $newDisplayName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("类型")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("类型", selection: $newType) {
                                ForEach(Tag.TagType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    
                    HStack {
                        if editingMapping != nil {
                            Button("取消") {
                                resetForm()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Button(editingMapping != nil ? "保存" : "添加") {
                            saveMapping()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newKey.isEmpty || newDisplayName.isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                
                // 帮助文本
                VStack(alignment: .leading, spacing: 4) {
                    Text("💡 使用方法:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("输入格式: 单词 快捷键 内容")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("例如: apple root 苹果 memory 红苹果")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .background(.ultraThinMaterial)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 10)
            .frame(maxWidth: 700, maxHeight: 600)
            .padding(20)
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }
    
    private func saveMapping() {
        if let editingMapping = editingMapping {
            // 编辑现有标签
            if let index = tagMappings.firstIndex(where: { $0.id == editingMapping.id }) {
                tagMappings[index] = TagMapping(
                    id: editingMapping.id,
                    key: newKey.lowercased(),
                    displayName: newDisplayName,
                    type: newType
                )
            }
        } else {
            // 添加新标签
            let newMapping = TagMapping(
                key: newKey.lowercased(),
                displayName: newDisplayName,
                type: newType
            )
            tagMappings.append(newMapping)
        }
        
        saveToUserDefaults()
        resetForm()
    }
    
    private func resetForm() {
        newKey = ""
        newDisplayName = ""
        newType = .custom
        editingMapping = nil
    }
    
    private func saveToUserDefaults() {
        // 保存到UserDefaults
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(tagMappings) {
            UserDefaults.standard.set(data, forKey: "tagMappings")
        }
    }
    
    private func loadFromUserDefaults() {
        // 从UserDefaults加载
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "tagMappings"),
           let savedMappings = try? decoder.decode([TagMapping].self, from: data) {
            tagMappings = savedMappings
        }
    }
}

struct TagMappingRow: View {
    let mapping: TagMapping
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            // 标签颜色指示器
            Circle()
                .fill(Color.from(tagType: mapping.type))
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text(mapping.key)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(mapping.type.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.from(tagType: mapping.type).opacity(0.2))
                )
                .foregroundColor(Color.from(tagType: mapping.type))
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.clear)
        .hoverEffect(.highlight)
    }
}

struct TagMapping: Identifiable, Codable {
    let id = UUID()
    let key: String
    let displayName: String
    let type: Tag.TagType
    
    init(id: UUID = UUID(), key: String, displayName: String, type: Tag.TagType) {
        self.key = key
        self.displayName = displayName
        self.type = type
    }
}

#Preview {
    TagManagerView(onDismiss: {})
}