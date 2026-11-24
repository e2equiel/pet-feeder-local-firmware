import Foundation

struct TestFailure: Error { let message: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(message: message) }
}
func rejects(_ action: () throws -> Void) throws {
    do { try action() } catch { return }
    throw TestFailure(message: "Expected operation to be refused")
}

final class FakeTransport: DeviceTransport {
    let host = "192.168.1.123"
    var commands = [String]()
    var answer: (String) throws -> String = { _ in "" }
    func run(_ command: String, timeout: TimeInterval, limit: Int) throws -> String {
        commands.append(command); return try answer(command)
    }
    func close() {}
}

class ReadFixture: FeederInstaller {
    var readings = [Data]()
    override func read(_ command: String, maximum: Int, timeout: TimeInterval = 180) throws -> Data {
        guard !readings.isEmpty else { throw TestFailure(message: "Unexpected device read") }
        return readings.removeFirst()
    }
}

final class InstallFixture: FeederInstaller {
    var writes = [String]()
    var failBoot = false
    var folder: URL
    init(transport: FakeTransport, bundle: ReleaseBundle, folder: URL) {
        self.folder = folder; super.init(transport: transport, bundle: bundle)
        transport.answer = { [weak self] command in self?.writes.append(command); return "" }
        api = { _, _, resource in resource == .info ? ["version": "0.2.0", "id": "00:11:22:33:44:55"] : ["meals": []] }
    }
    override func inspect(requireAPI: Bool = true) throws -> FeederDetails {
        let details = FeederDetails(identity: "00:11:22:33:44:55", upgrade: !token.isEmpty, version: bundle.version)
        self.details = details; return details
    }
    override func backup(_ destination: URL) throws -> URL { folder }
    override func upload(_ path: String, payload: Data) throws {
        writes.append(path)
        if failBoot && path.hasSuffix("/boot.sh") { throw InstallerFailure("Synthetic upload interruption") }
    }
}

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("pet-feeder-native-tests-" + UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: temporary) }

func fixtureBundle() throws -> ReleaseBundle {
    let folder = temporary.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let files = ["pf_local.so": Data([127,69,76,70,1,0]), "boot.sh": Data("#!/bin/sh\n".utf8), "uninstall.sh": Data("#!/bin/sh\n".utf8)]
    for (name, bytes) in files { try bytes.write(to: folder.appendingPathComponent(name)) }
    let manifest: [String: Any] = ["format": 1, "version": "0.2.0", "stock_application_sha256": stockSHA256,
                                   "partition_sizes": partitionSizes, "files": files.mapValues(sha256)]
    try jsonData(manifest).write(to: folder.appendingPathComponent("release.json"))
    return try ReleaseBundle.load(folder)
}

let bundle = try fixtureBundle()
let flash = Data(repeating: 65, count: flashSize)
let mtd = partitionSizes.enumerated().map { "mtd\($0.offset): \(String(format: "%08x", $0.element)) 00010000" }.joined(separator: "\n")
var passed = 0
func test(_ name: String, _ action: () throws -> Void) {
    do { try action(); passed += 1; print("PASS " + name) }
    catch { fputs("FAIL \(name): \((error as? TestFailure)?.message ?? error.localizedDescription)\n", stderr); exit(1) }
}

