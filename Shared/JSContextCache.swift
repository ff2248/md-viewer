@preconcurrency import JavaScriptCore
import os

/// Thread-safe lazy cache for a JSContext loaded with a bundled JS file.
final class JSContextCache: Sendable {
    private let lock = OSAllocatedUnfairLock<JSContext?>(initialState: nil)
    private let resource: String
    private let setup: String
    private let globalName: String

    init(resource: String, setup: String = "", globalName: String) {
        self.resource = resource
        self.setup = setup
        self.globalName = globalName
    }

    func context(bundle: Bundle) -> JSContext? {
        lock.withLock { cached in
            if let ctx = cached { return ctx }

            guard let url = bundle.url(forResource: resource, withExtension: "js"),
                  let js = try? String(contentsOf: url, encoding: .utf8),
                  let ctx = JSContext() else { return nil }

            ctx.evaluateScript("var self = this; var window = this; \(setup)")
            ctx.evaluateScript(js)

            let alias = "if(typeof \(globalName)==='undefined' && typeof window.\(globalName)!=='undefined') { var \(globalName)=window.\(globalName); }"
            ctx.evaluateScript(alias)

            guard let test = ctx.evaluateScript("typeof \(globalName)"), test.toString() == "object" else { return nil }

            cached = ctx
            return ctx
        }
    }
}
