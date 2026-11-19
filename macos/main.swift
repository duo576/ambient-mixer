import AppKit
import WebKit
import CoreAudio

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSMenuDelegate, WKScriptMessageHandler {

    static let bundleID = "com.duolan.ambient-mixer"

    var statusItem: NSStatusItem?
    var window: NSWindow?
    var webView: WKWebView?
    let statusMenu = NSMenu()
    let pauseItem = NSMenuItem(title: "暂停播放", action: #selector(pausePlayback), keyEquivalent: "")
    let resumeItem = NSMenuItem(title: "继续播放", action: #selector(resumePlayback), keyEquivalent: "")

    // MARK: - lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护：已有实例在跑就激活它，自己退出
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other = others.first {
            print("[ambient-mixer] another instance running, exiting self")
            other.activate()
            NSApp.terminate(nil)
            return
        }

        // Set the running app icon explicitly as well as the bundle icon so
        // Dock and window switching do not retain an earlier placeholder.
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        // 右键菜单
        let showItem = NSMenuItem(title: "显示窗口", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        statusMenu.autoenablesItems = false
        statusMenu.addItem(showItem)
        statusMenu.addItem(.separator())
        pauseItem.target = self
        resumeItem.target = self
        pauseItem.isEnabled = false
        resumeItem.isEnabled = false
        statusMenu.addItem(pauseItem)
        statusMenu.addItem(resumeItem)
        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        statusMenu.addItem(quitItem)
        statusMenu.delegate = self

        // 菜单栏按钮（状态栏图标）
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            if let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "氛围音播放器") {
                img.isTemplate = true
                btn.image = img
            } else {
                btn.title = "♫"
            }
            btn.toolTip = "氛围音播放器"
            btn.target = self
            btn.action = #selector(statusClicked(_:))
            _ = btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        buildMainMenu()
        buildWindow()
        setupOutputDeviceMonitor()

        DispatchQueue.main.async { [weak self] in
            self?.showWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // 关窗口不退出，菜单栏图标还在
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let w = window else { return }
        if w.isMiniaturized { w.deminiaturize(nil) }
        w.makeKeyAndOrderFront(nil)
    }

    func buildMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于氛围音播放器", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏氛围音播放器", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出氛围音播放器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("拷贝", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - window

    func buildWindow() {
        let rect = NSRect(x: 0, y: 0, width: 760, height: 460)
        let w = NSWindow(contentRect: rect,
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "氛围音播放器"
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: 460, height: 300)
        w.level = .normal
        w.collectionBehavior = [.managed, .moveToActiveSpace, .fullScreenPrimary]
        w.setFrameAutosaveName("AmbientMixerMainWindow")
        if !w.setFrameUsingName("AmbientMixerMainWindow") { w.center() }

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(self, name: "playbackState")
        let webView = WKWebView(frame: rect, configuration: config)
        webView.navigationDelegate = self
        w.contentView = webView

        self.webView = webView
        self.window = w

        if let url = Bundle.main.url(forResource: "player", withExtension: "html") {
            _ = webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            print("[ambient-mixer] ERROR: player.html missing from bundle")
        }
    }

    @objc func showWindow() {
        guard let w = window else { return }
        if w.isMiniaturized { w.deminiaturize(nil) }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    // MARK: - status item

    @objc func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let btn = statusItem?.button else { return }
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: btn.bounds.minY), in: btn)
        } else {
            // A visible window may be behind another app or on another Space.
            // Always bring it forward instead of hiding it based on isVisible.
            showWindow()
        }
    }

    @objc func pausePlayback() {
        webView?.evaluateJavaScript("window.ambientMixer?.pausePlayback()", completionHandler: nil)
    }

    @objc func resumePlayback() {
        Task { @MainActor in
            do {
                _ = try await webView?.callAsyncJavaScript("await window.ambientMixer?.resumePlayback()", arguments: [:], in: nil, contentWorld: .page)
            } catch { print("[ambient-mixer] resume failed: \(error)") }
        }
    }

    // MARK: - 播放设备监听

    private var deviceListener: AudioObjectPropertyListenerBlock?

    /// 规则：检测到默认输出设备切换 → 暂停所有音轨（复用「继续播放」语义）
    func setupOutputDeviceMonitor(){
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                print("[ambient-mixer] default output device changed → pause all tracks")
                self?.pausePlayback()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        if status == noErr {
            deviceListener = block
            print("[ambient-mixer] output device monitor installed")
        }else{
            print("[ambient-mixer] output device monitor failed: \(status)")
        }
    }

    func currentDefaultOutput() -> AudioDeviceID {
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return dev
    }

    @discardableResult
    func setDefaultOutput(_ dev: AudioDeviceID) -> OSStatus {
        var d = dev
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &d)
    }

    /// 列出有输出通道的设备 (id, 名称)
    func outputDevices() -> [(AudioDeviceID, String)] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        var out: [(AudioDeviceID, String)] = []
        for id in ids {
            var cfg = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            var cfgSize = UInt32(0)
            guard AudioObjectGetPropertyDataSize(id, &cfg, 0, nil, &cfgSize) == noErr, cfgSize > 0 else { continue }
            let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(cfgSize), alignment: 16)
            defer { raw.deallocate() }
            guard AudioObjectGetPropertyData(id, &cfg, 0, nil, &cfgSize, raw) == noErr else { continue }
            let abl = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            let channels = abl.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0 else { continue }

            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            _ = AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name)
            out.append((id, name as String))
        }
        return out
    }

    /// AMBIENT_DEVICE_TEST=1：播放首条音轨 → 真实切换输出设备 → 验证自动暂停 → 继续播放 → 切回原设备
    private func runDeviceSwitchTest(){
        Task { @MainActor in
            guard let wv = webView else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 等音轨恢复
            let playJS = "(function(){var b=document.querySelector('#list .row .play'); if(!b) return 'no-track'; b.click(); return 'clicked';})()"
            if let r = try? await wv.evaluateJavaScript(playJS) { print("[ambient-mixer] device-test play: \(r as? String ?? "?")") }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let stateJS = "(function(){var t=window.ambientMixer.tracks[0]; return JSON.stringify({paused: t? t.audio.paused : null, ct: t? +t.audio.currentTime.toFixed(2) : null, btn: document.getElementById('allBtn').textContent, btnDisabled: document.getElementById('allBtn').disabled});})()"
            if let r = try? await wv.evaluateJavaScript(stateJS) { print("[ambient-mixer] device-test before: \(r as? String ?? "?")") }

            let cur = currentDefaultOutput()
            let devices = outputDevices()
            print("[ambient-mixer] device-test outputs: \(devices.map { "\($0.0):\($0.1)" }), current=\(cur)")
            guard let alt = devices.first(where: { $0.0 != cur }) else {
                print("[ambient-mixer] device-test: no alternate output device"); return
            }
            print("[ambient-mixer] device-test switch→\(alt.0)(\(alt.1)) status=\(setDefaultOutput(alt.0))")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let r = try? await wv.evaluateJavaScript(stateJS) { print("[ambient-mixer] device-test after switch: \(r as? String ?? "?")") }

            // 验证「继续播放」能恢复暂停前的音轨
            _ = try? await wv.evaluateJavaScript("void window.ambientMixer.resumePlayback()")
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if let r = try? await wv.evaluateJavaScript(stateJS) { print("[ambient-mixer] device-test after resume: \(r as? String ?? "?")") }
            _ = try? await wv.evaluateJavaScript("void window.ambientMixer.pausePlayback()")

            print("[ambient-mixer] device-test restore→\(cur) status=\(setDefaultOutput(cur))")
            try? await Task.sleep(nanoseconds: 800_000_000)
            print("[ambient-mixer] device-test done")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "playbackState", let state = message.body as? [String: Bool] else { return }
        pauseItem.isEnabled = state["canPause"] == true
        resumeItem.isEnabled = state["canResume"] == true
    }

    // MARK: - webview

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[ambient-mixer] page loaded: \(webView.title ?? "?")")
        let env = ProcessInfo.processInfo.environment
        if env["AMBIENT_CLEAN"] != nil {
            runDebugJS(clean: true)
        } else if env["AMBIENT_DEBUG"] != nil {
            runDebugJS(clean: false)
        }
        if env["AMBIENT_DEVICE_TEST"] != nil {
            runDeviceSwitchTest()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[ambient-mixer] page load failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[ambient-mixer] page load failed: \(error.localizedDescription)")
    }

    /// 环境变量触发的自检（正常启动不执行，不影响用户数据）
    private func runDebugJS(clean: Bool) {
        guard let wv = webView else { return }
        let body: String
        if clean {
            body = """
              try { localStorage.removeItem('__ambient_launch'); localStorage.removeItem('ambient-mixer-meta'); } catch(e) {}
              try { indexedDB.deleteDatabase('ambient-mixer'); } catch(e) {}
              try { indexedDB.deleteDatabase('__ambient_dbg'); } catch(e) {}
              return 'cleaned';
            """
        } else {
            body = """
              var out = {};
              try {
                var prev = localStorage.getItem('__ambient_launch');
                var n = prev ? ((parseInt(prev,10)||0)+1) : 1;
                localStorage.setItem('__ambient_launch', String(n));
                out.lsPrev = prev; out.lsNow = n;
              } catch(e) { out.ls = 'ERR:' + e.message; }
              return new Promise(function(resolve){
                try {
                  var req = indexedDB.open('__ambient_dbg', 1);
                  req.onupgradeneeded = function(){ req.result.createObjectStore('m'); };
                  req.onsuccess = function(){
                    var db = req.result;
                    var tx = db.transaction('m','readwrite');
                    var store = tx.objectStore('m');
                    var get = store.get('n');
                    get.onsuccess = function(){
                      var prev = get.result || 0;
                      store.put(prev+1, 'n');
                      tx.oncomplete = function(){ out.idbPrev = prev; out.idbNow = prev+1; resolve(JSON.stringify(out)); };
                    };
                    get.onerror = function(){ out.idb = 'ERR:get'; resolve(JSON.stringify(out)); };
                  };
                  req.onerror = function(){ out.idb = 'ERR:' + ((req.error && req.error.message) || '?'); resolve(JSON.stringify(out)); };
                } catch(e){ out.idb = 'ERR:' + e.message; resolve(JSON.stringify(out)); }
              });
            """
        }
        Task { @MainActor in
            do {
                let result = try await wv.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
                print("[ambient-mixer] debug(\(clean ? "clean" : "run")): \(result as? String ?? String(describing: result))")
            } catch {
                print("[ambient-mixer] debug error: \(error.localizedDescription)")
            }
        }
        if !clean {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let js = "JSON.stringify({tracks: window.ambientMixer ? window.ambientMixer.tracks.length : -1, playing: document.querySelectorAll('#list .row.playing').length})"
                if let r = try? await wv.evaluateJavaScript(js) {
                    print("[ambient-mixer] state: \(r as? String ?? "?")")
                }
                let winInfo = self.window.map { "win(visible=\($0.isVisible), level=\($0.level), frame=\($0.frame))" } ?? "win=nil"
                let stInfo = self.statusItem.map { st in
                    let bw = st.button?.window
                    return "status(btnWin visible=\(bw?.isVisible ?? false), frame=\(String(describing: bw?.frame)), length=\(st.length))"
                } ?? "status=nil"
                print("[ambient-mixer] ui: \(winInfo) | \(stInfo)")

                // 进程内合成点击，验证 图标→statusClicked→showWindow 链路（不动用户屏幕）
                if let btn = self.statusItem?.button {
                    let before = self.window?.isVisible ?? false
                    btn.performClick(nil)
                    let after = self.window?.isVisible ?? false
                    btn.performClick(nil)
                    let restored = self.window?.isVisible ?? false
                    print("[ambient-mixer] toggle test: \(before) -> \(after) -> \(restored) (expect true -> true -> true)")
                }
            }
        }
    }
}

// MARK: - entry

setvbuf(stdout, nil, _IONBF, 0) // 日志即时输出，便于终端诊断

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
