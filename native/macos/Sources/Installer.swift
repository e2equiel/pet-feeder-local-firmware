import Foundation

let stockSHA256 = "f499431d38ed3cb8a4607ee870f06461e14ccb9f6f6387137b0ded2f5191a499"
let partitionSizes = [0x32000, 0x1000, 0x1000, 0xC000, 0x190000, 0x570000, 0xC0000]
let flashSize = partitionSizes.reduce(0, +)
let immutableSize = partitionSizes.dropLast().reduce(0, +)
private let statePath = "/mnt/config/pet-feeder-local"
private let hookPath = "/mnt/config/tmp_test.sh"
private let hookMarker = "PET_FEEDER_LOCAL_BOOT_HOOK"

struct ReleaseBundle {
    let directory: URL
    let version: String
    let moduleSHA256: String

    static func load(_ directory: URL) throws -> ReleaseBundle {
        do {
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("release.json"))) as? [String: Any]
            guard let manifest, manifest["format"] as? Int == 1,
                  manifest["stock_application_sha256"] as? String == stockSHA256,
                  manifest["partition_sizes"] as? [Int] == partitionSizes,
                  let files = manifest["files"] as? [String: String],
                  Set(files.keys) == Set(["pf_local.so", "boot.sh", "uninstall.sh"]),
                  let version = manifest["version"] as? String, matches(version, "^[0-9]+\\.[0-9]+\\.[0-9]+$") else {
                throw InstallerFailure("Invalid manifest.")
            }
            for (name, digest) in files {
                guard sha256(try Data(contentsOf: directory.appendingPathComponent(name))) == digest else {
                    throw InstallerFailure("Release checksum mismatch.")
                }
            }
            guard try Data(contentsOf: directory.appendingPathComponent("pf_local.so")).prefix(5) == Data([127, 69, 76, 70, 1]) else {
                throw InstallerFailure("Unsupported module.")
            }
            return ReleaseBundle(directory: directory, version: version, moduleSHA256: files["pf_local.so"]!)
        } catch {
            throw InstallerFailure("The bundled release is incomplete or damaged. Download a fresh installer ZIP.")
        }
    }
}

struct FeederDetails {
    let identity: String
    let upgrade: Bool
    let version: String
    var metadata: [String: Any] {
        ["model": "V330L-DU4L-VS", "stock_version": "68.00.09", "identity": identity,
         "stock_application_sha256": stockSHA256, "upgrade": upgrade, "version_to_install": version]
    }
}

struct InstallResult {
    let apiAddress: String
    let token: String
    let backupDirectory: URL
    let scheduledMeals: Int
    let version: String
    var metadata: [String: Any] {
        ["model": "V330L-DU4L-VS", "version": version, "api_address": apiAddress, "token": token,
         "backup_directory": backupDirectory.path, "scheduled_meals": scheduledMeals,
         "rtsp_address": "rtsp://feeder:TOKEN@\(URL(string: apiAddress)!.host!):8555/live"]
    }
}

class FeederInstaller {
    let transport: DeviceTransport
    let bundle: ReleaseBundle
    let progress: (String, String) -> Void
    var details: FeederDetails?
    var token = ""
    var previousSchedule: NSArray?
    var api: (String, String, APIResource) throws -> [String: Any] = { try deviceAPI(host: $0, token: $1, resource: $2) }
    var activationTimeout: TimeInterval = 75

    init(transport: DeviceTransport, bundle: ReleaseBundle, progress: @escaping (String, String) -> Void = { _, _ in }) {
        self.transport = transport; self.bundle = bundle; self.progress = progress
    }

