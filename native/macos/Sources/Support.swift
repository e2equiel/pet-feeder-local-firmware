import Foundation
import CryptoKit
import Darwin

struct InstallerFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func randomHex(_ count: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    return (0..<count).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
}

func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

func captures(_ text: String, _ pattern: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
        (0..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
    }
}

func localAddress(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4,
          parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && ($0.count == 1 || !$0.hasPrefix("0")) }),
          parts.allSatisfy({ UInt8($0) != nil }) else {
        throw InstallerFailure("Enter one private IPv4 address, for example 192.168.1.123.")
    }
    let bytes = parts.map { UInt8($0)! }
    guard bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) || (bytes[0] == 192 && bytes[1] == 168) else {
        throw InstallerFailure("Only a private LAN address is accepted. No network scan is performed.")
    }
    return bytes.map(String.init).joined(separator: ".")
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

func privateWrite(_ data: Data, to path: URL) throws {
    try data.write(to: path, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
}

func jsonData(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
}

final class SocketChannel {
    private var descriptor: Int32 = -1

    init(host: String, port: UInt16, timeout: TimeInterval = 5) throws {
        let host = try localAddress(host)
        descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw InstallerFailure("Could not open a local connection.") }
        do {
            var noSignal: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw InstallerFailure("Could not prepare the local connection.")
            }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { throw InstallerFailure("Invalid device address.") }
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if connected != 0 {
                guard errno == EINPROGRESS else { throw InstallerFailure("Could not connect. Check the feeder's power, address and Wi-Fi.") }
                var item = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                guard poll(&item, 1, Int32(timeout * 1000)) > 0 else { throw InstallerFailure("The local connection timed out.") }
                var error: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else {
                    throw InstallerFailure("Could not connect. Check the feeder's power, address and Wi-Fi.")
                }
            }
            guard fcntl(descriptor, F_SETFL, flags) == 0 else { throw InstallerFailure("Could not prepare the local connection.") }
            var receiveTimeout = timeval(tv_sec: 0, tv_usec: 400_000)
            var sendTimeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        } catch {
            close()
            throw error
        }
    }

    func send(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.send(descriptor, base.advanced(by: offset), buffer.count - offset, 0)
                if sent < 0 && errno == EINTR { continue }
                guard sent > 0 else { throw InstallerFailure("The device connection was interrupted.") }
                offset += sent
            }
        }
    }

    // nil means the bounded receive timed out; an EOF is a connection error.
    func receive() throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
        if count < 0 && [EAGAIN, EWOULDBLOCK, EINTR].contains(errno) { return nil }
        guard count > 0 else { throw InstallerFailure("The feeder connection closed. Check its power and address.") }
        return Data(buffer.prefix(count))
    }

    func close() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }

    deinit { close() }
}

protocol DeviceTransport: AnyObject {
    var host: String { get }
    func run(_ command: String, timeout: TimeInterval, limit: Int) throws -> String
    func close()
}

extension DeviceTransport {
    func run(_ command: String) throws -> String { try run(command, timeout: 20, limit: 128 * 1024) }
}

struct TelnetDecoder {
    private var partial = Data()

    mutating func clean(_ received: Data, reply: (Data) throws -> Void) throws -> Data {
        let bytes = [UInt8](partial + received)
        partial.removeAll(keepingCapacity: true)
        var output = Data()
        var cursor = 0
        while cursor < bytes.count {
            guard bytes[cursor] == 255 else { output.append(bytes[cursor]); cursor += 1; continue }
            guard cursor + 1 < bytes.count else { partial = Data(bytes[cursor...]); break }
            let command = bytes[cursor + 1]
            if command == 255 { output.append(255); cursor += 2 }
            else if [251, 252, 253, 254].contains(command) {
                guard cursor + 2 < bytes.count else { partial = Data(bytes[cursor...]); break }
                if command == 253 { try reply(Data([255, 252, bytes[cursor + 2]])) }
                if command == 251 { try reply(Data([255, 254, bytes[cursor + 2]])) }
                cursor += 3
            } else if command == 250 {
                var end = cursor + 2
                while end + 1 < bytes.count && !(bytes[end] == 255 && bytes[end + 1] == 240) { end += 1 }
                guard end + 1 < bytes.count else {
                    guard bytes.count - cursor <= 4096 else { throw InstallerFailure("Invalid Telnet negotiation.") }
                    partial = Data(bytes[cursor...]); break
                }
                cursor = end + 2
            } else { cursor += 2 }
        }
        return output
    }
}

final class TelnetTransport: DeviceTransport {
    let host: String
    private let channel: SocketChannel
    private var decoder = TelnetDecoder()

