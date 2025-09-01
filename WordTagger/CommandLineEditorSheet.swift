import SwiftUI

struct CommandLineEditorSheet: View {
    @Binding var node: Node
    let onSave: (Node) -> Void
    let onCancel: () -> Void
    
    @State private var commandLineText: String = ""
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isSaving: Bool = false
    @State private var hasUnsavedChanges: Bool = false
    @State private var includeDisplayNames: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("编辑节点命令")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("取消") {
                        handleCancel()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Button("保存") {
                        handleSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!isFormValid || isSaving)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 说明文档
                    GroupBox("命令格式说明") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("命令格式：节点名 标签类型1 标签值1 标签类型2 标签值2 ...")
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("示例：")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("依赖 a 餐厅A a 肉店B")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                                
                                Text("解释：创建名为"依赖"的节点，包含两个类型为"a"的标签："餐厅A"和"肉店B"")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("注意事项：")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("• 节点名和标签值不能包含空格，如需空格请使用下划线")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("• 标签类型和标签值必须成对出现")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("• 保存后会自动更新节点和所有相关标签")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                    }
                    
                    // 命令输入区域
                    GroupBox("命令编辑") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("当前命令：")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Toggle("包含展示名", isOn: $includeDisplayNames)
                                    .font(.caption)
                                    .onChange(of: includeDisplayNames) { _, _ in
                                        updateCommandText()
                                    }
                            }
                            
                            TextField("输入命令...", text: $commandLineText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(3...10)
                                .onChange(of: commandLineText) {
                                    hasUnsavedChanges = commandLineText != node.commandRepresentationWithDisplayNames
                                }
                            
                            if !commandLineText.isEmpty {
                                Text("预览解析结果：")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                if let previewNode = Node.fromCommandLine(commandLineText, layerId: node.layerId) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("节点名：")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(previewNode.text)
                                                .font(.body)
                                                .fontWeight(.medium)
                                        }
                                        
                                        if !previewNode.tags.isEmpty {
                                            Text("标签：")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            LazyVGrid(columns: [
                                                GridItem(.flexible()),
                                                GridItem(.flexible())
                                            ], spacing: 8) {
                                                ForEach(previewNode.tags, id: \.id) { tag in
                                                    HStack {
                                                        Text(tag.type.rawValue)
                                                            .font(.caption)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.blue.opacity(0.2))
                                                            .cornerRadius(4)
                                                        
                                                        Text(tag.value)
                                                            .font(.caption)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.green.opacity(0.2))
                                                            .cornerRadius(4)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(8)
                                } else {
                                    Text("命令格式错误，请检查输入")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(8)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(12)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            loadNodeCommand()
        }
        .alert("错误", isPresented: $showingError) {
            Button("确定") {
                showingError = false
            }
        } message: {
            Text(errorMessage)
        }
        .overlay(
            Group {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("保存中...")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(radius: 8)
                        )
                    }
                }
            }
        )
    }
    
    // MARK: - Computed Properties
    
    private var isFormValid: Bool {
        !commandLineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Node.fromCommandLine(commandLineText, layerId: node.layerId) != nil
    }
    
    // MARK: - Methods
    
    private func loadNodeCommand() {
        updateCommandText()
        hasUnsavedChanges = false
    }
    
    private func updateCommandText() {
        // 始终使用带显示名的表示，确保方括号内容不丢失
        commandLineText = node.commandRepresentationWithDisplayNames
    }
    
    private func handleSave() {
        guard isFormValid else {
            showError("命令格式错误，请检查输入")
            return
        }
        
        guard !isSaving else { return }
        
        isSaving = true
        
        // 更新节点
        var updatedNode = node
        updatedNode.updateFromCommandLine(commandLineText)
        
        // 模拟保存延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.onSave(updatedNode)
            self.hasUnsavedChanges = false
            self.isSaving = false
            self.dismiss()
        }
    }
    
    private func handleCancel() {
        if hasUnsavedChanges {
            showUnsavedChangesDialog()
        } else {
            onCancel()
            dismiss()
        }
    }
    
    private func showUnsavedChangesDialog() {
        let alert = NSAlert()
        alert.messageText = "未保存的更改"
        alert.informativeText = "您有未保存的更改。是否要在关闭前保存？"
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn: // 保存
            handleSave()
        case .alertSecondButtonReturn: // 不保存
            onCancel()
            dismiss()
        case .alertThirdButtonReturn: // 取消
            break // 什么都不做，保持在编辑器中
        default:
            break
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

#Preview {
    @Previewable @State var sampleNode = Node(
        text: "依赖",
        layerId: UUID(),
        tags: [
            Tag(type: .custom("a"), value: "餐厅A"),
            Tag(type: .custom("a"), value: "肉店B")
        ]
    )
    
    CommandLineEditorSheet(
        node: $sampleNode,
        onSave: { node in
            print("保存节点: \(node.commandRepresentationWithDisplayNames)")
        },
        onCancel: {
            print("取消编辑")
        }
    )
}