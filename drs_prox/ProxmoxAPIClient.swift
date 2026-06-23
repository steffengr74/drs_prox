import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige URL"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .decodingError(let msg): return "Dekodierungsfehler: \(msg)"
        }
    }
}

struct TaskResult {
    let status: String
    let exitStatus: String?

    var isFinished: Bool { status == "stopped" }
    var isSuccess: Bool { exitStatus == "OK" }
}

private final class SSLBypassDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

final class ProxmoxAPIClient {
    private let settings: ProxmoxSettings
    private let session: URLSession

    init(settings: ProxmoxSettings) {
        self.settings = settings
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        if settings.verifyCertificate {
            self.session = URLSession(configuration: config)
        } else {
            self.session = URLSession(configuration: config, delegate: SSLBypassDelegate(), delegateQueue: nil)
        }
    }

    private func makeRequest(path: String, method: String = "GET", formParams: [String: String]? = nil) throws -> URLRequest {
        guard let url = URL(string: settings.baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("PVEAPIToken=\(settings.tokenID)=\(settings.tokenSecret)", forHTTPHeaderField: "Authorization")
        if let params = formParams {
            request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpError(0, "Keine HTTP-Antwort")
        }
        guard 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
            throw APIError.httpError(http.statusCode, msg)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    func fetchNodes() async throws -> [ProxmoxNode] {
        let req = try makeRequest(path: "/nodes")
        let res: PVEResponse<[NodeDTO]> = try await perform(req)
        var nodes = res.data.map { dto in
            ProxmoxNode(
                id: dto.node,
                name: dto.node,
                status: dto.status,
                cpuUsage: dto.cpu ?? 0,
                maxCPU: dto.maxcpu ?? 1,
                memTotal: dto.maxmem ?? 0,
                memUsed: dto.mem ?? 0,
                uptime: dto.uptime ?? 0
            )
        }
        
        // Fetch network interfaces for each online node
        for i in nodes.indices where nodes[i].isOnline {
            if let interfaces = try? await fetchNetworkInterfaces(node: nodes[i].name) {
                nodes[i].networkInterfaces = interfaces
            }
        }
        
        return nodes
    }
    
    func fetchNetworkInterfaces(node: String) async throws -> [NetworkInterface] {
        // First, get the list of network interfaces from the network config
        let netReq = try makeRequest(path: "/nodes/\(node)/network")
        
        let (data, response) = try await session.data(for: netReq)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpError(0, "Keine HTTP-Antwort")
        }
        guard 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
            throw APIError.httpError(http.statusCode, msg)
        }
        
        // Try to parse as flexible JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return []
        }
        
        var interfaces: [NetworkInterface] = []

        // First pass: build a map of bond -> slave-list so we can attribute slaves to their master.
        var slavesByBond: [String: [String]] = [:]
        var masterBySlave: [String: String] = [:]
        for item in dataArray {
            guard let iface = item["iface"] as? String,
                  (item["type"] as? String) == "bond" else { continue }
            let raw = (item["slaves"] as? String) ?? (item["bond_slaves"] as? String) ?? ""
            let slaves = raw.split(whereSeparator: { $0 == " " || $0 == "," })
                .map(String.init)
                .filter { !$0.isEmpty }
            slavesByBond[iface] = slaves
            for s in slaves { masterBySlave[s] = iface }
        }

        // Manually parse each interface config
        for item in dataArray {
            guard let iface = item["iface"] as? String else { continue }

            // Accept physical NICs (en*, eth*, nic*) and bonds
            let isPhysical = (iface.hasPrefix("en") || iface.hasPrefix("eth") || iface.hasPrefix("nic"))
                && !iface.hasPrefix("veth")
            let isBond = iface.hasPrefix("bond")
            guard isPhysical || isBond else { continue }

            let type = item["type"] as? String
            guard type != "bridge" else { continue }

            let active = (item["active"] as? Int == 1) || (item["active"] as? Bool == true)
            let speed = item["speed"] as? Int64
            let kind: NetworkInterface.Kind = isBond ? .bond : .physical
            let slaves = slavesByBond[iface] ?? []
            let bondMaster = masterBySlave[iface]
            
            // Get RRD data for this interface
            do {
                let rrdReq = try makeRequest(path: "/nodes/\(node)/rrddata?timeframe=hour&cf=AVERAGE")
                let (rrdData, rrdResponse) = try await session.data(for: rrdReq)
                
                guard let rrdHttp = rrdResponse as? HTTPURLResponse, 200..<300 ~= rrdHttp.statusCode else {
                    throw APIError.httpError(0, "RRD request failed")
                }
                
                guard let rrdJson = try? JSONSerialization.jsonObject(with: rrdData) as? [String: Any],
                      let rrdArray = rrdJson["data"] as? [[String: Any]],
                      let latest = rrdArray.last else {
                    throw APIError.decodingError("No RRD data")
                }
                
                // Look for interface-specific keys first (e.g., "netin:bond0")
                let netinKey = "netin:\(iface)"
                let netoutKey = "netout:\(iface)"
                
                var rxBytes = (latest[netinKey] as? Double) ?? 0
                var txBytes = (latest[netoutKey] as? Double) ?? 0
                
                // If interface-specific keys don't exist, use the generic netin/netout
                if rxBytes == 0 && txBytes == 0 {
                    // For bonds, use the total network traffic
                    rxBytes = (latest["netin"] as? Double) ?? 0
                    txBytes = (latest["netout"] as? Double) ?? 0
                    
                    // If we have multiple interfaces, divide by the count for approximation
                    let interfaceCount = dataArray.filter { item in
                        guard let ifaceName = item["iface"] as? String else { return false }
                        return (ifaceName.hasPrefix("en") || ifaceName.hasPrefix("eth") || ifaceName.hasPrefix("bond")) &&
                               !ifaceName.hasPrefix("veth") &&
                               (item["type"] as? String) != "bridge"
                    }.count
                    
                    if interfaceCount > 1 {
                        rxBytes = rxBytes / Double(interfaceCount)
                        txBytes = txBytes / Double(interfaceCount)
                    }
                }
                
                interfaces.append(NetworkInterface(
                    id: iface,
                    name: iface,
                    rxBytes: Int64(rxBytes),
                    txBytes: Int64(txBytes),
                    speed: speed,
                    isActive: active,
                    kind: kind,
                    slaves: slaves,
                    bondMaster: bondMaster
                ))

            } catch {
                // If RRD fetch fails, add interface with zero stats
                interfaces.append(NetworkInterface(
                    id: iface,
                    name: iface,
                    rxBytes: 0,
                    txBytes: 0,
                    speed: speed,
                    isActive: active,
                    kind: kind,
                    slaves: slaves,
                    bondMaster: bondMaster
                ))
            }
        }
        
