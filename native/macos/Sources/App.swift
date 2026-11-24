import AppKit
import SwiftUI

private let accent = Color(red: 31/255, green: 120/255, blue: 109/255)
private let ink = Color(red: 18/255, green: 61/255, blue: 69/255)
private let installerVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"

final class InstallerModel: ObservableObject {
    enum Stage { case connect, review, complete }
    @Published var address = ""
    @Published var password = "AK2040jk"
    @Published var backups = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PetFeederLocalBackups")
    @Published var stage = Stage.connect
    @Published var busy = false
    @Published var message = "Ready to check one feeder."
    @Published var error: String?
    @Published var details: FeederDetails?
    @Published var result: InstallResult?
    @Published var confirmed = false
    @Published var copied = false
    @Published var confirmRestore = false
    @Published var demo: Bool
    private var installer: FeederInstaller?
    private var backupPanel: NSOpenPanel?
    private let queue = DispatchQueue(label: "io.github.e2equiel.pet-feeder-local.installer", qos: .userInitiated)

    init(demo: Bool) {
        self.demo = demo
        if demo { address = "192.168.1.123"; message = "Disconnected preview. No device will be contacted." }
    }

    private func report(_ stage: String, _ text: String) {
        DispatchQueue.main.async { self.message = text }
    }

    func check() {
        guard !busy else { return }
        busy = true; error = nil; confirmed = false
        let host = address, secret = password
        queue.async {
            do {
                if self.demo {
                    DispatchQueue.main.async {
                        self.details = FeederDetails(identity: "00:00:00:00:00:00", upgrade: false, version: "0.2.0")
                        self.stage = .review; self.busy = false
                        self.message = "Sample compatibility result. No network connection was made."
                    }
                    return
                }
                guard let resources = Bundle.main.resourceURL else { throw InstallerFailure("The app bundle is incomplete.") }
                let bundle = try ReleaseBundle.load(resources.appendingPathComponent("bundle"))
                let transport = try TelnetTransport(host: host, password: secret)
                let installer = FeederInstaller(transport: transport, bundle: bundle, progress: self.report)
                do {
                    let details = try installer.inspect(requireAPI: false)
                    DispatchQueue.main.async {
                        self.installer = installer; self.details = details; self.stage = .review; self.busy = false
                        self.message = "Exact supported firmware verified. Review this feeder before continuing."
                    }
                } catch { transport.close(); throw error }
            } catch { self.fail(error) }
        }
    }

    func install() {
        guard !busy, confirmed, stage == .review else { return }
        if demo { message = "Preview only. Installation is disabled; no device was contacted."; return }
        guard let installer else { return }
        busy = true; error = nil
        let destination = backups
        queue.async {
            defer { installer.transport.close() }
            do {
                let result = try installer.install(destination)
                DispatchQueue.main.async {
                    self.result = result; self.stage = .complete; self.busy = false; self.installer = nil
                }
            } catch { self.fail(error) }
        }
    }

    func restore() {
        guard !busy, confirmed, stage == .review, let installer else { return }
        busy = true; error = nil
        queue.async {
            defer { installer.transport.close() }
            do {
                try installer.restore()
                DispatchQueue.main.async { self.stage = .complete; self.busy = false; self.installer = nil }
            } catch { self.fail(error) }
        }
    }

    private func fail(_ error: Error) {
        let text = (error as? InstallerFailure)?.message ?? "Could not complete the operation. Check the feeder and keep your private backups."
        DispatchQueue.main.async {
            self.installer?.transport.close(); self.installer = nil
            self.error = text; self.busy = false; self.stage = .connect
            self.message = "Stopped. Review the error before trying again."
        }
    }

    func back() {
        guard !busy else { return }
        installer?.transport.close(); installer = nil; details = nil; confirmed = false
        stage = .connect; error = nil; message = "Ready to check one feeder."
    }

    func chooseBackups() {
        guard !busy, backupPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose where to keep private feeder backups"
        panel.prompt = "Use this folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = backups
        backupPanel = panel
        let selected: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, let panel else { return }
            defer { if self.backupPanel === panel { self.backupPanel = nil } }
            if response == .OK, let folder = panel.urls.first ?? panel.directoryURL {
                DispatchQueue.main.async { self.backups = folder; self.message = "Private backup folder selected." }
            }
        }
        if let window = NSApplication.shared.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: selected)
        } else {
            panel.begin(completionHandler: selected)
        }
    }

    func copyToken() {
        guard let result else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result.token, forType: .string)
        copied = true
    }

    func closeConnection() { installer?.transport.close(); installer = nil }

    func preview() {
        guard !busy, stage == .connect else { return }
        demo = true; address = "192.168.1.123"; error = nil
        message = "Disconnected preview. No device will be contacted."
    }
}

