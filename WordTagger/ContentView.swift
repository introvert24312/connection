import SwiftUI
import CoreLocation
import MapKit

struct ContentView: View {
    @EnvironmentObject private var store: WordStore
    @State private var selectedWord: Word?
    @State private var showSidebar: Bool = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：标签和搜索
            if showSidebar {
                TagSidebarView(selectedWord: $selectedWord)
                    .frame(width: 300)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            // 中间：单词列表
            WordListView(selectedWord: $selectedWord)
                .frame(minWidth: showSidebar ? 400 : 500)
            
            // 右侧：详情面板
            if let word = selectedWord {
                DetailPanel(word: word)
                    .frame(minWidth: 500)
            } else {
                WelcomeView()
                    .frame(minWidth: 500)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSidebar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    openWindow(id: "map")
                }) {
                    Image(systemName: "map")
                        .foregroundColor(.blue)
                }
                .help("打开地图视图 (⌘M)")
                
                Button(action: {
                    openWindow(id: "graph")
                }) {
                    Image(systemName: "circle.hexagonpath")
                        .foregroundColor(.purple)
                }
                .help("打开全局图谱 (⌘G)")
                
                Button(action: {
                    store.selectWord(nil)
                    selectedWord = nil
                }) {
                    Image(systemName: "clear")
                        .foregroundColor(.gray)
                }
                .help("清除选择")
            }
        }
        .onAppear {
            // 同步selectedWord状态
            DispatchQueue.main.async {
                selectedWord = store.selectedWord
            }
            
            // 注册通知监听器
            NotificationCenter.default.addObserver(
                forName: .openMapWindow,
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "map")
            }
            
            NotificationCenter.default.addObserver(
                forName: .openGraphWindow,
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "graph")
            }
            
            NotificationCenter.default.addObserver(
                forName: Notification.Name("openWordManager"),
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "wordManager")
            }
            
            // 监听切换侧边栏的通知
            NotificationCenter.default.addObserver(
                forName: Notification.Name("toggleSidebar"),
                object: nil,
                queue: .main
            ) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSidebar.toggle()
                }
            }
        }
        .onChange(of: store.selectedWord) { _, newValue in
            DispatchQueue.main.async {
                selectedWord = newValue
            }
        }
        .onChange(of: store.words) { _, _ in
            // 当words变化时，检查selectedWord是否还有效
            DispatchQueue.main.async {
                if let current = selectedWord, !store.words.contains(where: { $0.id == current.id }) {
                    selectedWord = nil
                }
            }
        }
    }
}

// MARK: - 欢迎视图

struct WelcomeView: View {
    @EnvironmentObject private var store: WordStore
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("欢迎使用单词标签管理器")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("使用智能标签系统来组织和记忆单词")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                    Text("按 ⌘N 添加新单词")
                }
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                    Text("按 ⌘F 搜索单词")
                }
                
                HStack {
                    Image(systemName: "command")
                        .foregroundColor(.purple)
                    Text("按 ⌘K 打开命令面板")
                }
            }
            .font(.body)
            .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("当前统计")
                    .font(.headline)
                
                HStack(spacing: 30) {
                    StatCard(title: "单词总数", value: "\(store.words.count)", color: .blue)
                    StatCard(title: "标签总数", value: "\(store.allTags.count)", color: .green)
                    StatCard(title: "地点标签", value: "\(store.allTags.filter { $0.hasCoordinates }.count)", color: .red)
                }
            }
            
            Spacer()
        }
        .padding(40)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(WordStore.shared)
}