import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSMenuDelegate {

    static let bundleID = "com.duolan.ambient-mixer"

    var statusItem: NSStatusItem?
    var window: NSWindow?
    var webView: WKWebView?
    let statusMenu = NSMenu()

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

        // 右键菜单
        let showItem = NSMenuItem(title: "显示 / 隐藏窗口", action: #selector(toggleWindow), keyEquivalent: "")
        showItem.target = self
        statusMenu.addItem(showItem)
        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = self
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

        buildWindow()

        DispatchQueue.main.async { [weak self] in
            self?.showWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // 关窗口不退出，菜单栏图标还在
    }

    // MARK: - window

    func buildWindow() {
        let rect = NSRect(x: 0, y: 0, width: 820, height: 560)
        let w = NSWindow(contentRect: rect,
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "氛围音播放器"
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: 460, height: 300)
        w.center()

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
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

    func showWindow() {
        guard let w = window else { return }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func toggleWindow() {
        guard let w = window else { return }
        if w.isVisible {
            w.orderOut(nil)
        } else {
            showWindow()
        }
    }

    // MARK: - status item

    @objc func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // 右键弹菜单（弹完由 menuDidClose 复位，左键才能恢复切换窗口）
            if let item = statusItem, let btn = item.button {
                item.menu = statusMenu
                btn.performClick(nil)
            }
        } else {
            toggleWindow()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
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

                // 进程内合成点击，验证 图标→statusClicked→toggleWindow 链路（不动用户屏幕）
                if let btn = self.statusItem?.button {
                    let before = self.window?.isVisible ?? false
                    btn.performClick(nil)
                    let after = self.window?.isVisible ?? false
                    btn.performClick(nil)
                    let restored = self.window?.isVisible ?? false
                    print("[ambient-mixer] toggle test: \(before) -> \(after) -> \(restored) (expect true -> false -> true)")
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
app.setActivationPolicy(.accessory)
app.run()