test("one canonical private IPv4 target; no hostnames, subnets or shell input") {
    for host in ["192.168.1.123", "10.1.2.3", "172.16.1.2", "172.31.2.3"] { try expect(try localAddress(host) == host, "Private address rejected") }
    for host in ["8.8.8.8", "127.0.0.1", "169.254.1.2", "172.32.0.1", "feeder.local", "192.168.1.0/24", "::1", "192.168.1.2; reboot", "192.168.01.2", "10.0.0.256"] {
        try rejects { _ = try localAddress(host) }
    }
}
test("bundle rejects tampering") {
    let candidate = try fixtureBundle()
    try Data("tampered".utf8).write(to: candidate.directory.appendingPathComponent("boot.sh"))
    try rejects { _ = try ReleaseBundle.load(candidate.directory) }
}
test("bundle rejects extra paths") {
    let candidate = try fixtureBundle(); let path = candidate.directory.appendingPathComponent("release.json")
    var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
    var files = manifest["files"] as! [String: String]; files["../../outside"] = String(repeating: "0", count: 64); manifest["files"] = files
    try jsonData(manifest).write(to: path)
    try rejects { _ = try ReleaseBundle.load(candidate.directory) }
}
test("unknown partition layout stops before writes") {
    let transport = FakeTransport(); transport.answer = { $0 == "busybox --list" ? "base64 sha256sum tar dd" : "mtd0: 00800000 00010000" }
    try rejects { _ = try FeederInstaller(transport: transport, bundle: bundle).inspect() }
    try expect(transport.commands.count == 2, "Unexpected command after profile refusal")
}
test("foreign boot modification is preserved") {
    let transport = FakeTransport(); transport.answer = { $0 == "busybox --list" ? "base64 sha256sum tar dd" : mtd }
    let installer = ReadFixture(transport: transport, bundle: bundle); installer.readings = [Data("#!/bin/sh\nother_project".utf8)]
    try rejects { _ = try installer.inspect() }
    try expect(transport.commands.count == 2, "Unexpected command after foreign hook")
}
test("unsupported original application is refused") {
    let transport = FakeTransport()
    transport.answer = { $0 == "busybox --list" ? "base64 sha256sum tar dd" : $0 == "cat /proc/mtd" ? mtd : "wrong fingerprint" }
    let installer = ReadFixture(transport: transport, bundle: bundle); installer.readings = [Data()]
    try rejects { _ = try installer.inspect() }
    try expect(!transport.commands.contains(where: { $0.contains("mkdir") }), "Profile check wrote data")
}
test("binary backup transfer and maximum size") {
    let transport = FakeTransport(); let bytes = Data((0..<5120).map { UInt8($0 % 256) })
    transport.answer = { command in let marker = captures(command, "PFL_DATA_[a-f0-9]+")[0][0]; return "\n\(marker)_BEGIN\n\(bytes.base64EncodedString())\n\(marker)_END\n" }
    let installer = FeederInstaller(transport: transport, bundle: bundle)
    try expect(try installer.read("cat synthetic", maximum: bytes.count) == bytes, "Binary transfer changed bytes")
    try rejects { _ = try installer.read("cat synthetic", maximum: 100) }
}
test("interrupted or invalid base64 is refused") {
    let transport = FakeTransport(); transport.answer = { _ in "truncated" }
    let installer = FeederInstaller(transport: transport, bundle: bundle)
    try rejects { _ = try installer.read("cat synthetic", maximum: 100) }
    transport.answer = { command in let marker = captures(command, "PFL_DATA_[a-f0-9]+")[0][0]; return "\n\(marker)_BEGIN\n%%%%\n\(marker)_END\n" }
    try rejects { _ = try installer.read("cat synthetic", maximum: 100) }
}
test("failed upload never replaces destination") {
    let transport = FakeTransport(); let installer = FeederInstaller(transport: transport, bundle: bundle)
    try rejects { try installer.upload("/run/synthetic", payload: Data("test".utf8)) }
    try expect(!transport.commands.contains(where: { $0.contains("mv -f") }), "Unverified file was renamed")
}
test("two matching full flash backups are required") {
    let transport = FakeTransport(); let installer = ReadFixture(transport: transport, bundle: bundle)
    installer.details = FeederDetails(identity: "synthetic", upgrade: false, version: "0.2.0")
    installer.readings = [flash, Data(repeating: 66, count: flashSize)]
    try rejects { _ = try installer.backup(temporary.appendingPathComponent("different")) }
    try expect(transport.commands.isEmpty, "Backup failure performed a write")
}
test("truncated backup stops before installation") {
    let transport = FakeTransport(); let installer = ReadFixture(transport: transport, bundle: bundle)
    installer.details = FeederDetails(identity: "synthetic", upgrade: false, version: "0.2.0"); installer.readings = [Data("short".utf8)]
    try rejects { _ = try installer.backup(temporary.appendingPathComponent("truncated")) }
    try expect(transport.commands.isEmpty, "Truncated backup performed a write")
}
test("matching backups have private permissions and exact hashes") {
    let installer = ReadFixture(transport: FakeTransport(), bundle: bundle)
    installer.details = FeederDetails(identity: "synthetic", upgrade: false, version: "0.2.0"); installer.readings = [flash, flash, Data(repeating: 48, count: 2048)]
    let folder = try installer.backup(temporary.appendingPathComponent("matching"))
    let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("backup.json"))) as! [String: Any]
    try expect((metadata["files"] as? [String: String])?["flash-read-1.bin"] == sha256(flash), "Incorrect backup hash")
    let permissions = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("flash-read-1.bin").path)[.posixPermissions] as! Int
    try expect(permissions == 0o600, "Backup permissions are not private")
    let directoryPermissions = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as! Int
    try expect(directoryPermissions == 0o700, "Backup directory permissions are not private")
}
test("rollback preserves journal, token and raw flash") {
    let script = FeederInstaller.rollbackScript("/run/synthetic-transaction")
    for forbidden in ["operations.dat", "/dev/mtd", "api.token", "POST", "schedules"] { try expect(!script.contains(forbidden), "Rollback touches " + forbidden) }
    try expect(script.contains("active.rollback") && script.contains("was-enabled"), "Rollback restoration missing")
}
test("recovery is armed before replacing boot files") {
    let installer = InstallFixture(transport: FakeTransport(), bundle: bundle, folder: temporary); installer.failBoot = true
    try rejects { _ = try installer.install(temporary) }
    let timer = installer.writes.firstIndex(where: { $0.contains("sleep 180") })!
    let boot = installer.writes.firstIndex(of: "/mnt/config/pet-feeder-local/boot.sh")!
    try expect(timer < boot, "Boot file changed before recovery timer")
    try expect(installer.writes.last!.hasSuffix("/rollback.sh"), "Failed installation did not roll back")
}
test("failed activation rolls back without feeding") {
    let installer = InstallFixture(transport: FakeTransport(), bundle: bundle, folder: temporary); installer.activationTimeout = 0
    try rejects { _ = try installer.install(temporary) }
    try expect(installer.writes.last!.hasSuffix("/rollback.sh"), "No rollback after failed activation")
    try expect(!installer.writes.contains(where: { $0.contains("POST") || $0.contains("/dev/mtd") }), "Unexpected feed or raw-flash command")
}
test("changed meal table causes rollback before commit") {
    let installer = InstallFixture(transport: FakeTransport(), bundle: bundle, folder: temporary)
    installer.previousSchedule = [["portions": 2]]
    try rejects { _ = try installer.install(temporary) }
    try expect(installer.writes.last!.hasSuffix("/rollback.sh"), "Changed schedule was committed")
    try expect(!installer.writes.contains(where: { $0.hasPrefix("touch /run/") && $0.contains("/committed") }), "Schedule mismatch was committed")
}
test("successful upgrade preserves token and exact meal table") {
    let installer = InstallFixture(transport: FakeTransport(), bundle: bundle, folder: temporary)
    installer.token = String(repeating: "a", count: 64); installer.previousSchedule = []
    let result = try installer.install(temporary)
    try expect(result.token == String(repeating: "a", count: 64), "Existing token changed")
    try expect(!installer.writes.contains(where: { $0.hasSuffix("/api.token") }), "Existing token overwritten")
    try expect(installer.writes.contains(where: { $0.hasPrefix("touch /run/") && $0.contains("/committed") }), "Successful activation not committed")
    let file = temporary.appendingPathComponent("home-assistant-setup.json")
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! Int
    try expect(permissions == 0o600, "Setup credentials are not private")
}
test("API accepts complete bounded JSON only") {
    let body = "{\"api_version\":1}"
    let response = Data("HTTP/1.1 200 Response\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
    try expect(try parseDeviceHTTP(response)["api_version"] as? Int == 1, "API JSON rejected")
    for response in ["HTTP/1.1 302 Found\r\nLocation: http://example.com/\r\nContent-Length: 2\r\n\r\n{}", "HTTP/1.1 200 OK\r\nContent-Length: 8193\r\n\r\n{}", "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}", "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{"] {
        try rejects { _ = try parseDeviceHTTP(Data(response.utf8)) }
    }
}
test("console command length is bounded before sending") {
    try rejects { _ = try TelnetTransport.envelope(String(repeating: "x", count: 2000), marker: "PFL_DONE_test") }
    try expect(try TelnetTransport.envelope("printf synthetic", marker: "PFL_DONE_test").count < 1000, "Small command rejected")
}
test("Telnet completion markers are recognized across real CRLF frames") {
    let marker = "PFL_DONE_synthetic"
    let response = "command output\r\n\(marker)0\r\n[root@ipc:/root]# "
    try expect(matches(response, "\\r?\\n\(marker)\\d+\\r?\\n"), "Real Telnet completion frame was missed")
    try expect(captures(response, marker + "(\\d+)\\r?\\n").first?[1] == "0", "Completion code was lost")
}
test("Telnet negotiation supports split packets and escaped IAC") {
    var decoder = TelnetDecoder(); var replies = [Data]()
    try expect(try decoder.clean(Data([97,255,253]), reply: { replies.append($0) }) == Data([97]), "Split negotiation lost data")
    try expect(try decoder.clean(Data([1,98,255,255]), reply: { replies.append($0) }) == Data([98,255]), "Negotiation continuation failed")
    try expect(replies == [Data([255,252,1])], "Unsupported option was not rejected")
}
print("\(passed) native installer boundary tests passed; no hardware or cloud required")
