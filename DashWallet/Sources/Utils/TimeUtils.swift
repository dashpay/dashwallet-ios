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
            connection.send(content: message, completion: .contentProcessed({ error in
                if let error = error {
                    print("Error sending NTP request: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                connection.receive(minimumIncompleteLength: 48, maximumLength: 48) { content, _, _, error in
                    defer { connection.cancel() }
                    
                    if let error = error {
                        print("Error receiving NTP response: \(error)")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    guard let message = content else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Timestamp starts at byte 40 of the received packet and is four bytes,
                    // or two words, long. First byte is the high-order byte of the integer;
                    // the last byte is the low-order byte. The high word is the seconds field,
                    // and the low word is the fractional field.
                    let seconds = Int64(message[40]) << 24 |
                        Int64(message[41]) << 16 |
                        Int64(message[42]) << 8 |
                        Int64(message[43])
                    
                    let result = (seconds - 2_208_988_800) * 1000
                    continuation.resume(returning: result)
                }
            }))
        }
    }

    static func getTimeSkew(force: Bool = false) async throws -> TimeInterval {
        let currentTimeMillis = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Check if we can use the cached skew
        if !force && (lastTimeWhenSkewChecked + 60_000 > currentTimeMillis) {
            print("[SW] CoinJoin: timeskew: \(lastTimeSkew); using last value")
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
                    // Log the error and try the next URL
                    print("[SW] CoinJoin: Error fetching HTTP date from \(url): \(error)")
                }
            }
            
            print("[SW] CoinJoin: timeskew: network time is \(String(describing: networkTime))")
            guard networkTime != nil else {
                throw NSError(domain: "TimeUtils", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get network time"])
            }
        }
        
        // Calculate the new time skew
        let newSkew = TimeInterval((currentTimeMillis - networkTime!) / 1000)
        
        // Update the cache
        lastTimeWhenSkewChecked = currentTimeMillis
        lastTimeSkew = newSkew
        
        print("[SW] CoinJoin: timeskew: \(currentTimeMillis)-\(networkTime!) = \(newSkew) s; source: \(timeSource)")
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
