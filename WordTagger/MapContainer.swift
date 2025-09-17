import SwiftUI
import CoreLocation
import MapKit

struct MapContainer: View {
    @EnvironmentObject private var store: NodeStore
    @Binding var isLocationSelectionMode: Bool
    var sourceWindowId: String? = nil
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
    @State private var selectedNode: Node?
    @State private var searchQuery: String = ""
    @State private var showingSearchResults = false
    @State private var geoSearchResults: [MKMapItem] = []
    @State private var isSearchingLocation = false
    @StateObject private var locationManager = LocationManager()
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var selectedLocationName: String = ""
    @State private var isPreviewingLocation: Bool = false
    @State private var mapViewSize: CGSize = CGSize(width: 800, height: 600)
    @State private var currentHeading: Double = 0
    @State private var currentPitch: Double = 0
    
    var body: some View {
        ZStack {
            mapView
            overlayView
        }
        .navigationTitle("地图视图")
        .onAppear {
            locationManager.requestLocation()
            print("MapContainer appeared, isLocationSelectionMode: \(isLocationSelectionMode)")
            print("🔗 MapContainer (中间层): 初始 sourceWindowId = \(sourceWindowId ?? "nil")")
            
            // 🔧 增强窗口映射的稳定性检查
            if sourceWindowId == nil {
                print("⚠️ MapContainer: sourceWindowId为空，将依赖WindowFocusManager进行路由")
            } else {
                print("✅ MapContainer: 已配置 sourceWindowId - \(String(sourceWindowId!.prefix(8)))")
            }
            
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
            
            // 监听位置预览通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("previewLocation"),
                object: nil,
                queue: .main
            ) { notification in
                if let previewData = notification.object as? [String: Any],
                   let latitude = previewData["latitude"] as? Double,
                   let longitude = previewData["longitude"] as? Double,
                   let name = previewData["name"] as? String {
                    
                    print("🎯 MapContainer: Received location preview request for \(name)")
                    
                    // 设置预览位置
                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    selectedLocation = coordinate
                    selectedLocationName = name
                    
                    // 聚焦到该位置
                    let newRegion = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    
                    withAnimation(.easeInOut(duration: 1.0)) {
                        region = newRegion
                        cameraPosition = .region(newRegion)
                    }
                    
                    // 3秒后自动清除预览标记
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if !isLocationSelectionMode {
                            selectedLocation = nil
                            selectedLocationName = ""
                        }
                    }
                }
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
        .onChange(of: store.selectedNode) { _, newNode in
            if let node = newNode, !node.locationTags.isEmpty {
                selectedNode = node
                focusOnNode(node)
            }
        }
        .onChange(of: isLocationSelectionMode) { _, newValue in
            print("MapContainer (中间层): ⚠️ isLocationSelectionMode changed to \(newValue)")
            if newValue {
                print("🗺️ MapContainer: 进入位置选择模式 - sourceWindowId = \(sourceWindowId ?? "nil")")
            }
        }
    }
    
    // MARK: - View Components
    
