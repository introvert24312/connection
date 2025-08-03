import SwiftUI
import CoreLocation
import MapKit

struct CommandPaletteView: View {
    @EnvironmentObject private var store: WordStore
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @StateObject private var commandParser = CommandParser.shared
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索输入框
            HStack {
                Image(systemName: "command")
                    .foregroundColor(.blue)
                
                TextField("输入层名称 (⌘+R创建新层)...", text: $query, onCommit: executeSelectedCommand)
                    .font(.title2)
                    .focused($isTextFieldFocused)
                    .onKeyPress(.upArrow) {
                        selectedIndex = max(0, selectedIndex - 1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        selectedIndex = min(availableCommands.count - 1, selectedIndex + 1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        isPresented = false
                        return .handled
                    }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 命令列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(availableCommands.enumerated()), id: \.offset) { index, command in
                        NewCommandRowView(
                            command: command,
                            isSelected: index == selectedIndex
                        ) {
                            executeCommand(command)
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: 300)
            
            if availableCommands.isEmpty && !query.isEmpty {
                VStack {
                    Text("未找到匹配的命令")
                        .foregroundColor(.secondary)
                        .padding()
                }
                .frame(height: 100)
            }
        }
        .frame(width: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .padding()
        .onAppear {
            // 重置状态
            query = ""
            selectedIndex = 0
            updateAvailableCommands()
            
            // 立即聚焦到输入框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: query) { _, newQuery in
            updateAvailableCommands()
            selectedIndex = 0
        }
        .background(
            Button("") {
                createNewLayer()
    
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
        )
    }
    
    @State private var availableCommands: [Command] = []
    
    @MainActor
    private func updateAvailableCommands() {
        let context = CommandContext(
            store: store,
            currentWord: store.selectedWord,
            selectedTag: store.selectedTag
        )
        
        Task {
            availableCommands = await commandParser.parse(query, context: context)
        }
    }
    
    private func executeSelectedCommand() {
        guard !availableCommands.isEmpty, selectedIndex < availableCommands.count else { return }
        let command = availableCommands[selectedIndex]
        executeCommand(command)
    }
    
    private func executeCommand(_ command: Command) {
        let context = CommandContext(
            store: store,
            currentWord: store.selectedWord,
            selectedTag: store.selectedTag
        )
        
        Task {
            do {
                let result = try await command.execute(with: context)
                await MainActor.run {
                    handleCommandResult(result)
                }
            } catch {
                await MainActor.run {
                    // Handle error
                    print("Command execution error: \(error)")
                }
            }
        }
        
        isPresented = false
    }
    
    private func handleCommandResult(_ result: CommandResult) {
        switch result {
        case .success(let message):
            print("Success: \(message)")
        case .wordCreated(let word):
            store.selectWord(word)
        case .wordSelected(let word):
            store.selectWord(word)
        case .tagAdded(_, let word):
            store.selectWord(word)
        case .searchPerformed(_):
            // Search results are already handled by the store
            break
        case .navigationRequested(let destination):
            handleNavigation(destination)
        case .layerSwitched(let layer):
            print("已切换到层: \(layer.displayName)")
        case .error(let message):
            print("Error: \(message)")
        }
    }
    
    private func handleNavigation(_ destination: NavigationDestination) {
        switch destination {
        case .map:
            NotificationCenter.default.post(name: .openMapWindow, object: nil)
        case .graph:
            NotificationCenter.default.post(name: .openGraphWindow, object: nil)
        case .settings:
            // Handle settings navigation - could open settings window
            break
        case .word(let id):
            if let word = store.words.first(where: { $0.id == id }) {
                store.selectWord(word)
            }
        }
    }
    
    private func createNewLayer() {
        guard !query.isEmpty else { return }
        
        // 检查是否已存在同名层
        let existingLayer = store.layers.first { 
            $0.name.lowercased() == query.lowercased() || 
            $0.displayName.lowercased() == query.lowercased() 
        }
        
        if existingLayer == nil {
            // 创建新层
            let newLayer = store.createLayer(name: query.lowercased(), displayName: query)
            
            // 切换到新层
            Task {
                await store.switchToLayer(newLayer)
                await MainActor.run {
                    print("已创建并切换到新层: \(newLayer.displayName)")
                    isPresented = false
                }
            }
        } else {
            print("层 '\(query)' 已存在")
        }
    }
}

// MARK: - 新命令行视图

private struct NewCommandRowView: View {
    let command: Command
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: command.icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(command.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(command.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Category badge
                Text(command.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(iconColor.opacity(0.2))
                    )
                    .foregroundColor(iconColor)
                
                if isSelected {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        )
    }
    
    private var iconColor: Color {
        switch command.category {
        case .word: return .green
        case .tag: return .orange
        case .search: return .blue
        case .navigation: return .red
        case .system: return .gray
        case .layer: return .purple
        }
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    static let openMapWindow = Notification.Name("openMapWindow")
    static let openGraphWindow = Notification.Name("openGraphWindow")
    static let addNewWord = Notification.Name("addNewWord")
    static let focusSearch = Notification.Name("focusSearch")
}


#Preview {
    CommandPaletteView(isPresented: .constant(true))
        .environmentObject(WordStore.shared)
}
