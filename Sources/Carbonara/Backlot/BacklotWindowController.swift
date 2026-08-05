import AppKit
import WebKit

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
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        self.webView = webView
        return true
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
