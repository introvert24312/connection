import Foundation
import MapKit

struct GeographicData {
    static let commonLocations: [CommonLocation] = [
        // 中国主要城市
        CommonLocation(name: "北京", coordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)),
        CommonLocation(name: "上海", coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)),
        CommonLocation(name: "广州", coordinate: CLLocationCoordinate2D(latitude: 23.1291, longitude: 113.2644)),
        CommonLocation(name: "深圳", coordinate: CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)),
        CommonLocation(name: "杭州", coordinate: CLLocationCoordinate2D(latitude: 30.2741, longitude: 120.1551)),
        CommonLocation(name: "南京", coordinate: CLLocationCoordinate2D(latitude: 32.0603, longitude: 118.7969)),
        CommonLocation(name: "成都", coordinate: CLLocationCoordinate2D(latitude: 30.5728, longitude: 104.0668)),
        CommonLocation(name: "重庆", coordinate: CLLocationCoordinate2D(latitude: 29.5630, longitude: 106.5516)),
        CommonLocation(name: "西安", coordinate: CLLocationCoordinate2D(latitude: 34.3416, longitude: 108.9398)),
        CommonLocation(name: "武汉", coordinate: CLLocationCoordinate2D(latitude: 30.5928, longitude: 114.3055)),
        
        // 世界主要城市
        CommonLocation(name: "纽约", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)),
        CommonLocation(name: "洛杉矶", coordinate: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)),
        CommonLocation(name: "伦敦", coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)),
        CommonLocation(name: "巴黎", coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)),
        CommonLocation(name: "东京", coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)),
        CommonLocation(name: "首尔", coordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)),
        CommonLocation(name: "新加坡", coordinate: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198)),
        CommonLocation(name: "悉尼", coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)),
        CommonLocation(name: "多伦多", coordinate: CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832)),
        CommonLocation(name: "柏林", coordinate: CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)),
        
        // 中国著名景点
        CommonLocation(name: "故宫", coordinate: CLLocationCoordinate2D(latitude: 39.9163, longitude: 116.3972)),
        CommonLocation(name: "天安门", coordinate: CLLocationCoordinate2D(latitude: 39.9055, longitude: 116.3976)),
        CommonLocation(name: "长城", coordinate: CLLocationCoordinate2D(latitude: 40.4319, longitude: 116.5704)),
        CommonLocation(name: "西湖", coordinate: CLLocationCoordinate2D(latitude: 30.2489, longitude: 120.1292)),
        CommonLocation(name: "外滩", coordinate: CLLocationCoordinate2D(latitude: 31.2397, longitude: 121.4912)),
        CommonLocation(name: "兵马俑", coordinate: CLLocationCoordinate2D(latitude: 34.3848, longitude: 109.2734)),
        CommonLocation(name: "黄山", coordinate: CLLocationCoordinate2D(latitude: 30.1644, longitude: 118.1662)),
        CommonLocation(name: "泰山", coordinate: CLLocationCoordinate2D(latitude: 36.2543, longitude: 117.1011)),
        CommonLocation(name: "九寨沟", coordinate: CLLocationCoordinate2D(latitude: 33.2540, longitude: 103.9196)),
        CommonLocation(name: "张家界", coordinate: CLLocationCoordinate2D(latitude: 29.1173, longitude: 110.4792)),
        
        // 世界著名景点
        CommonLocation(name: "自由女神像", coordinate: CLLocationCoordinate2D(latitude: 40.6892, longitude: -74.0445)),
        CommonLocation(name: "埃菲尔铁塔", coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945)),
        CommonLocation(name: "大本钟", coordinate: CLLocationCoordinate2D(latitude: 51.5007, longitude: -0.1246)),
        CommonLocation(name: "富士山", coordinate: CLLocationCoordinate2D(latitude: 35.3606, longitude: 138.7274)),
        CommonLocation(name: "悉尼歌剧院", coordinate: CLLocationCoordinate2D(latitude: -33.8568, longitude: 151.2153)),
        CommonLocation(name: "金门大桥", coordinate: CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783)),
        CommonLocation(name: "泰姬陵", coordinate: CLLocationCoordinate2D(latitude: 27.1751, longitude: 78.0421)),
        CommonLocation(name: "罗马斗兽场", coordinate: CLLocationCoordinate2D(latitude: 41.8902, longitude: 12.4922)),
        
        // 大学和学校
        CommonLocation(name: "清华大学", coordinate: CLLocationCoordinate2D(latitude: 40.0031, longitude: 116.3262)),
        CommonLocation(name: "北京大学", coordinate: CLLocationCoordinate2D(latitude: 39.9926, longitude: 116.3057)),
        CommonLocation(name: "复旦大学", coordinate: CLLocationCoordinate2D(latitude: 31.2989, longitude: 121.5027)),
        CommonLocation(name: "浙江大学", coordinate: CLLocationCoordinate2D(latitude: 30.2636, longitude: 120.1216)),
        CommonLocation(name: "哈佛大学", coordinate: CLLocationCoordinate2D(latitude: 42.3770, longitude: -71.1167)),
        CommonLocation(name: "斯坦福大学", coordinate: CLLocationCoordinate2D(latitude: 37.4275, longitude: -122.1697)),
        CommonLocation(name: "麻省理工学院", coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0942)),
        CommonLocation(name: "牛津大学", coordinate: CLLocationCoordinate2D(latitude: 51.7548, longitude: -1.2544)),
        CommonLocation(name: "剑桥大学", coordinate: CLLocationCoordinate2D(latitude: 52.2043, longitude: 0.1218)),
        CommonLocation(name: "东京大学", coordinate: CLLocationCoordinate2D(latitude: 35.7128, longitude: 139.7617)),
        
        // 机场
        CommonLocation(name: "北京首都国际机场", coordinate: CLLocationCoordinate2D(latitude: 40.0799, longitude: 116.6031)),
        CommonLocation(name: "上海浦东国际机场", coordinate: CLLocationCoordinate2D(latitude: 31.1443, longitude: 121.8083)),
        CommonLocation(name: "广州白云国际机场", coordinate: CLLocationCoordinate2D(latitude: 23.3924, longitude: 113.2988)),
        CommonLocation(name: "洛杉矶国际机场", coordinate: CLLocationCoordinate2D(latitude: 33.9425, longitude: -118.4081)),
        CommonLocation(name: "伦敦希思罗机场", coordinate: CLLocationCoordinate2D(latitude: 51.4700, longitude: -0.4543)),
        CommonLocation(name: "成田国际机场", coordinate: CLLocationCoordinate2D(latitude: 35.7720, longitude: 140.3929)),
        
        // 商圈和地标
        CommonLocation(name: "王府井", coordinate: CLLocationCoordinate2D(latitude: 39.9097, longitude: 116.4174)),
        CommonLocation(name: "三里屯", coordinate: CLLocationCoordinate2D(latitude: 39.9371, longitude: 116.4486)),
        CommonLocation(name: "南京路", coordinate: CLLocationCoordinate2D(latitude: 31.2355, longitude: 121.4737)),
        CommonLocation(name: "时代广场", coordinate: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)),
        CommonLocation(name: "香榭丽舍大街", coordinate: CLLocationCoordinate2D(latitude: 48.8698, longitude: 2.3076)),
        CommonLocation(name: "银座", coordinate: CLLocationCoordinate2D(latitude: 35.6719, longitude: 139.7647)),
        CommonLocation(name: "明洞", coordinate: CLLocationCoordinate2D(latitude: 37.5636, longitude: 126.9826))
    ]
    
    static func searchLocations(query: String) -> [CommonLocation] {
        guard !query.isEmpty else { return [] }
        
        return commonLocations.filter { location in
            location.name.localizedCaseInsensitiveContains(query)
        }.sorted { first, second in
            // 优先显示完全匹配的结果
            if first.name.lowercased() == query.lowercased() {
                return true
            } else if second.name.lowercased() == query.lowercased() {
                return false
            }
            // 然后按照前缀匹配排序
            let firstHasPrefix = first.name.lowercased().hasPrefix(query.lowercased())
            let secondHasPrefix = second.name.lowercased().hasPrefix(query.lowercased())
            
            if firstHasPrefix && !secondHasPrefix {
                return true
            } else if !firstHasPrefix && secondHasPrefix {
                return false
            }
            // 最后按名称长度排序
            return first.name.count < second.name.count
        }
    }
    
    static func createMKMapItem(from location: CommonLocation) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: location.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = location.name
        return mapItem
    }
}

struct CommonLocation: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CommonLocation, rhs: CommonLocation) -> Bool {
        lhs.id == rhs.id
    }
}