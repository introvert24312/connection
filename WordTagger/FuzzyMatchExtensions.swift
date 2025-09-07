import Foundation

// MARK: - Fuzzy Matching Extensions

extension String {
    /// 计算与目标字符串的模糊匹配分数
    func fuzzyMatchScore(with target: String) -> Double {
        let query = self.lowercased()
        let target = target.lowercased()
        let queryChars = Array(query)
        let targetChars = Array(target)
        
        // 完全匹配
        if target == query {
            return 1.0
        }
        
        // 前缀匹配给高分
        if target.hasPrefix(query) {
            return 0.9
        }
        
        // 包含匹配
        if target.contains(query) {
            return 0.7
        }
        
        // 字符序列匹配（不需要连续）
        var targetIndex = 0
        var matchedChars = 0
        
        for queryChar in queryChars {
            while targetIndex < targetChars.count {
                if targetChars[targetIndex] == queryChar {
                    matchedChars += 1
                    targetIndex += 1
                    break
                }
                targetIndex += 1
            }
        }
        
        if matchedChars == queryChars.count {
            // 根据匹配位置的紧密程度给分
            let ratio = Double(matchedChars) / Double(targetChars.count)
            return ratio * 0.6 // 最高0.6分
        }
        
        // 部分字符匹配
        if matchedChars > 0 {
            let ratio = Double(matchedChars) / Double(queryChars.count)
            return ratio * 0.3 // 最高0.3分
        }
        
        return 0.0
    }
}

// MARK: - Fuzzy Search Utilities

struct FuzzySearchResult<T> {
    let item: T
    let score: Double
    let matchedText: String
}

extension Array where Element == String {
    /// 对字符串数组进行模糊搜索
    func fuzzySearch(query: String, limit: Int = 10) -> [FuzzySearchResult<String>] {
        guard !query.isEmpty else { return [] }
        
        let results = self.compactMap { item -> FuzzySearchResult<String>? in
            let score = query.fuzzyMatchScore(with: item)
            return score > 0 && item.lowercased() != query.lowercased() 
                ? FuzzySearchResult(item: item, score: score, matchedText: item) 
                : nil
        }
        
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }
}

// 需要导入Node类型
// extension Array where Element == Node {
//     /// 对节点数组进行模糊搜索
//     func fuzzySearch(query: String, limit: Int = 10) -> [FuzzySearchResult<Node>] {
//         guard !query.isEmpty else { return [] }
//         
//         let results = self.compactMap { node -> FuzzySearchResult<Node>? in
//             let score = query.fuzzyMatchScore(with: node.text)
//             return score > 0 && node.text.lowercased() != query.lowercased()
//                 ? FuzzySearchResult(item: node, score: score, matchedText: node.text)
//                 : nil
//         }
//         
//         return Array(results.sorted { $0.score > $1.score }.prefix(limit))
//     }
// }