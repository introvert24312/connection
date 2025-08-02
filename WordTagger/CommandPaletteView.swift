import SwiftUI
import CoreLocation
import MapKit

struct CommandPaletteView: View {
    @EnvironmentObject private var store: WordStore
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @StateObject private var commandParser = CommandParser.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索输入框
            HStack {
                Image(systemName: "command")
                    .foregroundColor(.blue)
                
                TextField("输入命令或搜索单词...", text: $query, onCommit: executeSelectedCommand)
                    .textFieldStyle(.plain)
                    .font(.title3)
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
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .padding()
        .onAppear {
            // 重置状态
            query = ""
            selectedIndex = 0
            
            // 延迟聚焦到输入框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // 确保窗口是活跃的
                if let window = NSApplication.shared.keyWindow {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .onChange(of: query) { _, newQuery in
            commandParser.updateSuggestions(
                for: newQuery,
                context: CommandContext(
                    store: store,
                    currentWord: store.selectedWord,
                    selectedTag: store.selectedTag
                )
            )
            selectedIndex = 0
        }
    }
    
    private var availableCommands: [Command] {
        let context = CommandContext(
            store: store,
            currentWord: store.selectedWord,
            selectedTag: store.selectedTag
        )
        
        let commands = commandParser.parse(query, context: context)
        print("🎯 CommandPalette availableCommands: query='\(query)', commands=\(commands.count)")
        for (i, cmd) in commands.enumerated() {
            print("  \(i): '\(cmd.title)' - '\(cmd.description)'")
        }
        return commands
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
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(command.description)
                        .font(.caption)
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