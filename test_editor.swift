import SwiftUI
import WebKit

// 全新的简单Typora编辑器
struct NewSimpleEditor: View {
    @Binding var text: String
    @Binding var isEditing: Bool
    let onTextChange: (String) -> Void
    
    var body: some View {
        Group {
            if isEditing {
                // 超简单TextEditor先验证逻辑
                VStack {
                    HStack {
                        Text("📝 编辑中")
                        Spacer()
                        Button("完成") { isEditing = false }
                    }
                    
                    TextEditor(text: $text)
                        .font(.title3)
                        .onChange(of: text) { _, newValue in
                            onTextChange(newValue)
                        }
                }
                .padding()
            } else if text.isEmpty {
                VStack {
                    Text("开始编写")
                        .font(.title)
                    Text("点击开始")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditing = true
                }
            } else {
                // 简单预览
                ScrollView {
                    Text(text)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditing = true
                }
            }
        }
    }
}