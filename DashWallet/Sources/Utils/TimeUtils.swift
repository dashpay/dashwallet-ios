import Foundation
import Network

class TimeUtils {
    private static var lastTimeWhenSkewChecked: Int64 = 0
    private static var lastTimeSkew: TimeInterval = 0
    
    private static func queryNtpTime(server: String) async -> Int64? {
        let message = Data([0b00100011] + [UInt8](repeating: 0, count: 47))
        
        let connection = NWConnection(to: .hostPort(host: .name(server, nil), port: 123), using: .udp)
        connection.stateUpdateHandler = { _ in }
        connection.start(queue: .global())
        
        return await withCheckedContinuation { continuation in
            var didResume = false
            
            // A helper function so that we only resume once.
            func safeResume(with result: Int64?) {
                // Ensure that resume is only called once.
                if !didResume {
                    didResume = true
                    continuation.resume(returning: result)
                }
            }
            
            let timeout = DispatchTime.now() + .seconds(5)
            
            let timeoutWorkItem = DispatchWorkItem {
                connection.cancel()
                safeResume(with: nil)
            }
            DispatchQueue.global().asyncAfter(deadline: timeout, execute: timeoutWorkItem)
            
            connection.send(content: message, completion: .contentProcessed({ error in
                if error != nil {
                    connection.cancel()
                    timeoutWorkItem.cancel()
                    safeResume(with: nil)
                    return
                }
                
                connection.receive(minimumIncompleteLength: 48, maximumLength: 48) { content, _, _, error in
                    defer {
                        connection.cancel()
                        timeoutWorkItem.cancel()
                    }
                    
                    if error != nil {
                        safeResume(with: nil)
                        return
                    }
                    
                    guard let message = content else {
                        safeResume(with: nil)
                        return
                    }
                    
                    // Parse the NTP response.
                    let seconds = Int64(message[40]) << 24 |
                        Int64(message[41]) << 16 |
                        Int64(message[42]) << 8 |
                        Int64(message[43])
                    
                    let result = (seconds - 2_208_988_800) * 1000
                    safeResume(with: result)
                    timeoutWorkItem.cancel()
                }
            }))
        }
    }

    static func getTimeSkew(force: Bool = false) async throws -> TimeInterval {
        let currentTimeMillis = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Check if we can use the cached skew
        if !force && (lastTimeWhenSkewChecked + 60_000 > currentTimeMillis) {
            return lastTimeSkew
        }
        
        var networkTime: Int64?
        var timeSource = "NTP"
        
        // Attempt multiple NTP queries
        var networkTimes: [Int64] = []
        for _ in 0..<4 {
            if let time = await queryNtpTime(server: "pool.ntp.org"), time > 0 {
                networkTimes.append(time)
            }
        }
    
        if networkTimes.count > 1 {
            let sortedTimes = networkTimes.sorted()
            let middleIndex = sortedTimes.count / 2
            
            if sortedTimes.count % 2 == 0 {
                networkTime = (sortedTimes[middleIndex - 1] + sortedTimes[middleIndex]) / 2
            } else {
                networkTime = sortedTimes[middleIndex]
            }
        }
        
        // Fallback to HTTP Date headers if NTP fails
        if networkTime == nil {
            let urls = ["https://www.dash.org/", "https://insight.dash.org/insight"]
            for url in urls {
                do {
                    let (_, response) = try await URLSession.shared.data(from: URL(string: url)!)
                    if let httpResponse = response as? HTTPURLResponse,
                       let dateString = httpResponse.allHeaderFields["Date"] as? String,
                       let networkDate = DateFormatter.rfc1123.date(from: dateString) {
                        networkTime = Int64(networkDate.timeIntervalSince1970 * 1000)
                        timeSource = url
                        break
                    }
                } catch {
                    // ignore
                }
            }
            
            guard networkTime != nil else {
                throw NSError(domain: "TimeUtils", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get network time"])
            }
        }
        
        // Calculate the new time skew
        let newSkew = TimeInterval((currentTimeMillis - networkTime!) / 1000)
        
        // Update the cache
        lastTimeWhenSkewChecked = currentTimeMillis
        lastTimeSkew = newSkew
        
        print("CoinJoin: timeskew: \(currentTimeMillis)-\(networkTime!) = \(newSkew) s; source: \(timeSource)")
        return newSkew
    }
}

extension DateFormatter {
    static let rfc1123: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        return formatter
    }()
}