    func read(_ command: String, maximum: Int, timeout: TimeInterval = 180) throws -> Data {
        let marker = "PFL_DATA_" + randomHex(12)
        let output = try transport.run("printf '\\n\(marker)_BEGIN\\n'\n\(command) | busybox base64\nprintf '\\n\(marker)_END\\n'",
                                       timeout: timeout, limit: maximum * 2 + 65536)
        guard let start = output.range(of: "\n\(marker)_BEGIN\n"),
              let end = output.range(of: "\n\(marker)_END\n", range: start.upperBound..<output.endIndex) else {
            throw InstallerFailure("The backup transfer was interrupted. Retry before installing.")
        }
        let encoded = output[start.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
        guard let result = Data(base64Encoded: String(encoded)), result.count <= maximum else {
            throw InstallerFailure("The backup transfer is incomplete, invalid or larger than expected.")
        }
        return result
    }

    func upload(_ path: String, payload: Data) throws {
        let temporary = shellQuote(path + ".new-" + randomHex(8))
        _ = try transport.run(": > \(temporary)\nchmod 600 \(temporary)")
        for cursor in stride(from: 0, to: payload.count, by: 96) {
            if payload.count > 4096 && cursor % (96 * 25) == 0 {
                progress("installing", "Uploading the local service… \(cursor * 100 / payload.count)%")
            }
            let end = min(cursor + 96, payload.count)
            let encoded = payload[cursor..<end].base64EncodedString()
            _ = try transport.run("printf '%s' '\(encoded)' | busybox base64 -d >> \(temporary)")
        }
        let digest = sha256(payload)
        guard matches(try transport.run("busybox sha256sum \(temporary)"), "(?m)^\(digest)\\s") else {
            throw InstallerFailure("An uploaded file failed verification. Activation was not attempted.")
        }
        _ = try transport.run("mv -f \(temporary) \(shellQuote(path))")
    }

    @discardableResult
    func inspect(requireAPI: Bool = true) throws -> FeederDetails {
        progress("checking", "Checking this feeder's exact firmware and flash layout…")
        let applets = Set(try transport.run("busybox --list").split(whereSeparator: { $0.isWhitespace }).map(String.init))
        guard Set(["base64", "sha256sum", "tar", "dd"]).isSubset(of: applets) else {
            throw InstallerFailure("This firmware lacks the required backup tools. It is not supported.")
        }
        let rows = captures(try transport.run("cat /proc/mtd"), "mtd([0-9]+):\\s+([0-9a-f]+)")
        var sizes = [Int: Int]()
        for row in rows { if let index = Int(row[1]), let size = Int(row[2], radix: 16) { sizes[index] = size } }
        guard rows.count == 7, sizes.count == 7, (0..<7).allSatisfy({ sizes[$0] == partitionSizes[$0] }) else {
            throw InstallerFailure("The flash layout is not supported. Nothing was installed.")
        }
        let hook = String(decoding: try read("test ! -f \(hookPath) || cat \(hookPath)", maximum: 16384), as: UTF8.self)
        guard hook.isEmpty || hook.contains(hookMarker) else {
            throw InstallerFailure("This feeder has another boot modification. It will not be overwritten.")
        }
        let mounted = try transport.run("cat /proc/mounts").contains(" /usr/sbin/ak_tuya_ipc ")
        let application = mounted && !hook.isEmpty ? "/run/pet-feeder-local/ak_tuya_ipc" : "/usr/sbin/ak_tuya_ipc"
        guard matches(try transport.run("busybox sha256sum \(application)"), "(?m)^\(stockSHA256)\\s") else {
            throw InstallerFailure("The original firmware fingerprint is not supported. Do not force installation.")
        }
        let mac = String(decoding: try read("cat /sys/class/net/wlan0/address", maximum: 128), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard matches(mac, "^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$") else { throw InstallerFailure("Could not read a reliable device identity.") }
        if !hook.isEmpty && requireAPI {
            token = String(decoding: try read("cat \(statePath)/api.token", maximum: 128), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard matches(token, "^[A-Za-z0-9_-]{32,96}$") else {
                throw InstallerFailure("The existing token is missing or invalid. Use Restore before reinstalling.")
            }
            do {
                guard let meals = try api(transport.host, token, .schedules)["meals"] as? NSArray else { throw InstallerFailure("Missing schedule.") }
                previousSchedule = meals
            } catch { throw InstallerFailure("The existing local installation is not healthy. Use Restore before upgrading.") }
        }
        let result = FeederDetails(identity: mac, upgrade: !hook.isEmpty, version: bundle.version)
        details = result
        return result
    }

    func backup(_ destination: URL) throws -> URL {
        if details == nil { try inspect() }
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let directory = destination.appendingPathComponent("feeder-" + formatter.string(from: Date()) + "-" + randomHex(4))
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var readings = [Data]()
        var checksums = [String: String]()
        for index in 1...2 {
            progress("backup", "Reading backup \(index) of 2. Keep the feeder powered on…")
            let data = try read("cat " + (0..<7).map { "/dev/mtd\($0)" }.joined(separator: " "), maximum: flashSize)
            guard data.count == flashSize else { throw InstallerFailure("A complete flash backup could not be read. Nothing was installed.") }
            let name = "flash-read-\(index).bin"
            try privateWrite(data, to: directory.appendingPathComponent(name))
            checksums[name] = sha256(data); readings.append(data)
        }
        guard readings[0] == readings[1] else { throw InstallerFailure("The two flash backups differ. Wait until the feeder is idle, then retry.") }
        let configuration = try read("tar -C /mnt/config -cf - .", maximum: 4 * 1024 * 1024)
        guard configuration.count >= 1024 else { throw InstallerFailure("The configuration backup is incomplete. Nothing was installed.") }
        try privateWrite(configuration, to: directory.appendingPathComponent("private-configuration.tar"))
        checksums["private-configuration.tar"] = sha256(configuration)
        let metadata: [String: Any] = ["device": details!.metadata, "files": checksums,
                                      "immutable_flash_sha256": sha256(readings[0].prefix(immutableSize)),
                                      "warning": "Private: contains Wi-Fi and device credentials. Never upload this directory."]
        try privateWrite(jsonData(metadata), to: directory.appendingPathComponent("backup.json"))
        try privateWrite(Data("These backups contain credentials. Keep them private. Never attach them to a GitHub issue.\nRaw flash restoration requires hardware expertise.\n".utf8), to: directory.appendingPathComponent("KEEP_PRIVATE.txt"))
        return directory
    }

    func install(_ destination: URL) throws -> InstallResult {
        let details = try inspect()
        let backupDirectory = try backup(destination)
        progress("installing", "Backups match. Uploading and checking the local firmware overlay…")
        let transaction = "/run/pet-feeder-install-" + randomHex(12)
        let release = statePath + "/releases/" + bundle.moduleSHA256
        _ = try transport.run("mkdir -p \(statePath) \(statePath)/releases \(release) \(transaction)\nchmod 700 \(statePath) \(transaction)")
        _ = try transport.run("for name in active boot.sh; do test ! -f \(statePath)/$name || cp \(statePath)/$name \(transaction)/$name; done\ntest ! -f \(hookPath) || cp \(hookPath) \(transaction)/hook\ntest ! -f \(statePath)/enabled || touch \(transaction)/was-enabled\ntest ! -f \(statePath)/feeding.enabled || touch \(transaction)/was-feeding-enabled")
        try upload(transaction + "/rollback.sh", payload: Data(Self.rollbackScript(transaction).utf8))
        var activated = false
        do {
            try upload(release + "/pf_local.so", payload: Data(contentsOf: bundle.directory.appendingPathComponent("pf_local.so")))
            try upload(release + "/module.sha256", payload: Data((bundle.moduleSHA256 + "  pf_local.so\n").utf8))
            _ = try transport.run("cd \(release) && busybox sha256sum -c module.sha256\nLD_BIND_NOW=1 LD_PRELOAD=\(release)/pf_local.so /bin/true")
            // Recovery is armed before any boot pointer changes; the durable
            // operation journal, API token and raw flash are never rolled back.
            _ = try transport.run("(trap '' HUP; sleep 180; /bin/sh \(transaction)/rollback.sh) > \(transaction)/rollback.log 2>&1 &")
            try upload(statePath + "/boot.sh", payload: Data(contentsOf: bundle.directory.appendingPathComponent("boot.sh")))
            try upload(statePath + "/uninstall.sh", payload: Data(contentsOf: bundle.directory.appendingPathComponent("uninstall.sh")))
            if token.isEmpty {
                token = randomHex(32)
                try upload(statePath + "/api.token", payload: Data((token + "\n").utf8))
            }
            try upload(statePath + "/active", payload: Data((bundle.moduleSHA256 + "\n").utf8))
            try upload(hookPath, payload: Data("#!/bin/sh\n# \(hookMarker)\n/bin/sh \(statePath)/boot.sh > /run/pet-feeder-local-boot.log 2>&1 || true\n".utf8))
            _ = try transport.run("chmod 600 \(statePath)/api.token\nchmod 700 \(hookPath) \(statePath)/boot.sh \(statePath)/uninstall.sh\ntouch \(statePath)/enabled \(statePath)/feeding.enabled\nsync")
            activated = true
            progress("restarting", "Restarting only this feeder's camera application…")
            _ = try transport.run("if grep -q ' /usr/sbin/ak_tuya_ipc ' /proc/mounts; then umount /usr/sbin/ak_tuya_ipc; fi\n/bin/sh \(statePath)/boot.sh && kill -TERM $(pidof ak_tuya_ipc)")
            let deadline = ProcessInfo.processInfo.systemUptime + activationTimeout
            var verifiedMeals: NSArray?
            while ProcessInfo.processInfo.systemUptime < deadline {
                do {
                    _ = try transport.run("pid=$(pidof ak_tuya_ipc); test -n \"$pid\"; grep -F '\(release)/pf_local.so' /proc/$pid/maps")
                    let info = try api(transport.host, token, .info)
                    if info["version"] as? String == bundle.version && info["id"] as? String == details.identity {
                        let schedule = try api(transport.host, token, .schedules)
                        guard let meals = schedule["meals"] as? NSArray else { throw InstallerFailure("Missing schedule.") }
                        verifiedMeals = meals
                        break
                    }
                } catch { /* Retry reads only. A device timer also protects activation. */ }
                Thread.sleep(forTimeInterval: 1)
            }
            guard let meals = verifiedMeals else { throw InstallerFailure("The local API did not start. Restoring the previous installation.") }
            if let previousSchedule, !previousSchedule.isEqual(to: meals as! [Any]) {
                throw InstallerFailure("Schedule verification failed. Restoring the previous installation.")
            }
            _ = try transport.run("touch \(transaction)/committed\nsync")
            let result = InstallResult(apiAddress: "http://\(transport.host):8080", token: token,
                                       backupDirectory: backupDirectory, scheduledMeals: meals.count, version: bundle.version)
            try privateWrite(jsonData(result.metadata), to: backupDirectory.appendingPathComponent("home-assistant-setup.json"))
            progress("complete", "Installed. Keep your backups private, then connect Home Assistant.")
            return result
        } catch {
            if activated { progress("restoring", "Verification failed. Restoring the previous installation…") }
            _ = try? transport.run("/bin/sh \(transaction)/rollback.sh")
            throw error
        }
    }

    static func rollbackScript(_ transaction: String) -> String {
        """
        #!/bin/sh
        test ! -f \(transaction)/committed || exit 0
        if test -f \(transaction)/active; then
            cp \(transaction)/active \(statePath)/active.rollback && mv -f \(statePath)/active.rollback \(statePath)/active
        else
            rm -f \(statePath)/active
        fi
        if test -f \(transaction)/boot.sh; then cp \(transaction)/boot.sh \(statePath)/boot.sh; fi
        if test -f \(transaction)/hook; then cp \(transaction)/hook \(hookPath); chmod 700 \(hookPath); else rm -f \(hookPath); fi
        if test ! -f \(transaction)/was-feeding-enabled; then rm -f \(statePath)/feeding.enabled; fi
        if grep -q ' /usr/sbin/ak_tuya_ipc ' /proc/mounts; then umount /usr/sbin/ak_tuya_ipc; fi
        if test -f \(transaction)/was-enabled; then
            /bin/sh \(statePath)/boot.sh
        else
            rm -f \(statePath)/enabled
            busybox ip route del unreachable 0.0.0.0/1 2>/dev/null || true
            busybox ip route del unreachable 128.0.0.0/1 2>/dev/null || true
        fi
        pid=$(pidof ak_tuya_ipc || true)
        test -z "$pid" || kill -TERM $pid
        touch \(transaction)/committed
        sync

        """
    }

    func restore() throws {
        try inspect(requireAPI: false)
        progress("restoring", "Restoring this feeder's original boot path and network routing…")
        _ = try transport.run("test -f \(statePath)/uninstall.sh && /bin/sh \(statePath)/uninstall.sh")
        progress("complete", "Stock operation restored. Meal schedules were not changed.")
    }
}