    init(host: String, password: String) throws {
        self.host = try localAddress(host)
        guard !password.isEmpty, password.utf8.count < 512, !password.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) else {
            throw InstallerFailure("Enter a valid root password.")
        }
        channel = try SocketChannel(host: self.host, port: 23)
        do {
            _ = try until("login:\\s*$", timeout: 10)
            try channel.send(Data("root\r\n".utf8))
            _ = try until("Password:\\s*$", timeout: 5)
            try channel.send(Data((password + "\r\n").utf8))
            let result = try until("(?:[#\\$] ?|Login incorrect)", timeout: 8)
            if result.contains("Login incorrect") { throw InstallerFailure("The root password was rejected. Nothing was installed.") }
        } catch { channel.close(); throw error }
    }

    private func until(_ pattern: String, timeout: TimeInterval, limit: Int = 128 * 1024) throws -> String {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data()
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard let data = try channel.receive() else { continue }
            output.append(try decoder.clean(data, reply: channel.send))
            guard output.count <= limit else { throw InstallerFailure("The device returned more data than expected. Installation stopped.") }
            if matches(String(decoding: output.suffix(512), as: UTF8.self), pattern) {
                return String(decoding: output, as: UTF8.self).replacingOccurrences(of: "\r\0", with: "\r")
            }
        }
        throw InstallerFailure("The feeder did not respond in time. Check its power and Wi-Fi connection.")
    }

    static func envelope(_ command: String, marker: String) throws -> Data {
        let encoded = Data(command.utf8).base64EncodedString()
        let result = Data("printf '%s' '\(encoded)' | busybox base64 -d | /bin/sh -e; pfl_code=$?; printf '\\n\(marker)%s\\n' \"$pfl_code\"\n".utf8)
        guard result.count <= 1000 else { throw InstallerFailure("A console command exceeds the supported limit. Activation stopped.") }
        return result
    }

    func run(_ command: String, timeout: TimeInterval = 20, limit: Int = 128 * 1024) throws -> String {
        let marker = "PFL_DONE_" + randomHex(12)
        try channel.send(Self.envelope(command, marker: marker))
        let output = try until("\\r?\\n\(marker)\\d+\\r?\\n", timeout: timeout, limit: limit)
        let codes = captures(output, marker + "(\\d+)\\r?\\n")
        guard codes.first?[1] == "0" else { throw InstallerFailure("A device check failed. No raw flash is written.") }
        return output.replacingOccurrences(of: "\r", with: "")
    }

    func close() { try? channel.send(Data("exit\n".utf8)); channel.close() }
}

enum APIResource: String { case info, schedules }

func parseDeviceHTTP(_ response: Data) throws -> [String: Any] {
    guard response.count <= 16384,
          let boundary = response.range(of: Data("\r\n\r\n".utf8)), boundary.lowerBound <= 8192 else {
        throw InstallerFailure("The device returned an invalid or oversized API response.")
    }
    let header = String(decoding: response[..<boundary.lowerBound], as: UTF8.self)
    let lines = header.components(separatedBy: "\r\n")
    guard matches(lines.first ?? "", "^HTTP/1\\.[01] 200(?: |$)") else {
        throw InstallerFailure("The local API could not be verified. No redirects are followed.")
    }
    let lengths = lines.dropFirst().filter { $0.lowercased().hasPrefix("content-length:") }
    guard lengths.count == 1, let length = Int(lengths[0].dropFirst(15).trimmingCharacters(in: .whitespaces)),
          (0...8192).contains(length), !lines.contains(where: { $0.lowercased().hasPrefix("transfer-encoding:") }) else {
        throw InstallerFailure("The device returned an unsupported or oversized API response.")
    }
    let body = response[boundary.upperBound...]
    guard body.count == length, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw InstallerFailure("The device returned an incomplete or invalid API response.")
    }
    return object
}

func deviceAPI(host: String, token: String, resource: APIResource) throws -> [String: Any] {
    let host = try localAddress(host)
    guard matches(token, "^[A-Za-z0-9_-]{32,96}$") else { throw InstallerFailure("The existing API token is invalid. Use Restore before reinstalling.") }
    // Direct numeric IPv4 socket: no DNS, HTTP proxy, cookies or redirect path.
    let channel = try SocketChannel(host: host, port: 8080)
    defer { channel.close() }
    let request = "GET /api/v1/\(resource.rawValue) HTTP/1.0\r\nHost: \(host):8080\r\nAuthorization: Bearer \(token)\r\nConnection: close\r\n\r\n"
    try channel.send(Data(request.utf8))
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    var output = Data()
    while ProcessInfo.processInfo.systemUptime < deadline {
        guard let data = try channel.receive() else { continue }
        output.append(data)
        guard output.count <= 16384 else { throw InstallerFailure("The local API response is too large.") }
        if let boundary = output.range(of: Data("\r\n\r\n".utf8)) {
            guard boundary.lowerBound <= 8192 else { throw InstallerFailure("The local API headers are too large.") }
            let header = String(decoding: output[..<boundary.lowerBound], as: UTF8.self)
            let lengths = captures(header, "(?im)^Content-Length: *([0-9]+) *$")
            guard let text = lengths.first?[1], let length = Int(text), length <= 8192 else {
                throw InstallerFailure("The local API response is invalid or too large.")
            }
            if output.count - boundary.upperBound >= length { return try parseDeviceHTTP(output) }
        }
    }
    throw InstallerFailure("The local API timed out.")
}
