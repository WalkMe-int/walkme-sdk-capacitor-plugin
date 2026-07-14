import Foundation
import WMBridgeCore
import WalkMeEditor

/// Backs the plugin with `WalkMePowerMode` from the `WalkMeEditor` SPM product.
/// The editor SDK's public API (per WalkMe README) is a subset of the
/// standard SDK's — no restart/dismissItem/tenantId/analytics-or-item
/// callbacks — so those throw `WMBridgeError.unsupportedInVariant`.
public final class WMEditorAdapter: WMBridge {

    public init() {}

    public let variantName = "editor"

    public func start(options: WMStartOptions) {
        let startOptions = WalkMeStartOptions(systemGuid: options.systemGuid)
        startOptions.environment = options.environment
        startOptions.dataCenter = Self.toDataCenter(options.dataCenter)
        startOptions.logsEnabled = options.localLogsEnabled
        options.language.map { startOptions.language = $0 }
        options.userId.map { startOptions.userId = $0 }
        WalkMePowerMode.start(options: startOptions)
    }

    public func stop() {
        WalkMePowerMode.stop()
    }

    public func restart() throws {
        throw WMBridgeError.unsupportedInVariant(method: "restart", variant: variantName)
    }

    public func setUserId(_ userId: String?) {
        if let userId {
            WalkMePowerMode.setUserId(userId)
        }
    }

    public func setLanguage(_ language: String) {
        WalkMePowerMode.setLanguage(language)
    }

    public func setVariable(key: String, value: String?) {
        WalkMePowerMode.setVariable(key: key, value: value)
    }

    public func setEventUserVars(_ values: [String: String]) {
        var mapped: [String: String] = [:]

        for (key, value) in values {
            if let typedKey = WalkMeEventUserVarsKey(rawValue: key) {
                mapped[typedKey.rawValue] = value
            }
        }

        WalkMePowerMode.setEventUserVars(mapped)
    }

    public func setTenantId(_ tenantId: String?) throws {
        WalkMePowerMode.setTenantId(tenantId)
    }

    public func startItem(byID itemId: String, deepLink: String?) {
        guard let id = Int(itemId) else {
            assertionFailure("Invalid itemId: \(itemId)")
            return
        }

        WalkMePowerMode.startItem(byID: id, deepLink: deepLink)
    }

    public func dismissItem() throws {
        WalkMePowerMode.dismissItem()
    }

    public func sendEvent(name: String, attributes: [String: String]?) {
        WalkMePowerMode.sendEvent(name: name, attributes: attributes)
    }

    public func setEventEmitter(_ emitter: WMEventEmitter) {
        // No item/analytics listener hooks exposed by WalkMePowerMode today
        // (per WalkMe README) — nothing to wire up. Kept as a no-op rather
        // than throwing since start() always calls this.
    }

    private static func toDataCenter(_ value: String) -> WalkMeDataCenter {
        switch value {
        case "eu": return .eu
        case "us01": return .us01
        case "eu01": return .eu01
        case "prod": return .prod
        default: return .custom(value)
        }
    }
}

/// Selected by `WalkMePlugin.swift` via `#if WALKME_EDITOR` — see Package.swift.
public func createBridge() -> WMBridge { WMEditorAdapter() }
