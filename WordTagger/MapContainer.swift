import SwiftUI
import CoreLocation
import MapKit

struct MapContainer: View {
    @EnvironmentObject private var store: WordStore
    @Binding var isLocationSelectionMode: Bool
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074), // 北京
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var selectedLocationCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var selectedWord: Word?
    @State private var searchQuery: String = ""
    @State private var showingSearchResults = false
    @State private var geoSearchResults: [MKMapItem] = []
    @State private var isSearchingLocation = false
    @StateObject private var locationManager = LocationManager()
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var selectedLocationName: String = ""
    @State private var showingLocationConfirmation = false
    @State private var mapViewSize: CGSize = CGSize(width: 800, height: 600)
    
    var body: some View {
        ZStack {
            mapView
            overlayView
        }
        .navigationTitle("地图视图")
        .onAppear {
            locationManager.requestLocation()
            print("MapContainer appeared, isLocationSelectionMode: \(isLocationSelectionMode)")
            
            // 监听位置选择模式通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("openMapForLocationSelection"),
                object: nil,
                queue: .main
            ) { _ in
                print("🎯 MapContainer: Received openMapForLocationSelection notification!")
                print("🎯 MapContainer: Current isLocationSelectionMode before: \(isLocationSelectionMode)")
                // 注意：这里不能直接设置，因为isLocationSelectionMode是@Binding
                // 它应该由MapWindow来控制
            }
        }
        .onChange(of: locationManager.location) { _, newLocation in
            if let location = newLocation {
                let newRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                region = newRegion
                cameraPosition = MapCameraPosition.region(newRegion)
            }
        }
        .onChange(of: store.selectedWord) { _, newWord in
            if let word = newWord, !word.locationTags.isEmpty {
                selectedWord = word
                focusOnWord(word)
            }
        }
        .onChange(of: isLocationSelectionMode) { _, newValue in
            print("MapContainer: ⚠️ isLocationSelectionMode changed to \(newValue)")
            print("MapContainer: showingLocationConfirmation is: \(showingLocationConfirmation)")
        }
        .onChange(of: showingLocationConfirmation) { _, newValue in
            print("MapContainer: 🔄 showingLocationConfirmation changed to \(newValue)")
        }
    }
    
    // MARK: - View Components
    
    private var mapView: some View {
        ZStack {
            GeometryReader { geometry in
                Map(position: $cameraPosition) {
                    ForEach(locationAnnotations, id: \.id) { annotation in
                        Annotation(
                            annotation.title,
                            coordinate: annotation.coordinate,
                            anchor: .center
                        ) {
                            LocationMarkerView(annotation: annotation) {
                                selectedWord = annotation.word
                            }
                        }
                    }
                    
                    // Apple风格位置选择大头针
                    if isLocationSelectionMode && !showingLocationConfirmation {
                        Annotation(
                            "选择此位置",
                            coordinate: region.center,
                            anchor: .bottom
                        ) {
                            ApplePinView {
                                selectCurrentLocation()
                            }
                        }
                    }
                    
                    // 选中的位置标记
                    if let selectedLocation = selectedLocation, showingLocationConfirmation {
                        Annotation(
                            "选中位置",
                            coordinate: selectedLocation,
                            anchor: .bottom
                        ) {
                            SelectedLocationPinView()
                        }
                    }
                }
                .mapStyle(.standard)
                .onTapGesture { location in
                    if isLocationSelectionMode {
                        print("Map tapped at screen coordinates: \(location)")
                        handleMapTap(at: location, mapSize: geometry.size)
                    }
                }
                .onAppear {
                    mapViewSize = geometry.size
                    print("📏 Map view size: \(mapViewSize)")
                }
                .onChange(of: geometry.size) { _, newSize in
                    mapViewSize = newSize
                    print("📏 Map view size changed to: \(mapViewSize)")
                }
                .onMapCameraChange { context in
                    // 同步region和cameraPosition
                    region = context.region
                    print("🗺️ Map region updated: center=\(context.region.center), span=\(context.region.span)")
                }
            }
        }
        .focusable()
        .onKeyPress(.return) {
            if isLocationSelectionMode && showingLocationConfirmation {
                confirmLocationSelection()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if isLocationSelectionMode {
                if showingLocationConfirmation {
                    showingLocationConfirmation = false
                    selectedLocation = nil
                } else {
                    isLocationSelectionMode = false
                }
                return .handled
            }
            return .ignored
        }
    }
    
    private var overlayView: some View {
        VStack {
            locationSelectionPrompt
            toolbarView
            searchResultsView
            
            // 调试信息覆盖层
            if isLocationSelectionMode {
                VStack {
                    Text("🐛 调试信息")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text("位置选择模式: \(isLocationSelectionMode ? "✅" : "❌")")
                        .font(.caption)
                    Text("显示确认界面: \(showingLocationConfirmation ? "✅" : "❌")")
                        .font(.caption)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.8))
                .cornerRadius(8)
                .padding()
            }
            
            Spacer()
            selectedWordCard
        }
    }
    
    private var locationSelectionPrompt: some View {
        Group {
            if isLocationSelectionMode {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            if showingLocationConfirmation {
                                Text("已选择位置")
                                    .font(.headline)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(selectedLocationName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    if let coordinate = selectedLocation {
                                        Text("\(String(format: "%.6f", coordinate.latitude)), \(String(format: "%.6f", coordinate.longitude))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text("按回车键确认添加到单词中")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            } else {
                                Text("选择位置")
                                    .font(.headline)
                                Text("点击搜索结果、大头针或地图任意位置")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("取消") {
                            isLocationSelectionMode = false
                            showingLocationConfirmation = false
                            selectedLocation = nil
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if showingLocationConfirmation {
                        HStack(spacing: 12) {
                            Button(action: {
                                confirmLocationSelection()
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("确认添加")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: [])
                            
                            Button(action: {
                                showingLocationConfirmation = false
                                selectedLocation = nil
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise.circle")
                                    Text("重新选择")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
    
    private var toolbarView: some View {
        HStack {
            MapControlsView(
                region: $region,
                cameraPosition: $cameraPosition,
                wordsWithLocation: filteredWordsWithLocation
            )
            
            Spacer()
            
            searchBoxView
            
            Spacer()
            
            if !filteredWordsWithLocation.isEmpty {
                MapStatsView(wordsCount: filteredWordsWithLocation.count)
            }
        }
        .padding()
    }
    
    private var searchBoxView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索地点或单词...", text: $searchQuery)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .onSubmit {
                    showSearchResults()
                }
                .onChange(of: searchQuery) { _, newValue in
                    if !newValue.isEmpty {
                        showSearchResults()
                    } else {
                        showingSearchResults = false
                        geoSearchResults = []
                    }
                }
            
            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    showingSearchResults = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    private var searchResultsView: some View {
        Group {
            if showingSearchResults && !searchQuery.isEmpty {
                VStack(spacing: 8) {
                    MapSearchResults(
                        query: searchQuery,
                        words: store.words,
                        geoResults: geoSearchResults,
                        isSearchingLocation: isSearchingLocation,
                        isLocationSelectionMode: isLocationSelectionMode,
                        onWordSelected: { word in
                            selectedWord = word
                            showingSearchResults = false
                            focusOnWord(word)
                        },
                        onLocationSelected: { mapItem in
                            handleLocationSelection(mapItem)
                        }
                    )
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var selectedWordCard: some View {
        Group {
            if let selectedWord = selectedWord {
                WordLocationCard(word: selectedWord) {
                    self.selectedWord = nil
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func handleLocationSelection(_ mapItem: MKMapItem) {
        if isLocationSelectionMode {
            let locationName = mapItem.name ?? "未知地点"
            print("Selected location from search: \(locationName)")
            NotificationCenter.default.post(
                name: NSNotification.Name("locationSelected"),
                object: locationName
            )
            isLocationSelectionMode = false
            showingSearchResults = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.keyWindow?.close()
            }
        } else {
            showingSearchResults = false
            focusOnLocation(mapItem)
        }
    }
    
    private var wordsWithLocationTags: [Word] {
        return store.words.filter { !$0.locationTags.isEmpty }
    }
    
    private var filteredWordsWithLocation: [Word] {
        let words = wordsWithLocationTags
        
        if searchQuery.isEmpty {
            return words
        }
        
        return words.filter { word in
            word.text.localizedCaseInsensitiveContains(searchQuery) ||
            word.meaning?.localizedCaseInsensitiveContains(searchQuery) == true ||
            word.locationTags.contains { tag in
                tag.value.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }
    
    private var locationAnnotations: [WordLocationAnnotation] {
        return filteredWordsWithLocation.compactMap { word in
            guard let locationTag = word.locationTags.first,
                  let lat = locationTag.latitude,
                  let lng = locationTag.longitude else { return nil }
            
            return WordLocationAnnotation(
                id: word.id,
                word: word,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                locationTag: locationTag
            )
        }
    }
    
    private func focusOnWord(_ word: Word) {
        guard let locationTag = word.locationTags.first,
              let lat = locationTag.latitude,
              let lng = locationTag.longitude else { return }
        
        let newRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        withAnimation(.easeInOut(duration: 1.0)) {
            region = newRegion
            cameraPosition = .region(newRegion)
        }
    }
    
    private func showSearchResults() {
        guard !searchQuery.isEmpty else {
            showingSearchResults = false
            geoSearchResults = []
            return
        }
        
        showingSearchResults = true
        
        // 搜索地理位置
        searchLocation(query: searchQuery)
    }
    
    private func searchLocation(query: String) {
        isSearchingLocation = true
        
        // 首先搜索本地常见地点数据
        let commonLocations = GeographicData.searchLocations(query: query)
        let commonLocationItems = commonLocations.prefix(5).map { location in
            GeographicData.createMKMapItem(from: location)
        }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            Task { @MainActor in
                isSearchingLocation = false
                
                if let response = response {
                    // 合并常见地点和搜索结果，优先显示常见地点
                    let searchResults = Array(response.mapItems.prefix(3))
                    geoSearchResults = Array(commonLocationItems) + searchResults
                    
                    // 如果只有一个地理位置结果，自动聚焦
                    if geoSearchResults.count == 1, let item = geoSearchResults.first {
                        focusOnLocation(item)
                        showingSearchResults = false
                    }
                } else {
                    // 即使搜索失败，也显示常见地点匹配结果
                    geoSearchResults = Array(commonLocationItems)
                }
            }
        }
    }
    
    private func focusOnLocation(_ mapItem: MKMapItem) {
        let coordinate = mapItem.placemark.coordinate
        let newRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        withAnimation(.easeInOut(duration: 1.0)) {
            region = newRegion
            cameraPosition = .region(newRegion)
        }
    }
    
    private func handleMapTap(at location: CGPoint, mapSize: CGSize) {
        print("Map tapped at screen coordinates: \(location)")
        
        // 获取当前地图的显示区域
        let currentRegion = region
        
        // 使用实际的地图视图尺寸
        let mapViewWidth = mapSize.width
        let mapViewHeight = mapSize.height
        
        print("📏 Using map size: \(mapSize)")
        
        // 计算点击位置相对于地图中心的偏移比例
        let centerX = mapViewWidth / 2
        let centerY = mapViewHeight / 2
        
        let offsetX = location.x - centerX  // 相对于中心的像素偏移
        let offsetY = location.y - centerY
        
        // 将像素偏移转换为地理坐标偏移
        // 考虑当前地图的缩放级别（span）
        let longitudeOffset = Double(offsetX) * currentRegion.span.longitudeDelta / Double(mapViewWidth)
        let latitudeOffset = -Double(offsetY) * currentRegion.span.latitudeDelta / Double(mapViewHeight) // Y轴翻转
        
        let tappedCoordinate = CLLocationCoordinate2D(
            latitude: currentRegion.center.latitude + latitudeOffset,
            longitude: currentRegion.center.longitude + longitudeOffset
        )
        
        selectedLocation = tappedCoordinate
        print("🎯 Calculated tapped coordinate: \(tappedCoordinate)")
        print("🎯 Map center: \(currentRegion.center)")
        print("🎯 Map span: \(currentRegion.span)")
        print("🎯 Map center should be at: (\(centerX), \(centerY))")
        print("🎯 Click offset: (\(offsetX), \(offsetY)) pixels")
        print("🎯 Geo offset: (\(longitudeOffset), \(latitudeOffset)) degrees")
        
        // 反向地理编码获取地址信息
        let geocoder = CLGeocoder()
        let locationForGeocoding = CLLocation(latitude: tappedCoordinate.latitude, longitude: tappedCoordinate.longitude)
        
        geocoder.reverseGeocodeLocation(locationForGeocoding) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    // 构建位置名称
                    var locationComponents: [String] = []
                    
                    if let name = placemark.name {
                        locationComponents.append(name)
                    } else if let thoroughfare = placemark.thoroughfare {
                        locationComponents.append(thoroughfare)
                    }
                    
                    if let locality = placemark.locality {
                        locationComponents.append(locality)
                    }
                    
                    if let administrativeArea = placemark.administrativeArea {
                        locationComponents.append(administrativeArea)
                    }
                    
                    self.selectedLocationName = locationComponents.isEmpty ? 
                        "(\(String(format: "%.4f", tappedCoordinate.latitude)), \(String(format: "%.4f", tappedCoordinate.longitude)))" :
                        locationComponents.joined(separator: ", ")
                } else {
                    self.selectedLocationName = "(\(String(format: "%.4f", tappedCoordinate.latitude)), \(String(format: "%.4f", tappedCoordinate.longitude)))"
                }
                
                print("🎯 About to set showingLocationConfirmation = true")
                print("🎯 Current isLocationSelectionMode: \(self.isLocationSelectionMode)")
                self.showingLocationConfirmation = true
                print("✅ Selected location: \(self.selectedLocationName)")
                print("✅ showingLocationConfirmation is now: \(self.showingLocationConfirmation)")
            }
        }
    }
    
    private func selectCurrentLocation() {
        let coordinate = region.center
        selectedLocation = coordinate
        selectedLocationName = "当前位置 (\(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude)))"
        showingLocationConfirmation = true
        print("Selected current location: \(selectedLocationName)")
    }
    
    private func confirmLocationSelection() {
        guard let _ = selectedLocation else { return }
        
        print("Confirming location selection: \(selectedLocationName)")
        
        // 发送位置选择通知
        NotificationCenter.default.post(
            name: NSNotification.Name("locationSelected"),
            object: selectedLocationName
        )
        
        // 重置状态
        isLocationSelectionMode = false
        showingLocationConfirmation = false
        selectedLocation = nil
        
        // 延迟关闭地图窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.keyWindow?.close()
        }
    }
}

// MARK: - WordLocationAnnotation

struct WordLocationAnnotation: Identifiable {
    let id: UUID
    let word: Word
    let coordinate: CLLocationCoordinate2D
    let locationTag: Tag
    
    var title: String {
        return word.text
    }
    
    var subtitle: String {
        return locationTag.value
    }
}

// MARK: - LocationMarkerView

struct LocationMarkerView: View {
    let annotation: WordLocationAnnotation
    let onTap: () -> Void
    
    private var markerColor: Color {
        if let firstTag = annotation.word.tags.first {
            return Color.from(tagType: firstTag.type)
        }
        return .blue
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(markerColor)
                        .frame(width: 32, height: 32)
                        .shadow(radius: 4)
                    
                    Text(String(annotation.word.text.prefix(1)).uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                Text(annotation.title)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.9))
                            .shadow(radius: 2)
                    )
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Map Controls

struct MapControlsView: View {
    @Binding var region: MKCoordinateRegion
    @Binding var cameraPosition: MapCameraPosition
    let wordsWithLocation: [Word]
    
    var body: some View {
        HStack(spacing: 12) {
            // 缩放控制
            VStack(spacing: 4) {
                Button(action: zoomIn) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                }
                .controlButtonStyle()
                
                Button(action: zoomOut) {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .medium))
                }
                .controlButtonStyle()
            }
            
            // 适应所有标记
            Button(action: fitAllMarkers) {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.system(size: 14))
                    Text("全览")
                        .font(.caption)
                }
            }
            .controlButtonStyle()
            .disabled(wordsWithLocation.isEmpty)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func zoomIn() {
        let newRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: region.span.latitudeDelta * 0.5,
                longitudeDelta: region.span.longitudeDelta * 0.5
            )
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            region = newRegion
            cameraPosition = .region(newRegion)
        }
    }
    
    private func zoomOut() {
        let newRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: region.span.latitudeDelta * 2.0,
                longitudeDelta: region.span.longitudeDelta * 2.0
            )
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            region = newRegion
            cameraPosition = .region(newRegion)
        }
    }
    
    private func fitAllMarkers() {
        guard !wordsWithLocation.isEmpty else { return }
        
        var minLat = 90.0
        var maxLat = -90.0
        var minLng = 180.0
        var maxLng = -180.0
        
        for word in wordsWithLocation {
            for locationTag in word.locationTags {
                if let lat = locationTag.latitude, let lng = locationTag.longitude {
                    minLat = min(minLat, lat)
                    maxLat = max(maxLat, lat)
                    minLng = min(minLng, lng)
                    maxLng = max(maxLng, lng)
                }
            }
        }
        
        let centerLat = (minLat + maxLat) / 2
        let centerLng = (minLng + maxLng) / 2
        let spanLat = (maxLat - minLat) * 1.2 // 添加一些边距
        let spanLng = (maxLng - minLng) * 1.2
        
        let newRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
            span: MKCoordinateSpan(
                latitudeDelta: max(spanLat, 0.01),
                longitudeDelta: max(spanLng, 0.01)
            )
        )
        
        withAnimation(.easeInOut(duration: 1.0)) {
            region = newRegion
            cameraPosition = .region(newRegion)
        }
    }
}

// MARK: - Map Stats

struct MapStatsView: View {
    let wordsCount: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text("\(wordsCount) 个位置")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

// MARK: - Word Location Card

struct WordLocationCard: View {
    let word: Word
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.text)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let meaning = word.meaning {
                        Text(meaning)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    if let phonetic = word.phonetic {
                        Text(phonetic)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // 位置标签
            if !word.locationTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("位置信息")
                        .font(.headline)
                    
                    ForEach(word.locationTags, id: \.id) { tag in
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            
                            Text(tag.value)
                                .font(.body)
                            
                            if let lat = tag.latitude, let lng = tag.longitude {
                                Spacer()
                                Text("\(lat, specifier: "%.4f"), \(lng, specifier: "%.4f")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            // 其他标签
            let otherTags = word.tags.filter { $0.type != .location }
            if !otherTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("其他标签")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                        ForEach(otherTags, id: \.id) { tag in
                            TagChip(tag: tag)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}


// MARK: - Control Button Style

struct ControlButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.primary)
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func controlButtonStyle() -> some View {
        modifier(ControlButtonStyle())
    }
}

// MARK: - Extensions

extension CLLocationCoordinate2D {
    func isEqual(to other: CLLocationCoordinate2D, tolerance: Double = 0.0001) -> Bool {
        return abs(self.latitude - other.latitude) < tolerance &&
               abs(self.longitude - other.longitude) < tolerance
    }
}

extension MKCoordinateSpan {
    func isEqual(to other: MKCoordinateSpan, tolerance: Double = 0.0001) -> Bool {
        return abs(self.latitudeDelta - other.latitudeDelta) < tolerance &&
               abs(self.longitudeDelta - other.longitudeDelta) < tolerance
    }
}

// MARK: - Map Search Results

struct MapSearchResults: View {
    let query: String
    let words: [Word]
    let geoResults: [MKMapItem]
    let isSearchingLocation: Bool
    let isLocationSelectionMode: Bool
    let onWordSelected: (Word) -> Void
    let onLocationSelected: (MKMapItem) -> Void
    
    private var wordResults: [Word] {
        if query.isEmpty {
            return []
        }
        
        return words.filter { word in
            word.text.localizedCaseInsensitiveContains(query) ||
            word.meaning?.localizedCaseInsensitiveContains(query) == true ||
            word.tags.contains { tag in
                tag.value.localizedCaseInsensitiveContains(query)
            }
        }.prefix(3).map { $0 }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 单词搜索结果
            if !wordResults.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("单词结果")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(wordResults.count) 个")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    LazyVStack(spacing: 0) {
                        ForEach(wordResults, id: \.id) { word in
                            MapSearchResultRow(word: word) {
                                onWordSelected(word)
                            }
                            
                            if word.id != wordResults.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
                .padding(.horizontal)
            }
            
            // 地理位置搜索结果
            if isSearchingLocation || !geoResults.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("地点结果")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if isSearchingLocation {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("\(geoResults.count) 个")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    if !geoResults.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(geoResults.enumerated()), id: \.offset) { index, mapItem in
                                LocationSearchResultRow(mapItem: mapItem, isLocationSelectionMode: isLocationSelectionMode) {
                                    onLocationSelected(mapItem)
                                }
                                
                                if index < geoResults.count - 1 {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
                .padding(.horizontal)
            }
        }
    }
}

struct MapSearchResultRow: View {
    let word: Word
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(word.locationTags.isEmpty ? Color.gray : Color.red)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(word.text)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let meaning = word.meaning {
                        Text(meaning)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if !word.locationTags.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                            
                            Text(word.locationTags.first?.value ?? "")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

struct LocationSearchResultRow: View {
    let mapItem: MKMapItem
    let isLocationSelectionMode: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isLocationSelectionMode ? Color.blue : Color.red)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mapItem.name ?? "未知地点")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let address = mapItem.placemark.title {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                if isLocationSelectionMode {
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("选择")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                } else {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocation() {
        switch authorizationStatus {
        case .notDetermined:
            #if os(macOS)
            manager.requestAlwaysAuthorization()
            #else
            manager.requestWhenInUseAuthorization()
            #endif
        case .authorizedAlways:
            manager.requestLocation()
        #if !os(macOS)
        case .authorizedWhenInUse:
            manager.requestLocation()
        #endif
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        #if os(macOS)
        if status == .authorizedAlways {
            manager.requestLocation()
        }
        #else
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
        #endif
    }
}

// MARK: - Apple Pin View

struct ApplePinView: View {
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 3D立体细针设计 - 真实感大头针
            ZStack {
                // 底层阴影 - 增强3D效果
                Circle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 18, height: 18)
                    .offset(x: 1, y: 2)
                    .blur(radius: 1)
                
                // 针头主体 - 3D渐变效果
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.red.opacity(0.9),
                                Color.red,
                                Color.red.opacity(0.7)
                            ],
                            center: UnitPoint(x: 0.3, y: 0.3),
                            startRadius: 2,
                            endRadius: 8
                        )
                    )
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.6), Color.gray.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
                
                // 高光点 - 3D立体感
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 3, height: 3)
                    .offset(x: -2, y: -2)
                
                // 中心精确点
                Circle()
                    .fill(Color.white)
                    .frame(width: 2, height: 2)
            }
            
            // 3D针尖 - 带有立体阴影
            ZStack {
                // 针尖阴影
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: -1.5, y: 10))
                    path.addLine(to: CGPoint(x: 1.5, y: 10))
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.3))
                .offset(x: 1, y: 1)
                .blur(radius: 0.5)
                
                // 针尖主体 - 渐变3D效果
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: -1.5, y: 10))
                    path.addLine(to: CGPoint(x: 1.5, y: 10))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.9),
                            Color.red,
                            Color.red.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: -1.5, y: 10))
                        path.addLine(to: CGPoint(x: 1.5, y: 10))
                        path.closeSubpath()
                    }
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.3)
                )
            }
            .offset(y: -1)
        }
        .onTapGesture {
            onTap()
        }
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.2), value: true)
    }
}

