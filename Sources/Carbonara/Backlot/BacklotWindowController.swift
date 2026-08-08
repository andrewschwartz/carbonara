import AppKit
import WebKit

enum BacklotControlError: LocalizedError {
    case resourcesMissing
    case pageFailedToLoad(String)
    case scriptFailed(String)
    case unexpectedResult

    var errorDescription: String? {
        switch self {
        case .resourcesMissing: "Backlot resources are missing from this build."
        case .pageFailedToLoad(let reason): "Backlot failed to load: \(reason)"
        case .scriptFailed(let reason): "Backlot couldn't run the request: \(reason)"
        case .unexpectedResult: "Backlot returned an unexpected result."
        }
    }
}

/// Singleton tool window hosting the Backlot previs shot builder.
///
/// Backlot runs as a bundled web app in a WKWebView. A script message bridge
/// (`BacklotBridge`) routes exported reference frames and generated media into
/// the active project's media library, and other exports to a save panel.
@MainActor
final class BacklotWindowController: NSWindowController {
    static let shared = BacklotWindowController()

    private let bridge = BacklotBridge()
    private var webView: WKWebView?

    private enum PageState { case idle, loading, ready, failed(String) }
    private var pageState: PageState = .idle
    private var pageWaiters: [CheckedContinuation<Void, Error>] = []
    /// Bumped per hydration so a slower in-flight hydration can't set `reflectedEditor` for a stale bin.
    private var hydrationGeneration = 0

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Backlot"
        window.minSize = NSSize(width: 980, height: 620)
        window.setFrameAutosaveName("CarbonaraBacklot-v1")
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        super.init(window: window)
        bridge.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if webView == nil, !loadWebView() {
            Log.app.error("backlot resource missing: Backlot/backlot.html")
            let alert = NSAlert()
            alert.messageText = "Backlot Unavailable"
            alert.informativeText = "Backlot resources are missing from this build."
            alert.runModal()
            return
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hydrate(from: AppState.shared.activeProject?.editorViewModel)
    }

    /// Projects the given project's persisted scenes into the shared web bin.
    /// No-op until Backlot has been opened; the bin hydrates lazily on `show()`.
    /// Because the window is a singleton shared across projects, this must run on
    /// every active-project change so a stale bin can't write into the wrong project.
    func hydrate(from editor: EditorViewModel?) {
        guard webView != nil else { return }
        Task { await hydrateBin(from: editor) }
    }

    private func hydrateBin(from editor: EditorViewModel?) async {
        hydrationGeneration &+= 1
        let generation = hydrationGeneration
        // Block write-back while the bin no longer matches any project's scenes.
        bridge.reflectedEditor = nil
        let payload = Self.hydrationPayload(for: editor?.backlotScenes ?? [])
        do {
            _ = try await evaluate("window.backlotAgent.hydrate(\(payload))")
            guard generation == hydrationGeneration else { return }
            bridge.reflectedEditor = editor
        } catch {
            Log.app.warning("backlot hydrate failed: \(Log.detail(error))")
        }
    }

    /// Encodes scenes into the `{scenes:[{id,name,shotData,composedPrompt}]}` shape
    /// `agentHydrate` expects; `shotData` is passed through verbatim as a JSON string.
    private static func hydrationPayload(for scenes: [BacklotScene]) -> String {
        struct HydrationScene: Encodable {
            let id: String
            let name: String
            let shotData: String
            let composedPrompt: String
        }
        struct HydrationStore: Encodable { let scenes: [HydrationScene] }
        let store = HydrationStore(scenes: scenes.map {
            HydrationScene(id: $0.id, name: $0.name, shotData: $0.shotData, composedPrompt: $0.composedPrompt)
        })
        guard let data = try? JSONEncoder().encode(store),
              let json = String(data: data, encoding: .utf8) else { return "{\"scenes\":[]}" }
        return json
    }

