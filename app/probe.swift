import Foundation

// Validation probe: mimics what the app's networking layer will do via URLSession.
// Reads sessionKey from env (SK) so it never lands in source or shell history echo.

let sk = ProcessInfo.processInfo.environment["SK"] ?? ""
guard !sk.isEmpty else { fputs("missing SK env\n", stderr); exit(2) }

func req(_ url: String) -> URLRequest {
    var r = URLRequest(url: URL(string: url)!)
    r.httpMethod = "GET"
    r.setValue("sessionKey=\(sk)", forHTTPHeaderField: "Cookie")
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    r.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
               forHTTPHeaderField: "User-Agent")
    r.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
    r.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
    r.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
    r.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
    r.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
    return r
}

func get(_ url: String) async -> (Int, Data) {
    do {
        let (data, resp) = try await URLSession.shared.data(for: req(url))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        return (code, data)
    } catch {
        fputs("error: \(error)\n", stderr); return (-1, Data())
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    let (oc, od) = await get("https://claude.ai/api/organizations")
    print("[orgs http=\(oc) bytes=\(od.count)]")
    let body = String(data: od, encoding: .utf8) ?? ""
    if oc != 200 { print(String(body.prefix(300))); sem.signal(); return }
    guard let arr = try? JSONSerialization.jsonObject(with: od) as? [[String: Any]] else {
        print("orgs not array: \(String(body.prefix(300)))"); sem.signal(); return
    }
    // Same pick as UsageClient.firstOrg: first org with "chat", else the first.
    let picked = (arr.first { ($0["capabilities"] as? [String])?.contains("chat") == true } ?? arr.first)?["uuid"] as? String
    // Dump usage for every org so payloads from different plans can be compared.
    for org in arr {
        guard let uuid = org["uuid"] as? String else { continue }
        let mark = uuid == picked ? "  <- app uses this org" : ""
        print("\n=== org \(uuid) raven_type=\(org["raven_type"] ?? "nil") capabilities=\(org["capabilities"] ?? "nil")\(mark)")
        let (uc, ud) = await get("https://claude.ai/api/organizations/\(uuid)/usage")
        print("[usage http=\(uc) bytes=\(ud.count)]")
        if let obj = try? JSONSerialization.jsonObject(with: ud),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            print(String(data: pretty, encoding: .utf8) ?? "")
        } else {
            print(String(String(data: ud, encoding: .utf8)?.prefix(300) ?? ""))
        }
    }
    sem.signal()
}
sem.wait()
