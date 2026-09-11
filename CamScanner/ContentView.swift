import SwiftUI
import Network
import WebKit

// Model lưu thông tin thiết bị và danh sách port mở
struct ScannedHost: Identifiable {
    let id = UUID()
    let ip: String
    var openPorts: [Int] = []
    var isWebAccessible: Bool {
        return openPorts.contains(80) || openPorts.contains(443) || openPorts.contains(8080) || openPorts.contains(8888)
    }
}

// Danh mục định danh cổng
struct PortService {
    static func getName(for port: Int) -> String {
        switch port {
        case 80: return "HTTP (Web)"
        case 443: return "HTTPS"
        case 8080: return "Web Admin (8080)"
        case 8888: return "Web Admin (8888)"
        case 554: return "RTSP (Video)"
        case 8000: return "Hikvision"
        case 37777: return "Dahua/EZ-IP"
        case 22: return "SSH"
        case 23: return "Telnet"
        case 3389: return "RDP"
        default: return "Port \(port)"
        }
    }
}

struct ContentView: View {
    @State private var subnet: String = "192.168.1."
    @State private var scannedDevices: [ScannedHost] = []
    @State private var isScanning: Bool = false
    @State private var progressText: String = "Sẵn sàng quét mạng"
    
    // Quản lý hiển thị WebView nhúng
    @State private var selectedWebURL: URL? = nil
    @State private var showWebView: Bool = false
    
    // Các port cần quét
    private let targetPorts: [Int] = [80, 443, 8080, 8888, 554, 8000, 37777, 22, 23, 3389]

    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                // Header
                VStack(spacing: 4) {
                    Text("NETWORK & CAMERA SCANNER")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Designed by Nguyen Tuan Anh • Tuan Anh Lab")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Input & Action
                HStack {
                    TextField("Dải mạng (ví dụ: 192.168.1.)", text: $subnet)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numbersAndPunctuation)
                        .disableAutocorrection(true)

                    Button(action: {
                        hideKeyboard()
                        startScan()
                    }) {
                        if isScanning {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.gray)
                                .cornerRadius(8)
                        } else {
                            Text("Quét")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    }
                    .disabled(isScanning)
                }
                .padding(.horizontal)

                // Status bar
                HStack {
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Tìm thấy: \(scannedDevices.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)

                // Device List
                List(scannedDevices) { host in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: host.isWebAccessible ? "network" : "desktopcomputer")
                                .foregroundColor(host.isWebAccessible ? .green : .blue)
                            Text(host.ip)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                            Spacer()
                            
                            // Nút truy cập web nhanh nếu có port web
                            if host.isWebAccessible {
                                Button(action: {
                                    openWebAdmin(for: host)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "safari")
                                        Text("Web UI")
                                    }
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        // Danh sách badge port mở
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(host.openPorts, id: \.self) { port in
                                    Text("\(port) - \(PortService.getName(for: port))")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(badgeColor(for: port).opacity(0.15))
                                        .foregroundColor(badgeColor(for: port))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationBarHidden(true)
            .onTapGesture {
                hideKeyboard()
            }
            // Sheet hiển thị giao diện Web nhúng
            .sheet(isPresented: $showWebView) {
                if let url = selectedWebURL {
                    SafariWebViewModal(url: url)
                }
            }
        }
    }

    // MARK: - Quét mạng
    private func startScan() {
        guard !subnet.isEmpty else { return }
        isScanning = true
        scannedDevices.removeAll()
        progressText = "Đang quét các thiết bị và cổng dịch vụ..."

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "cam.scanner.queue", attributes: .concurrent)

        for i in 1...254 {
            let ip = "\(subnet)\(i)"
            group.enter()
            queue.async {
                self.scanHost(ip: ip) { host in
                    if let host = host {
                        DispatchQueue.main.async {
                            self.scannedDevices.append(host)
                        }
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.isScanning = false
            self.progressText = "Hoàn tất! Tìm thấy \(self.scannedDevices.count) thiết bị."
        }
    }

    private func scanHost(ip: String, completion: @escaping (ScannedHost?) -> Void) {
        let portGroup = DispatchGroup()
        var discoveredPorts: [Int] = []
        let portLock = NSLock()

        for port in targetPorts {
            portGroup.enter()
            checkPort(ip: ip, port: port) { isOpen in
                if isOpen {
                    portLock.lock()
                    discoveredPorts.append(port)
                    portLock.unlock()
                }
                portGroup.leave()
            }
        }

        portGroup.notify(queue: .global()) {
            if !discoveredPorts.isEmpty {
                discoveredPorts.sort()
                completion(ScannedHost(ip: ip, openPorts: discoveredPorts))
            } else {
                completion(nil)
            }
        }
    }

    private func checkPort(ip: String, port: Int, completion: @escaping (Bool) -> Void) {
        let hostEndpoint = NWEndpoint.Host(ip)
        guard let portEndpoint = NWEndpoint.Port(rawValue: UInt16(port)) else {
            completion(false)
            return
        }

        let connection = NWConnection(host: hostEndpoint, port: portEndpoint, using: .tcp)
        let queue = DispatchQueue(label: "port.check.\(ip).\(port)")
        var isResolved = false

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !isResolved {
                    isResolved = true
                    connection.cancel()
                    completion(true)
                }
            case .failed(_), .waiting(_):
                if !isResolved {
                    isResolved = true
                    connection.cancel()
                    completion(false)
                }
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Timeout 1.2s cho mỗi cổng để tối ưu tốc độ
        queue.asyncAfter(deadline: .now() + 1.2) {
            if !isResolved {
                isResolved = true
                connection.cancel()
                completion(false)
            }
        }
    }

    // MARK: - Tiện ích
    private func openWebAdmin(for host: ScannedHost) {
        let port = host.openPorts.first(where: { [80, 443, 8080, 8888].contains($0) }) ?? 80
        let scheme = (port == 443) ? "https" : "http"
        let urlString = (port == 80 || port == 443) ? "\(scheme)://\(host.ip)" : "\(scheme)://\(host.ip):\(port)"
        
        if let url = URL(string: urlString) {
            self.selectedWebURL = url
            self.showWebView = true
        }
    }

    private func badgeColor(for port: Int) -> Color {
        switch port {
        case 80, 443, 8080, 8888: return .blue
        case 554, 8000, 37777: return .orange
        case 22, 23, 3389: return .purple
        default: return .gray
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// Modal mở Web View ngay trong ứng dụng
struct SafariWebViewModal: View {
    let url: URL
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            WebViewContainer(url: url)
                .navigationBarTitle(Text(url.absoluteString), displayMode: .inline)
                .navigationBarItems(trailing: Button("Đóng") {
                    presentationMode.wrappedValue.dismiss()
                })
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
}