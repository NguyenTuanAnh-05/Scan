import SwiftUI
import Network

struct ScannedHost: Identifiable {
    let id = UUID()
    let ip: String
    var openPorts: [Int] = []
    var webURL: URL? {
        let port = openPorts.first(where: { [80, 443, 8080, 8888].contains($0) }) ?? 80
        let scheme = (port == 443) ? "https" : "http"
        let urlStr = (port == 80 || port == 443) ? "\(scheme)://\(ip)" : "\(scheme)://\(ip):\(port)"
        return URL(string: urlStr)
    }
}

struct PortService {
    static func getName(for port: Int) -> String {
        switch port {
        case 80: return "HTTP"
        case 443: return "HTTPS"
        case 8080: return "Web 8080"
        case 8888: return "Web 8888"
        case 554: return "RTSP"
        case 8000: return "Hikvision"
        case 37777: return "Dahua"
        case 22: return "SSH"
        case 23: return "Telnet"
        case 3389: return "RDP"
        default: return "\(port)"
        }
    }
}

struct ContentView: View {
    @Environment(\.openURL) var openURL
    @State private var subnet: String = "192.168.1."
    @State private var scannedDevices: [ScannedHost] = []
    @State private var isScanning: Bool = false
    @State private var progressText: String = "Sẵn sàng quét mạng"
    
    private let targetPorts: [Int] = [80, 443, 8080, 8888, 554, 8000, 37777, 22, 23, 3389]

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("NETWORK & CAMERA SCANNER")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.blue)
                Text("Designed by Nguyen Tuan Anh • Tuan Anh Lab")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)

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
                            .font(.system(.body, design: .default).weight(.semibold))
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

            HStack {
                Text(progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Tìm thấy: \(scannedDevices.count)")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.blue)
            }
            .padding(.horizontal)

            List(scannedDevices) { host in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: host.webURL != nil ? "network" : "desktopcomputer")
                            .foregroundColor(host.webURL != nil ? .green : .blue)
                        Text(host.ip)
                            .font(.system(.body, design: .monospaced))
                            .bold()
                        Spacer()
                        
                        if let url = host.webURL {
                            Button(action: {
                                openURL(url)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("Web Admin")
                                }
                                .font(.caption)
                                .bold()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(host.openPorts, id: \.self) { port in
                                Text("\(port) - \(PortService.getName(for: port))")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(badgeColor(for: port).opacity(0.15))
                                    .foregroundColor(badgeColor(for: port))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(PlainListStyle())
        }
        .onTapGesture {
            hideKeyboard()
        }
    }

    private func startScan() {
        guard !subnet.isEmpty else { return }
        isScanning = true
        scannedDevices.removeAll()
        progressText = "Đang quét..."

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "cam.scan.queue", attributes: .concurrent)

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
        let queue = DispatchQueue(label: "port.\(ip).\(port)")
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

        queue.asyncAfter(deadline: .now() + 1.0) {
            if !isResolved {
                isResolved = true
                connection.cancel()
                completion(false)
            }
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