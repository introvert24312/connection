import Foundation
import CoreLocation
import SwiftUI

// MARK: - Array Extensions

extension Array where Element: Hashable {
    func unique() -> [Element] {
        Array(Set(self))
    }
}

// MARK: - CLLocationCoordinate2D Extensions

extension CLLocationCoordinate2D {
    static func from(string: String) -> CLLocationCoordinate2D? {
        // 解析格式: "lat,lng" 或 "lat, lng"
        let comps = string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard comps.count == 2,
              let lat = Double(comps[0]), 
              let lng = Double(comps[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    func toString() -> String {
        return "\(latitude),\(longitude)"
    }
}

// MARK: - Color Extensions

extension Color {
    public static func from(tagType: Tag.TagType) -> Color {
        switch tagType {
        case .memory: return Color(.systemPink)
        case .location: return Color(.systemGreen)
        case .root: return Color(.systemBlue)
        case .shape: return Color(.systemPurple)
        case .sound: return Color(.systemOrange)
        case .custom: return Color(.systemGray)
        }
    }
    
    public static func from(colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return Color(.systemBlue)
        case "green": return Color(.systemGreen)
        case "orange": return Color(.systemOrange)
        case "red": return Color(.systemRed)
        case "purple": return Color(.systemPurple)
        case "pink": return Color(.systemPink)
        case "yellow": return Color(.systemYellow)
        case "gray", "grey": return Color(.systemGray)
        default: return Color(.systemBlue)
        }
    }
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Date Extensions

extension Date {
    public func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    public func formatForDisplay() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - String Extensions

extension String {
    func levenshteinDistance(to other: String) -> Int {
        let a = Array(self.lowercased())
        let b = Array(other.lowercased())
        
        var distance = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count {
            distance[i][0] = i
        }
        
        for j in 0...b.count {
            distance[0][j] = j
        }
        
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i-1] == b[j-1] {
                    distance[i][j] = distance[i-1][j-1]
                } else {
                    distance[i][j] = Swift.min(
                        distance[i-1][j] + 1,     // deletion
                        distance[i][j-1] + 1,     // insertion
                        distance[i-1][j-1] + 1    // substitution
                    )
                }
            }
        }
        
        return distance[a.count][b.count]
    }
    
    func similarity(to other: String) -> Double {
        let maxLength = max(self.count, other.count)
        if maxLength == 0 { return 1.0 }
        let distance = levenshteinDistance(to: other)
        return 1.0 - Double(distance) / Double(maxLength)
    }
}

// MARK: - Debugging Helpers

#if DEBUG
extension WordStore {
    func printDebugInfo() {
        print("=== WordStore Debug Info ===")
        print("Total words: \(words.count)")
        print("Total unique tags: \(allTags.count)")
        print("Selected word: \(selectedWord?.text ?? "None")")
        print("Search query: '\(searchQuery)'")
        print("Search results: \(searchResults.count)")
        
        for tagType in Tag.TagType.allCases {
            let count = wordsCount(forTagType: tagType)
            print("\(tagType.displayName) tags: \(count) words")
        }
        print("============================")
    }
}
#endif

// MARK: - Performance Monitoring

public class PerformanceTimer {
    private let startTime: CFAbsoluteTime
    private let operation: String
    
    public init(_ operation: String) {
        self.operation = operation
        self.startTime = CFAbsoluteTimeGetCurrent()
    }
    
    public func end() {
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ \(operation): \(String(format: "%.2f", timeElapsed * 1000))ms")
    }
}