    private func loadWebView() -> Bool {
        guard let window,
              let html = BundledResource.url("Backlot/backlot.html") else { return false }
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(bridge, name: BacklotBridge.messageName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let webView = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if DEBUG
        webView.isInspectable = true
        #endif
        window.contentView = webView
        pageState = .loading
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        self.webView = webView
        return true
    }

    // MARK: - Agent control

    /// Opens Backlot if needed, waits for the page, and evaluates a script
    /// that must return a string (the agent API returns JSON strings).
    func runAgentScript(_ script: String) async throws -> String {
        if webView == nil {
            guard loadWebView() else { throw BacklotControlError.resourcesMissing }
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        let editor = AppState.shared.activeProject?.editorViewModel
        if bridge.reflectedEditor !== editor {
            await hydrateBin(from: editor)
        }
        return try await evaluate(script)
    }

    /// Ensures the page is loaded and the bin reflects `editor` without reordering
    /// the window — the precondition for a background bake driven off the tool call.
    func prepareForBake(editor: EditorViewModel) async throws {
        if webView == nil {
            guard loadWebView() else { throw BacklotControlError.resourcesMissing }
        }
        if bridge.reflectedEditor !== editor {
            await hydrateBin(from: editor)
        }
    }

    /// Waits for the page and evaluates a String-returning script without
    /// reordering the window — used for background hydration and baking.
    func evaluateQuiet(_ script: String) async throws -> String {
        try await evaluate(script)
    }

    private func evaluate(_ script: String) async throws -> String {
        try await waitForPageReady()
        guard let webView else { throw BacklotControlError.pageFailedToLoad("view unavailable") }
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: BacklotControlError.scriptFailed(error.localizedDescription))
                } else if let string = value as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(throwing: BacklotControlError.unexpectedResult)
                }
            }
        }
    }

    private func waitForPageReady() async throws {
        switch pageState {
        case .ready:
            return
        case .failed(let reason):
            throw BacklotControlError.pageFailedToLoad(reason)
        case .idle:
            throw BacklotControlError.resourcesMissing
        case .loading:
            try await withCheckedThrowingContinuation { pageWaiters.append($0) }
        }
    }

    fileprivate func finishPageLoad(_ result: Result<Void, Error>) {
        switch result {
        case .success: pageState = .ready
        case .failure(let error): pageState = .failed(error.localizedDescription)
        }
        let waiters = pageWaiters
        pageWaiters = []
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    /// Injected at document end: reroutes the page's anchor-based file downloads
    /// (reference frames, OBJ, shot/bin JSON) through the bridge, and adds an
    /// "Add to project media" action under generated fal results.
    private static let bridgeScript = """
    (function(){
      if(!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.carbonara)) return;
      var post = function(msg){ window.webkit.messageHandlers.carbonara.postMessage(msg); };
      document.addEventListener("click", function(e){
        var a = e.target && e.target.closest ? e.target.closest("a[download]") : null;
        if(!a || !a.href) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        var name = a.getAttribute("download") || "backlot-file";
        fetch(a.href)
          .then(function(r){ return r.blob(); })
          .then(function(b){
            var fr = new FileReader();
            fr.onload = function(){ post({kind:"download", filename:name, dataURL:String(fr.result)}); };
            fr.readAsDataURL(b);
          })
          .catch(function(){});
      }, true);
      var gen = document.getElementById("genResult");
      if(gen){
        new MutationObserver(function(){
          var media = gen.querySelector("img[src^='http'], video[src^='http']");
          if(!media || gen.querySelector(".cb-send")) return;
          var btn = document.createElement("button");
          btn.className = "btn btn-primary cb-send";
          btn.style.marginTop = "8px";
          btn.style.width = "100%";
          btn.textContent = "Add to project media";
          btn.addEventListener("click", function(){
            btn.disabled = true;
            btn.textContent = "Sent to project";
            post({kind:"importRemote", url: media.currentSrc || media.src});
          });
          gen.appendChild(btn);
        }).observe(gen, {childList:true, subtree:true});
      }
    })();
    """
}

extension BacklotWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishPageLoad(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishPageLoad(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishPageLoad(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.isFileURL { return .allow }
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }
}

extension BacklotWindowController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, !url.isFileURL {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}
