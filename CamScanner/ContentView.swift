import SwiftUI
import Network

struct ScanResult: Identifiable {
    let id = UUID()
    let ip: String
    let port: UInt16
    let service: String
}

struct ContentView: View {
    @State private var subnet: String = "192.168.1."
    @State private var results: [ScanResult] = []
    @State private var isScanning: Bool = false
    @State private var progressText: String = "Sẵn sàng quét"

    let targetPorts: [UInt16: String] = [
        80: "Web Admin",
        445: "Windows SMB",
        554: "RTSP Camera",
        8000: "Hikvision / Ezviz",
        37777: "Dahua / Imou",
        62078: "Apple Sync"
    ]

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("IP CAMERA SCANNER")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                Text("Designed by Nguyen Tuan Anh • Tuan Anh Lab")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.top, 10)

            HStack {
                TextField("Dải IP (VD: 192.168.1.)", text: $subnet)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numbersAndPunctuation)

                Button(action: startScan) {
                    Text(isScanning ? "Đang quét..." : "Quét")
                        .bold()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isScanning ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(isScanning)
            }
            .padding(.horizontal)

            HStack {
                Text(progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Tìm thấy: \(results.count)")
                    .font(.caption)
                    .bold()
            }
            .padding(.horizontal)

            List(results) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.ip)
                            .font(.headline)
                        Text("Port: \(item.port)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(item.service)
                        .font(.caption)
                        .padding(6)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }
            }
            .listStyle(PlainListStyle())
        }
    }

    func startScan() {
        isScanning = true
        results.removeAll()
        progressText = "Đang quét dải \(subnet)0/24..."

        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            for i in 1...254 {
                let ip = "\(subnet)\(i)"
                for (port, name) in targetPorts {
                    group.enter()
                    checkPort(ip: ip, port: port, service: name) {
                        group.leave()
                    }
                }
            }
            group.wait()
            DispatchQueue.main.async {
                isScanning = false
                progressText = "Hoàn tất quét mạng!"
            }
        }
    }

    func checkPort(ip: String, port: UInt16, service: String, completion: @escaping () -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { completion(); return }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
        var finished = false

        conn.stateUpdateHandler = { state in
            if case .ready = state {
                if !finished {
                    finished = true
                    DispatchQueue.main.async {
                        results.append(ScanResult(ip: ip, port: port, service: service))
                    }
                    conn.cancel()
                    completion()
                }
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if !finished {
                finished = true
                conn.cancel()
                completion()
            }
        }
    }
}