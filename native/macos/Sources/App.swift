import AppKit
import SwiftUI

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
    @Environment(\.colorScheme) private var colorScheme
    private var step: Int { model.stage == .connect ? 0 : model.stage == .review ? 1 : 2 }
    private var accent: Color { colorScheme == .dark ? Color(red: 0.46, green: 0.79, blue: 0.72) : Color(red: 31/255, green: 120/255, blue: 109/255) }
    private var muted: Color { colorScheme == .dark ? Color(red: 0.69, green: 0.73, blue: 0.70) : Color(red: 0.38, green: 0.41, blue: 0.39) }
    private var onAccent: Color { colorScheme == .dark ? Color(red: 0.06, green: 0.14, blue: 0.12) : .white }
    private var line: Color { Color(nsColor: .separatorColor).opacity(0.65) }
    private var pageTitle: String {
        if model.stage == .connect { return "Connect a feeder" }
        if model.stage == .review { return "Review your installation" }
        return model.result == nil ? "Original operation restored" : "Connect Home Assistant"
    }
    private var pageDescription: String {
        if model.stage == .connect { return "Start with one feeder on your Wi-Fi. We check its exact firmware before making changes." }
        if model.stage == .review { return "Confirm the selected feeder and choose where to keep its private backups." }
        return model.result == nil ? "The original application and network routing are back in place." : "Local control is installed. Use these private details to finish setup."
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Step \(step + 1) of 3").font(.system(size: 12)).foregroundColor(muted)
                            Text(pageTitle).font(.system(size: 28, weight: .medium)).foregroundColor(.primary)
                            Text(pageDescription).font(.system(size: 14)).foregroundColor(muted).fixedSize(horizontal: false, vertical: true)
                        }
                        if model.stage == .connect { connection }
                        else if model.stage == .review { review }
                        else { completion }
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 13)).foregroundColor(.red).padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.06)).cornerRadius(12)
                        }
                    }.frame(maxWidth: 600, alignment: .leading).padding(32).frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }.frame(maxWidth: .infinity)
        }.frame(minWidth: 900, minHeight: 680)
            .background(Color(nsColor: .windowBackgroundColor)).accentColor(accent)
            .alert("Restore stock operation?", isPresented: $model.confirmRestore) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) { model.restore() }
            } message: { Text("This restores only the selected feeder's original application and Internet routing. Its MCU meal table is preserved.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 56, height: 56)
                    .accessibilityLabel("Pet Feeder Local installer")
                Text("Pet Feeder\nLocal").font(.system(size: 22, weight: .semibold)).lineSpacing(1)
            }
            Text("Local control for your feeder").font(.system(size: 13)).foregroundColor(muted)
            VStack(alignment: .leading, spacing: 8) {
                stepLabel(0, "Connect", "Check one feeder")
                stepLabel(1, "Review & install", "Back up before installing")
                stepLabel(2, "Home Assistant", "Finish local setup")
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 12) {
                if model.demo {
                    Label("Disconnected preview", systemImage: "eye").font(.system(size: 12)).foregroundColor(accent)
                }
                Text("Installer \(installerVersion)\nFirmware overlay 0.2.0")
                    .font(.system(size: 12)).foregroundColor(muted).lineSpacing(4)
            }
        }.padding(24).frame(width: 240).background(Color(nsColor: .controlBackgroundColor))
    }

    private func stepLabel(_ index: Int, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step > index ? "checkmark.circle.fill" : "\(index + 1).circle")
                .font(.system(size: 18, weight: .regular)).frame(width: 20)
                .foregroundColor(step >= index ? accent : muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(step == index ? .primary : muted)
                Text(subtitle).font(.system(size: 12)).foregroundColor(muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(step == index ? accent.opacity(0.08) : .clear).cornerRadius(12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                if model.busy { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: model.error != nil ? "exclamationmark.circle" : model.stage == .complete ? "checkmark.circle" : "info.circle")
                        .foregroundColor(model.error != nil ? .red : muted)
                }
                Text(model.message).font(.system(size: 13)).foregroundColor(muted).fixedSize(horizontal: false, vertical: true)
            }.accessibilityElement(children: .combine)
            HStack(spacing: 16) {
                Text("Backups and credentials stay on this Mac").font(.system(size: 12)).foregroundColor(muted)
                Spacer()
                Button("Close installer") { NSApplication.shared.terminate(nil) }.disabled(model.busy).controlSize(.large)
            }
        }.padding(24).background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20, content: content).padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor)).cornerRadius(16)
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(line, lineWidth: 1) }
    }

    private func primaryAction(_ title: String, image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image).font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16).frame(minHeight: 40)
                .foregroundColor(onAccent).background(accent).cornerRadius(8)
        }.buttonStyle(.plain)
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shippingbox").font(.system(size: 18)).foregroundColor(muted).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supported model").font(.system(size: 12)).foregroundColor(muted)
                    Text("V330L-DU4L-VS · Original firmware 68.00.09").font(.system(size: 13, weight: .medium))
                }
            }
            panel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Feeder IP address").font(.system(size: 13, weight: .medium))
                    TextField("192.168.1.123", text: $model.address).textFieldStyle(.roundedBorder).controlSize(.large)
                        .accessibilityIdentifier("feeder-address")
                    Text("Find it in your router or the feeder's Tuya / Smart Life device information.")
                        .font(.system(size: 12)).foregroundColor(muted)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Device root password").font(.system(size: 13, weight: .medium))
                    SecureField("Root password", text: $model.password).textFieldStyle(.roundedBorder).controlSize(.large)
                    Text("The known factory password is prefilled. This is not your Tuya account password.")
                        .font(.system(size: 12)).foregroundColor(muted)
                }
                Divider()
                Label("Keep the power adapter connected and Wi-Fi configured. No Tuya developer account, microSD card or soldering is needed for this supported firmware.", systemImage: "powerplug")
                    .font(.system(size: 13)).foregroundColor(muted).fixedSize(horizontal: false, vertical: true)
                primaryAction("Check compatibility", image: "arrow.right", action: model.check).disabled(model.address.isEmpty)
            }
            Text("Checking is read-only. Only the address you enter will be contacted.").font(.system(size: 12)).foregroundColor(muted)
        }.disabled(model.busy)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 24) {
            panel {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield").font(.system(size: 20)).foregroundColor(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exact firmware verified").font(.system(size: 15, weight: .medium))
                        Text("\(model.address) · V330L-DU4L-VS").font(.system(size: 13)).foregroundColor(muted).textSelection(.enabled)
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 24) {
                    detail("Original firmware", "68.00.09")
                    detail("Overlay", model.details?.version ?? "0.2.0")
                    detail("Operation", model.details?.upgrade == true ? "Upgrade" : "First installation")
                }
            }
            panel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private backups").font(.system(size: 16, weight: .medium))
                    Text("Two matching full backups come first. Then the installer verifies and activates a reversible overlay. It does not write raw flash, send a feeding command or replace the saved meal table.")
                        .font(.system(size: 13)).foregroundColor(muted).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Backup folder").font(.system(size: 12)).foregroundColor(muted)
                    Text(model.demo ? "~/Documents/PetFeederLocalBackups" : model.backups.path)
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).lineLimit(3)
                    Button("Choose folder…", action: model.chooseBackups).disabled(model.demo).controlSize(.large)
                }
                Divider()
                Toggle("I selected the correct feeder and will keep it powered on", isOn: $model.confirmed).font(.system(size: 13))
                HStack {
                    Button("Back", action: model.back).controlSize(.large)
                    Spacer()
                    primaryAction(model.demo ? "Preview only" : "Back up and install", image: "arrow.down.to.line", action: model.install)
                        .disabled(!model.confirmed || model.demo)
                }
            }
            Text("Experimental: tested on one exact hardware profile. Observe actual meals before relying on it. Battery feeding and clock retention after complete power loss remain unverified.")
                .font(.system(size: 12)).foregroundColor(muted).fixedSize(horizontal: false, vertical: true)
            if model.details?.upgrade == true && !model.demo {
                Button("Restore stock operation…", role: .destructive) { model.confirmRestore = true }.disabled(!model.confirmed)
            }
        }.disabled(model.busy)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundColor(muted)
            Text(value).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let result = model.result {
                panel {
                    Label("Local API verified", systemImage: "checkmark.circle").font(.system(size: 15, weight: .medium)).foregroundColor(accent)
                    Text("Add the companion repository to Marketplace, install it, then set up the integration with these private details.")
                        .font(.system(size: 13)).foregroundColor(muted)
                    HStack(spacing: 12) {
                        Link("Add to Marketplace", destination: URL(string: "https://my.home-assistant.io/redirect/marketplace_repository/?owner=e2equiel&repository=ha-pet-feeder-local&category=integration")!)
                            .buttonStyle(.plain).padding(.horizontal, 16).frame(minHeight: 40)
                            .foregroundColor(onAccent).background(accent).cornerRadius(8)
                        Link("Set up integration", destination: URL(string: "https://my.home-assistant.io/redirect/config_flow_start/?domain=pet_feeder_local")!)
                            .buttonStyle(.bordered)
                    }.controlSize(.large)
                }
                panel {
                    detail("Local API address", result.apiAddress).textSelection(.enabled)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Private API token").font(.system(size: 12)).foregroundColor(muted)
                        HStack(spacing: 8) {
                            SecureField("Private token", text: .constant(result.token)).textFieldStyle(.roundedBorder)
                            Button(model.copied ? "Copied" : "Copy", action: model.copyToken)
                        }.controlSize(.large)
                    }
                    Divider()
                    Text("A private home-assistant-setup.json file is saved with your backups. Never post it, the token or your backup files publicly.")
                        .font(.system(size: 12)).foregroundColor(muted)
                    Button("Show private backups") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: result.backupDirectory.path) }.controlSize(.large)
                }
            } else {
                panel {
                    Label("Stock operation restored", systemImage: "checkmark.circle").font(.system(size: 16, weight: .medium)).foregroundColor(accent)
                    Text("The device may take a few minutes to reconnect to Tuya. Its saved meal table was not changed.")
                        .font(.system(size: 14)).foregroundColor(muted)
                }
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
        window.minSize = NSSize(width: 900, height: 680)
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