struct InstallerView: View {
    @ObservedObject var model: InstallerModel
    private var step: Int { model.stage == .connect ? 0 : model.stage == .review ? 1 : 2 }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 78, height: 78)
                    .accessibilityLabel("Pet Feeder Local installer")
                VStack(alignment: .leading, spacing: 7) {
                    Text("Pet Feeder\nLocal").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundColor(ink)
                    Text("Your feeder.\nYour network.").font(.system(size: 15)).foregroundColor(.secondary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 18) {
                    stepLabel(0, "Connect", "Choose one feeder")
                    stepLabel(1, "Review & install", "Verified private backups")
                    stepLabel(2, "Connect Home Assistant", "Local controls and camera")
                }.padding(.top, 16)
                Spacer()
                if model.demo { Label("Disconnected preview", systemImage: "eye").font(.caption).foregroundColor(accent) }
                Text("Installer \(installerVersion)\nFirmware overlay 0.2.0").font(.caption).foregroundColor(.secondary).lineSpacing(4)
            }.padding(28).frame(width: 245).background(Color(red: 238/255, green: 246/255, blue: 242/255))
            VStack(alignment: .leading, spacing: 18) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.stage == .connect { connection }
                        else if model.stage == .review { review }
                        else { completion }
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundColor(.red).padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.06)).cornerRadius(10)
                        }
                    }.padding(.trailing, 4)
                }
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.error == nil ? "checkmark.circle" : "exclamationmark.circle").foregroundColor(accent) }
                    Text(model.message).font(.callout).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityElement(children: .combine)
                HStack {
                    Text("Backups and credentials stay on this Mac.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Close installer") { NSApplication.shared.terminate(nil) }.disabled(model.busy)
                }
            }.padding(30).frame(maxWidth: .infinity)
        }.frame(minWidth: 880, minHeight: 670).background(Color(NSColor.windowBackgroundColor)).accentColor(accent)
            .alert("Restore stock operation?", isPresented: $model.confirmRestore) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) { model.restore() }
            } message: { Text("This restores only the selected feeder's original application and Internet routing. Its MCU meal table is preserved.") }
    }

    private func stepLabel(_ index: Int, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step > index ? "checkmark.circle.fill" : "\(index + 1).circle.fill")
                .font(.title3).foregroundColor(step >= index ? accent : .gray.opacity(0.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(step >= index ? ink : .secondary)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("Make it local.").font(.system(size: 31, weight: .bold, design: .rounded))
            Text("Check your feeder before making any changes. Only the address you enter will be contacted.")
                .font(.callout).foregroundColor(.secondary)
            Label("V330L-DU4L-VS · Original firmware 68.00.09", systemImage: "checkmark.shield")
                .font(.callout).foregroundColor(accent).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.07)).cornerRadius(10)
            VStack(alignment: .leading, spacing: 7) {
                Text("Feeder IP address").font(.headline)
                TextField("192.168.1.123", text: $model.address).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("feeder-address")
                Text("Find this in your router or the feeder's Tuya / Smart Life device information.").font(.caption).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Device root password").font(.headline)
                SecureField("Root password", text: $model.password).textFieldStyle(.roundedBorder)
                Text("The known factory password is prefilled. This is not your Tuya account password.").font(.caption).foregroundColor(.secondary)
            }
            Text("Keep the feeder on its power adapter. Wi-Fi must already be configured. No Tuya developer account, microSD card or soldering is needed for this supported version.")
                .font(.callout).foregroundColor(.secondary)
            Button(action: model.check) { Label("Check compatibility", systemImage: "arrow.right").padding(.vertical, 4) }
                .buttonStyle(.borderedProminent).disabled(model.address.isEmpty)
        }.disabled(model.busy)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready for your review.").font(.system(size: 29, weight: .bold, design: .rounded))
            Text("\(model.address) · V330L-DU4L-VS").font(.headline).textSelection(.enabled)
            HStack(spacing: 28) {
                detail("Original firmware", "68.00.09")
                detail("Overlay", model.details?.version ?? "0.2.0")
                detail("Operation", model.details?.upgrade == true ? "Upgrade" : "First installation")
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.06)).cornerRadius(10)
            Text("Two matching full backups come first. Then the installer verifies and activates a reversible overlay. It does not write raw flash, send a feeding command or replace the saved meal table.")
                .font(.callout).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                Text("Private backup folder").font(.headline)
                Text(model.demo ? "~/Documents/PetFeederLocalBackups" : model.backups.path).font(.caption).foregroundColor(.secondary).lineLimit(2).textSelection(.enabled)
                Button("Choose folder…", action: model.chooseBackups).disabled(model.demo)
            }
            Text("Experimental: tested on one exact hardware profile. Observe actual meals before relying on it. Battery feeding and clock retention after complete power loss remain unverified.")
                .font(.caption).foregroundColor(.secondary)
            Toggle("I selected the correct feeder and will keep it powered on.", isOn: $model.confirmed).font(.callout)
            HStack {
                Button("Back", action: model.back)
                Spacer()
                Button(model.demo ? "Preview only" : "Back up and install", action: model.install)
                    .buttonStyle(.borderedProminent).disabled(!model.confirmed || model.demo)
            }
            if model.details?.upgrade == true && !model.demo {
                Button("Restore stock operation…", role: .destructive) { model.confirmRestore = true }.disabled(!model.confirmed)
            }
        }.disabled(model.busy)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundColor(.secondary); Text(value).font(.callout.weight(.semibold)) }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("\(model.result == nil ? "Restored" : "You're local.")", systemImage: "checkmark.seal.fill")
                .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundColor(accent)
            if let result = model.result {
                Text("Connect Home Assistant").font(.title2.bold())
                Text("Add the companion repository to Marketplace, install it, then set up the integration with these private details.").font(.callout).foregroundColor(.secondary)
                detail("Local API address", result.apiAddress).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Private API token").font(.caption).foregroundColor(.secondary)
                    HStack { SecureField("Private token", text: .constant(result.token)).textFieldStyle(.roundedBorder); Button(model.copied ? "Copied" : "Copy", action: model.copyToken) }
                }
                HStack {
                    Link("Add to Marketplace", destination: URL(string: "https://my.home-assistant.io/redirect/marketplace_repository/?owner=e2equiel&repository=ha-pet-feeder-local&category=integration")!)
                    Link("Set up integration", destination: URL(string: "https://my.home-assistant.io/redirect/config_flow_start/?domain=pet_feeder_local")!)
                }.buttonStyle(.bordered)
                Button("Show private backups") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: result.backupDirectory.path) }
                Text("A private home-assistant-setup.json file is saved with your backups. Never post it, the token or your backup files publicly.").font(.caption).foregroundColor(.secondary)
            } else {
                Text("The original application and network routing have been restored. The device may take time to reconnect to Tuya.")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let model = InstallerModel(demo: CommandLine.arguments.contains("--demo"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Pet Feeder Local Installer"
        window.minSize = NSSize(width: 880, height: 670)
        window.contentView = NSHostingView(rootView: InstallerView(model: model))
        window.delegate = self; window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model.busy ? .terminateCancel : .terminateNow }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !model.busy }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model.closeConnection() }
    @objc func previewInstaller(_ sender: Any?) { model.preview() }
}

@main
struct NativeInstallerApp {
    static func main() {
        if CommandLine.arguments.contains("--verify-bundle") {
            do {
                guard let resources = Bundle.main.resourceURL else { throw InstallerFailure("Missing app resources.") }
                let bundle = try ReleaseBundle.load(resources.appendingPathComponent("bundle"))
                let icon = resources.appendingPathComponent("AppIcon.icns")
                guard FileManager.default.fileExists(atPath: icon.path) else { throw InstallerFailure("Missing app icon.") }
                print("Native macOS installer \(installerVersion); firmware \(bundle.version); bundle checksums and icon verified; no Python runtime")
            } catch { fputs("Bundle verification failed.\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let applicationItem = NSMenuItem(); menu.addItem(applicationItem)
        let applicationMenu = NSMenu()
        let preview = applicationMenu.addItem(withTitle: "Preview without a device", action: #selector(AppDelegate.previewInstaller(_:)), keyEquivalent: "p")
        preview.keyEquivalentModifierMask = [.command, .shift]; preview.target = delegate
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Pet Feeder Local Installer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu; app.mainMenu = menu
        withExtendedLifetime(delegate) { app.run() }
    }
}