        return interfaces.sorted { $0.name < $1.name }
    }
    
    func fetchVMs(on node: String) async throws -> [ProxmoxVM] {
        let req = try makeRequest(path: "/nodes/\(node)/qemu")
        let res: PVEResponse<[VMDTO]> = try await perform(req)
        return res.data.map { dto in
            ProxmoxVM(
                id: dto.vmid,
                name: dto.name ?? "",
                status: dto.status,
                node: node,
                cpuUsage: dto.cpu ?? 0,
                maxCPU: dto.cpus ?? 1,
                memUsed: dto.mem ?? 0,
                maxMem: dto.maxmem ?? 0,
                uptime: dto.uptime ?? 0
            )
        }
    }

    func migrateVM(vmid: Int, fromNode: String, toNode: String) async throws -> String {
        let req = try makeRequest(
            path: "/nodes/\(fromNode)/qemu/\(vmid)/migrate",
            method: "POST",
            formParams: ["target": toNode, "online": "1"]
        )
        let res: PVEResponse<String> = try await perform(req)
        return res.data
    }

    func fetchTaskStatus(node: String, upid: String) async throws -> TaskResult {
        // Colons in UPID must be percent-encoded for use as a URL path segment
        var charset = CharacterSet.urlPathAllowed
        charset.remove(charactersIn: ":")
        let encoded = upid.addingPercentEncoding(withAllowedCharacters: charset) ?? upid
        let req = try makeRequest(path: "/nodes/\(node)/tasks/\(encoded)/status")
        let res: PVEResponse<TaskStatusDTO> = try await perform(req)
        return TaskResult(status: res.data.status, exitStatus: res.data.exitstatus)
    }

    // Returns number of available package updates for the node
    func fetchUpdateCount(node: String) async throws -> Int {
        let req = try makeRequest(path: "/nodes/\(node)/apt/update")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            return 0
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [Any] else { return 0 }
        return arr.count
    }

    // Runs apt-get dist-upgrade on the node and returns the task UPID
    func installUpdates(node: String) async throws -> String {
        let req = try makeRequest(
            path: "/nodes/\(node)/apt/update",
            method: "POST",
            formParams: ["upgrade": "1", "notify": "0"]
        )
        let res: PVEResponse<String> = try await perform(req)
        return res.data
    }

    // Returns true if the node requires a reboot after installed updates
    func fetchRebootRequired(node: String) async throws -> Bool {
        let req = try makeRequest(path: "/nodes/\(node)/reboot-required")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            return false
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let val = json["data"] as? Int  { return val != 0 }
        if let val = json["data"] as? Bool { return val }
        return false
    }
}

// MARK: - DTOs

private struct PVEResponse<T: Decodable>: Decodable {
    let data: T
}

private struct NodeDTO: Decodable {
    let node: String
    let status: String
    let cpu: Double?
    let maxcpu: Int?
    let mem: Int64?
    let maxmem: Int64?
    let uptime: Int?
}

private struct VMDTO: Decodable {
    let vmid: Int
    let name: String?
    let status: String
    let cpu: Double?
    let cpus: Int?
    let mem: Int64?
    let maxmem: Int64?
    let uptime: Int?
}

private struct TaskStatusDTO: Decodable {
    let status: String
    let exitstatus: String?
}

private struct NodeStatusDTO: Decodable {
    let netin: [String: Double]?
    let netout: [String: Double]?
}

private struct NetworkConfigDTO: Decodable {
    let iface: String?
    let type: String?
    let active: Bool?
    let speed: Int64?
    let address: String?
    let netmask: String?
    let gateway: String?
}

private struct NetworkInterfaceDetailDTO: Decodable {
    let speed: Int64?
}

