import SwiftUI

struct NodeContextMenuView: View {
    let node: Node
    let onEditCommand: () -> Void
    let onEditName: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Edit Command Label option
            Button(action: onEditCommand) {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.body)
                        .foregroundColor(.blue)
                        .frame(width: 16, height: 16)
                    
                    Text("Edit Command Label")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.clear)
            .onHover { isHovered in
                // Add hover effect if needed
            }
            
            // Edit Node Name option
            Button(action: onEditName) {
                HStack(spacing: 12) {
                    Image(systemName: "pencil")
                        .font(.body)
                        .foregroundColor(.blue)
                        .frame(width: 16, height: 16)
                    
                    Text("Edit Node Name")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.clear)
            
            // Divider
            Divider()
                .padding(.horizontal, 8)
            
            // Delete option
            Button(action: onDelete) {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(width: 16, height: 16)
                    
                    Text("Delete Node")
                        .font(.body)
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.clear)
        }
        .frame(minWidth: 180)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#Preview {
    NodeContextMenuView(
        node: Node(
            text: "Sample Node",
            phonetic: "sample",
            meaning: "A test node",
            layerId: UUID(),
            tags: [],
            isCompound: false,
            markdown: "# Sample Node\nThis is a test node."
        ),
        onEditCommand: {
            print("Edit command tapped")
        },
        onEditName: {
            print("Edit name tapped")
        },
        onDelete: {
            print("Delete tapped")
        }
    )
    .padding()
    .frame(width: 300, height: 200)
}