    private var mapView: some View {
        ZStack {
            MapReader { proxy in
                GeometryReader { geometry in
                    Map(position: $cameraPosition) {
                        ForEach(locationAnnotations, id: \.id) { annotation in
                            Annotation(
                                "", // Remove title to avoid duplicate labels
                                coordinate: annotation.coordinate,
                                anchor: .center
                            ) {
                                LocationMarkerView(annotation: annotation) {
                                    print("🎯 Map node clicked: \(annotation.word.text)")
                                    handleMapNodeTap(annotation.word)
                                }
                            }
                        }
                        
                        // 3D精美大头针 - 显示选中或搜索的位置
                        if let selectedLocation = selectedLocation {
                            Annotation(
                                selectedLocationName.isEmpty ? "选中位置" : selectedLocationName,
                                coordinate: selectedLocation,
                                anchor: .bottom
                            ) {
                                if isLocationSelectionMode {
                                    Premium3DPinView()
                                } else {
                                    // 搜索结果的临时标记，使用不同的样式
                                    SearchLocationPinView()
                                }
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .onMapCameraChange { context in
                        // 同步region和cameraPosition
                        region = context.region
                        
                        // Track rotation/heading for coordinate conversion
                        let camera = context.camera
                        currentHeading = camera.heading
                        currentPitch = camera.pitch
                        
                        print("🗺️ Map updated - Region: \(context.region.center), Heading: \(currentHeading)°, Pitch: \(currentPitch)°")
                    }
                    .onTapGesture(coordinateSpace: .local) { location in
                        if isLocationSelectionMode {
                            // Use MapProxy for accurate coordinate conversion (handles rotation automatically)
                            if let tappedCoordinate = proxy.convert(location, from: .local) {
                                selectedLocation = tappedCoordinate
                                isPreviewingLocation = true
                                reverseGeocodeLocation(coordinate: tappedCoordinate)
                                print("🎯 Tapped coordinate (MapProxy): \(tappedCoordinate)")
                            } else {
                                // Fallback to manual conversion with rotation handling
                                let tappedCoordinate = convertScreenToMapCoordinate(screenPoint: location, mapSize: geometry.size)
                                selectedLocation = tappedCoordinate
                                isPreviewingLocation = true
                                reverseGeocodeLocation(coordinate: tappedCoordinate)
                                print("🎯 Tapped coordinate (Manual): \(tappedCoordinate)")
                            }
                        } else {
                            // 在非位置选择模式下，让节点点击事件优先处理
                            print("🗺️ Map tapped in normal mode - allowing node clicks to handle")
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
                }
            }
        }
        .focusable(true)
        .onKeyPress(.return) {
            if isLocationSelectionMode && selectedLocation != nil {
                confirmLocationSelection()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if isLocationSelectionMode {
                isLocationSelectionMode = false
                selectedLocation = nil
                selectedLocationName = ""
                isPreviewingLocation = false
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("l"), phases: .down) { keyPress in
            // L键切换位置选择模式
            isLocationSelectionMode.toggle()
            if !isLocationSelectionMode {
                // 退出位置选择模式时清理状态
                selectedLocation = nil
                selectedLocationName = ""
                isPreviewingLocation = false
            }
            return .handled
        }
    }
    
    private var overlayView: some View {
        VStack {
            locationSelectionPrompt
            toolbarView
            searchResultsView
            
            // 搜索位置或预览位置提示信息
            if selectedLocation != nil && !isLocationSelectionMode && !selectedLocationName.isEmpty {
                VStack {
                    HStack {
                        Image(systemName: selectedLocationName.contains("搜索位置") ? "info.circle.fill" : "location.circle.fill")
                            .foregroundColor(.blue)
                        
                        if selectedLocationName.contains("搜索位置") {
                            Text("搜索位置: \(selectedLocationName)")
                                .font(.caption)
                            Text("(5秒后自动消失)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("预览位置: \(selectedLocationName)")
                                .font(.caption)
                            Text("(3秒后自动消失)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding()
                .transition(.opacity)
            }
            
            
            Spacer()
            selectedNodeCard
        }
    }
    
    private var locationSelectionPrompt: some View {
        Group {
            if isLocationSelectionMode {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                        if selectedLocation != nil {
                            // 一行显示选中的位置信息（显示地名，但插入时使用坐标）
                            HStack(spacing: 8) {
                                Text(selectedLocationName.isEmpty ? "选中位置" : selectedLocationName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("• 按回车键确认添加")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            Text("点击地图任意位置选择坐标")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
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
                wordsWithLocation: filteredNodesWithLocation
            )
            
            Spacer()
            
            searchBoxView
            
            Spacer()
            
            // 位置选择相关按钮
            HStack(spacing: 8) {
                // 选择位置按钮
                if !isLocationSelectionMode {
                    Button(action: {
                        isLocationSelectionMode = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "location")
                                .font(.system(size: 14))
                            Text("选择位置")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("进入位置选择模式")
                }
                
                // 退出选择按钮
                if isLocationSelectionMode {
                    Button(action: {
                        isLocationSelectionMode = false
                        selectedLocation = nil
                        selectedLocationName = ""
                        isPreviewingLocation = false
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 14))
                            Text("退出选择")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("退出位置选择模式")
                }
            }
            
            if !filteredNodesWithLocation.isEmpty {
                MapStatsView(wordsCount: filteredNodesWithLocation.count)
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
                .disabled(isLocationSelectionMode) // 在位置选择模式时禁用搜索框
                .onSubmit {
                    // 在位置选择模式时，不处理搜索提交，让地图处理回车键
                    if !isLocationSelectionMode {
                        showSearchResults()
                    }
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
                        nodes: store.nodes,
                        geoResults: geoSearchResults,
                        isSearchingLocation: isSearchingLocation,
                        isLocationSelectionMode: isLocationSelectionMode,
                        onNodeSelected: { node in
                            selectedNode = node
                            showingSearchResults = false
                            focusOnNode(node)
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
    
    private var selectedNodeCard: some View {
        Group {
            if let selectedNode = selectedNode {
                NodeLocationCard(word: selectedNode) {
                    self.selectedNode = nil
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func handleLocationSelection(_ mapItem: MKMapItem) {
        if isLocationSelectionMode {
            let locationName = mapItem.name ?? "未知地点"
            let coordinate = mapItem.placemark.coordinate
            print("Selected location from search: \(locationName)")
            
            // 在位置选择模式下，先预览位置而不是直接选择
            showingSearchResults = false
            focusOnLocation(mapItem)
            
            // 设置选中位置以显示预览
            selectedLocation = coordinate
            selectedLocationName = locationName
            isPreviewingLocation = true
            
            print("🎯 Location selection mode: Previewing location \(locationName)")
        } else {
            // 在普通浏览模式下，点击搜索结果应该：
            // 1. 关闭搜索结果
            // 2. 聚焦到该位置
            // 3. 在地图上放置一个临时标记
            showingSearchResults = false
            focusOnLocation(mapItem)
            
            // 设置临时选中位置以显示3D大头针
            selectedLocation = mapItem.placemark.coordinate
            selectedLocationName = mapItem.name ?? "搜索位置"
            
            // 5秒后清除临时标记
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if !isLocationSelectionMode {
                    selectedLocation = nil
                    selectedLocationName = ""
                }
            }
        }
    }
    
    private var wordsWithLocationTags: [Node] {
        return store.nodes.filter { !$0.locationTags.isEmpty }
    }
    
    private var filteredNodesWithLocation: [Node] {
        let nodes = wordsWithLocationTags
        
        if searchQuery.isEmpty {
            return nodes
        }
        
        return nodes.filter { node in
            node.text.localizedCaseInsensitiveContains(searchQuery) ||
            node.meaning?.localizedCaseInsensitiveContains(searchQuery) == true ||
            node.locationTags.contains { tag in
                tag.value.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }
    
    private var locationAnnotations: [NodeLocationAnnotation] {
        return filteredNodesWithLocation.compactMap { word in
            guard let locationTag = word.locationTags.first,
                  let lat = locationTag.latitude,
                  let lng = locationTag.longitude else { return nil }
            
            return NodeLocationAnnotation(
                id: word.id,
                word: word,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                locationTag: locationTag
            )
        }
    }
    
    private func focusOnNode(_ word: Node) {
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
    
    private func convertScreenToMapCoordinate(screenPoint: CGPoint, mapSize: CGSize) -> CLLocationCoordinate2D {
        // Extract the current region from camera position
        var currentRegion: MKCoordinateRegion
        
        // For now, just use the stored region as fallback
        // TODO: Implement proper camera position extraction
        currentRegion = region
        
        // Calculate screen point relative to map center
        let centerX = mapSize.width / 2
        let centerY = mapSize.height / 2
        
        let offsetX = screenPoint.x - centerX
        let offsetY = screenPoint.y - centerY
        
        // Apply rotation transformation if map is rotated
        let rotatedOffsets = applyRotationTransform(
            offsetX: offsetX,
            offsetY: offsetY,
            heading: currentHeading
        )
        
        // Convert rotated offsets to geographic coordinates
        let longitudeOffset = Double(rotatedOffsets.x) * currentRegion.span.longitudeDelta / Double(mapSize.width)
        let latitudeOffset = -Double(rotatedOffsets.y) * currentRegion.span.latitudeDelta / Double(mapSize.height)
        
        let coordinate = CLLocationCoordinate2D(
            latitude: currentRegion.center.latitude + latitudeOffset,
            longitude: currentRegion.center.longitude + longitudeOffset
        )
        
        print("🎯 Manual conversion - Screen: \(screenPoint) -> Map: \(coordinate)")
        print("🎯 Rotation: \(currentHeading)°, Original offset: (\(offsetX), \(offsetY)), Rotated: (\(rotatedOffsets.x), \(rotatedOffsets.y))")
        print("🎯 Region center: \(currentRegion.center), span: \(currentRegion.span)")
        
        return coordinate
    }
    
    /// Applies rotation transformation to screen coordinates
    private func applyRotationTransform(offsetX: CGFloat, offsetY: CGFloat, heading: Double) -> CGPoint {
        // If no rotation, return original offsets
        guard abs(heading) > 0.1 else {
            return CGPoint(x: offsetX, y: offsetY)
        }
        
        // Convert heading to radians (negative because we need to reverse the rotation)
        let headingRadians = -heading * .pi / 180.0
        
        // Apply rotation matrix transformation
        let cos_theta = cos(headingRadians)
        let sin_theta = sin(headingRadians)
        
        let rotatedX = offsetX * cos_theta - offsetY * sin_theta
        let rotatedY = offsetX * sin_theta + offsetY * cos_theta
        
        return CGPoint(x: rotatedX, y: rotatedY)
    }
    
    /// Calculates coordinate region from camera parameters
    private func calculateRegionFromCamera(_ camera: MapCamera) -> MKCoordinateRegion {
        // More accurate calculation considering distance and pitch
        let distance = camera.distance
        let pitch = camera.pitch
        
        // Adjust for pitch - higher pitch shows less area
        let pitchFactor = cos(pitch * .pi / 180.0)
        let effectiveDistance = distance / pitchFactor
        
        // Convert distance to approximate coordinate span
        // These constants are empirically derived for reasonable accuracy
        let latitudeDelta = effectiveDistance / 111320.0 * 0.008
        let longitudeDelta = latitudeDelta / cos(camera.centerCoordinate.latitude * .pi / 180.0)
        
        return MKCoordinateRegion(
            center: camera.centerCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(latitudeDelta, 0.0001), // Minimum span to avoid zero values
                longitudeDelta: max(longitudeDelta, 0.0001)
            )
        )
    }
    
    private func reverseGeocodeLocation(coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
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
                    
                    let locationName = locationComponents.isEmpty ? 
                        "(\(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude)))" :
                        locationComponents.joined(separator: ", ")
                    
                    // 设置地名用于显示
                    self.selectedLocationName = locationName
                    print("✅ Location name: \(locationName)")
                } else {
                    let locationName = "(\(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude)))"
                    self.selectedLocationName = locationName
                    print("✅ Location name: \(locationName)")
                }
            }
        }
    }
    
    private func selectCurrentLocation() {
        let coordinate = region.center
        selectedLocation = coordinate
        selectedLocationName = "当前位置 (\(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude)))"
        print("Selected current location: \(selectedLocationName)")
    }
    
    private func confirmLocationSelection() {
        guard let coordinate = selectedLocation else { return }
        
        print("Confirming location selection with coordinates: \(coordinate.latitude), \(coordinate.longitude)")
        
        // 创建位置数据，如果有地名则包含地名信息
        var locationData: [String: Any] = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude
        ]
        
        // 如果有地名信息（来自搜索结果），则包含地名
        if !selectedLocationName.isEmpty && selectedLocationName != "选中位置" {
            locationData["name"] = selectedLocationName
            print("🎯 Confirming location with name: \(selectedLocationName)")
        }
        
        // 发送位置选择通知
        NotificationCenter.default.post(
            name: NSNotification.Name("locationSelected"),
            object: locationData
        )
        
        // 重置状态
        isLocationSelectionMode = false
        selectedLocation = nil
        selectedLocationName = ""
        isPreviewingLocation = false
        
        // 延迟关闭地图窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.keyWindow?.close()
        }
    }
    
    // MARK: - Map Node Navigation
    private func handleMapNodeTap(_ node: Node) {
        print("🗺️ MapContainer: 地图节点被点击: \(node.text)")
        
        // 1. 找到节点所属的层
        guard let targetLayer = store.layers.first(where: { $0.id == node.layerId }) else {
            print("⚠️ 未找到节点 '\(node.text)' 所属的层")
            return
        }
        
        print("🎯 目标层: \(targetLayer.displayName)")
        
        // 2. 🔧 修复：使用ID而不是对象，避免跨store实例的问题
        let userInfo: [String: Any] = [
            "targetNodeId": node.id.uuidString,
            "targetLayerId": targetLayer.id.uuidString,
            "targetNodeText": node.text, // 用于调试
            "targetLayerName": targetLayer.displayName // 用于调试
        ]
        
        // 🔧 关键修复：MapContainer作为中间层，根据sourceWindowId智能路由
        print("🔍 MapContainer (中间层): 开始智能路由 - sourceWindowId = \(sourceWindowId ?? "nil")")
        if let sid = sourceWindowId {
            print("🔍 MapContainer: 完整sourceWindowId = \(sid)")
        }
        
        if let sourceWindowId = sourceWindowId, !sourceWindowId.isEmpty {
            // 🔍 验证sourceWindowId是否为有效的UUID格式
            let isValidUUID = UUID(uuidString: sourceWindowId) != nil
            
            if isValidUUID {
                // 🎯 精确路由：直接发送到指定的源窗口
                var finalUserInfo = userInfo
                finalUserInfo["targetWindowId"] = sourceWindowId
                finalUserInfo["fromMapContainer"] = true
                finalUserInfo["routingMethod"] = "precise"
                
                print("🎯 MapContainer (中间层): 精确路由到源窗口 - \(String(sourceWindowId.prefix(8)))")
                print("✅ MapContainer: 已验证sourceWindowId为有效UUID格式")
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("handleMapPinTap"),
                    object: nil,
                    userInfo: finalUserInfo
                )
            } else {
                // 🔄 特殊处理：sourceWindowId不是UUID格式（如"MAIN_WINDOW"）
                print("⚠️ MapContainer: sourceWindowId非UUID格式 - \(sourceWindowId)")
                
                var finalUserInfo = userInfo
                finalUserInfo["targetWindowId"] = sourceWindowId
                finalUserInfo["fromMapContainer"] = true
                finalUserInfo["routingMethod"] = "special_id"
                
                print("🎯 MapContainer (中间层): 特殊ID路由 - \(sourceWindowId)")
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("handleMapPinTap"),
                    object: nil,
                    userInfo: finalUserInfo
                )
            }
        } else {
            // 🔄 回退路由：没有源窗口信息时的智能处理
            print("🔄 MapContainer (中间层): sourceWindowId为空，启用回退路由")
            
            // 尝试从WindowFocusManager获取当前活跃窗口 - 处理可能的nil值
            let currentActiveWindowId = WindowFocusManager.shared.getActiveWindowId()
            let activeWindowIdString = currentActiveWindowId?.uuidString ?? "unknown"
            print("🔍 MapContainer: 当前活跃窗口ID = \(String(activeWindowIdString.prefix(8)))")
            
            // 🔧 修复：只使用短ID，确保窗口ID格式一致
            let shortActiveWindowId = String(activeWindowIdString.prefix(8))
            
            var finalUserInfo = userInfo
            finalUserInfo["targetWindowId"] = shortActiveWindowId
            finalUserInfo["fromMapContainer"] = true
            finalUserInfo["routingMethod"] = "fallback"
            
            print("🎯 MapContainer (中间层): 回退路由到活跃窗口 - \(String(activeWindowIdString.prefix(8)))")
            
            NotificationCenter.default.post(
                name: NSNotification.Name("handleMapPinTap"),
                object: nil,
                userInfo: finalUserInfo
            )
        }
        
        print("✅ MapContainer (中间层): 路由完成")
        print("📋 通知内容: 节点=\(node.text), 层=\(targetLayer.displayName)")
    }
}

// MARK: - NodeLocationAnnotation

struct NodeLocationAnnotation: Identifiable {
    let id: UUID
    let word: Node
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
    let annotation: NodeLocationAnnotation
    let onTap: () -> Void
    
    private var markerColor: Color {
        if annotation.word.isCompound {
            return Color.purple.opacity(0.8)
        } else if let firstTag = annotation.word.tags.first {
            return Color.from(tagType: firstTag.type)
        }
        return .blue
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                VStack(spacing: 2) {
                    // 圆形标记显示首字符
                    ZStack {
                        Circle()
                            .fill(markerColor)
                            .frame(width: 32, height: 32)
                            .shadow(radius: 4)
                        
                        Text(String(annotation.locationTag.value.prefix(1)))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    // 下方显示完整地点名称
                    Text(annotation.locationTag.value)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.ultraThinMaterial)
                                .shadow(radius: 2)
                        )
                        .lineLimit(1)
                }
                
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Map Controls

struct MapControlsView: View {
    @Binding var region: MKCoordinateRegion
    @Binding var cameraPosition: MapCameraPosition
    let wordsWithLocation: [Node]
    
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

// MARK: - Node Location Card

struct NodeLocationCard: View {
    let word: Node
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
                            
                            Text(tag.displayName)
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
                    Text("其他标签 (\(otherTags.count))")
                        .font(.headline)
                    
                    // 标签详细显示已删除，标签信息在图谱中展示
                    if !otherTags.isEmpty {
                        Text("标签: \(otherTags.map { $0.value }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
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
    let nodes: [Node]
    let geoResults: [MKMapItem]
    let isSearchingLocation: Bool
    let isLocationSelectionMode: Bool
    let onNodeSelected: (Node) -> Void
    let onLocationSelected: (MKMapItem) -> Void
    
    private var nodeResults: [Node] {
        if query.isEmpty {
            return []
        }
        
        return nodes.filter { node in
            node.text.localizedCaseInsensitiveContains(query) ||
            node.meaning?.localizedCaseInsensitiveContains(query) == true ||
            node.tags.contains { tag in
                tag.value.localizedCaseInsensitiveContains(query)
            }
        }.prefix(3).map { $0 }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 单词搜索结果
            if !nodeResults.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("单词结果")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(nodeResults.count) 个")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    LazyVStack(spacing: 0) {
                        ForEach(nodeResults, id: \.id) { word in
                            MapSearchResultRow(word: word) {
                                onNodeSelected(word)
                            }
                            
                            if word.id != nodeResults.last?.id {
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
    let word: Node
    let onTap: () -> Void
    
    var body: some View {
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
                        
                        Text(word.locationTags.first?.displayName ?? "")
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
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

struct LocationSearchResultRow: View {
    let mapItem: MKMapItem
    let isLocationSelectionMode: Bool
    let onTap: () -> Void
    
    var body: some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
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
            // 苹果地图标准大头针设计
            ZStack {
                // 阴影
                Circle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 36, height: 36)
                    .offset(x: 1, y: 3)
                
                // 主体圆形 - 苹果标准红色
                Circle()
                    .fill(Color(red: 1.0, green: 0.23, blue: 0.19)) // #FF3B30
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // 内部位置图标
                Image(systemName: "location.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .medium))
            }
            
            // 三角形指针
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: -6, y: 12))
                path.addLine(to: CGPoint(x: 6, y: 12))
                path.closeSubpath()
            }
            .fill(Color(red: 1.0, green: 0.23, blue: 0.19)) // #FF3B30
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: -6, y: 12))
                    path.addLine(to: CGPoint(x: 6, y: 12))
                    path.closeSubpath()
                }
                .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .offset(y: -2)
        }
        .onTapGesture {
            onTap()
        }
        .animation(.easeInOut(duration: 0.2), value: true)
    }
}

// MARK: - Premium 3D Pin View

struct Premium3DPinView: View {
    var body: some View {
        // 创建自定义图标 - 仿你的SVG设计
        ZStack {
            // 主体圆形
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.red.opacity(0.9), Color.red.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            
            // 中心点
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
        }
        .onAppear { print("✅ 使用自定义大头针图标 - 基于你的SVG设计") }
    }
}

// MARK: - Search Location Pin View

struct SearchLocationPinView: View {
    @State private var pulseScale: Double = 1.0
    
    var body: some View {
        ZStack {
            // 脉冲动画圆圈
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 50, height: 50)
                .scaleEffect(pulseScale)
                .animation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                    value: pulseScale
                )
            
            // 主体圆形 - 蓝色搜索标记
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.9), Color.blue.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            
            // 搜索图标
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white)
                .font(.system(size: 12, weight: .medium))
        }
        .onAppear {
            pulseScale = 1.3
        }
    }
}



#Preview {
    MapContainer(isLocationSelectionMode: .constant(false), sourceWindowId: nil)
        .environmentObject(NodeStore.shared)
}