// MARK: - Selected Location Pin View

struct SelectedLocationPinView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 3D立体确认针设计 - 蓝色版本
            ZStack {
                // 底层阴影 - 增强3D效果
                Circle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 18, height: 18)
                    .offset(x: 1, y: 2)
                    .blur(radius: 1)
                
                // 针头主体 - 3D渐变效果（蓝色）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.9),
                                Color.blue,
                                Color.blue.opacity(0.7)
                            ],
                            center: UnitPoint(x: 0.3, y: 0.3),
                            startRadius: 2,
                            endRadius: 8
                        )
                    )
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.6), Color.gray.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                
                // 高光点 - 3D立体感
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 3, height: 3)
                    .offset(x: -2, y: -2)
                
                // 确认标记 - 白色勾号
                Text("✓")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // 3D针尖 - 带有立体阴影（蓝色）
            ZStack {
                // 针尖阴影
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: -1.5, y: 10))
                    path.addLine(to: CGPoint(x: 1.5, y: 10))
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.3))
                .offset(x: 1, y: 1)
                .blur(radius: 0.5)
                
                // 针尖主体 - 渐变3D效果（蓝色）
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: -1.5, y: 10))
                    path.addLine(to: CGPoint(x: 1.5, y: 10))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.9),
                            Color.blue,
                            Color.blue.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: -1.5, y: 10))
                        path.addLine(to: CGPoint(x: 1.5, y: 10))
                        path.closeSubpath()
                    }
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.3)
                )
            }
            .offset(y: -1)
        }
        .scaleEffect(1.1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    MapContainer(isLocationSelectionMode: .constant(false))
        .environmentObject(WordStore.shared)
}