import Darwin
import Foundation

/// This device's own addresses, for the quick IP picker in Settings.
enum NetworkInfo {
    enum Kind {
        case wifi, hotspot
    }

    struct Address: Hashable {
        let ip: String
        let kind: Kind
    }

    /// IPv4 addresses other devices could reach the proxy on: Wi-Fi (en0)
    /// and the Personal Hotspot bridge. Cellular isn't listed — nothing on
    /// the carrier side can connect in.
    static func localIPv4() -> [Address] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [Address] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let name = String(cString: ifa.ifa_name)
            let kind: Kind
            if name == "en0" {
                kind = .wifi
            } else if name.hasPrefix("bridge") {
                kind = .hotspot
            } else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !result.contains(where: { $0.ip == ip }) {
                result.append(Address(ip: ip, kind: kind))
            }
        }
        return result
    }
}
