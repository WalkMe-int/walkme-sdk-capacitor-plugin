import Foundation
import WMBridgeCore
import WalkMeEditor

/// Backs the plugin with `WalkMePowerMode` from the `WalkMeEditor` SPM product.
/// `WalkMePowerMode` exposes static `restart`/`dismissItem`/`setTenantId`, so
/// those are forwarded like any other call. The only real gap vs. the standard
/// SDK today is the item/analytics listener callbacks, which `WalkMePowerMode`
/// doesn't surface — see `setEventEmitter`.
public final class WMEditorAdapter: WMBridge {

    public init() {}

    public let variantName = "editor"

    // WalkMePowerMode.itemCallbacksDelegate is a `weak` property, so the adapter
    // must hold the strong reference or the delegate deallocates immediately and
    // item callbacks never fire.
    private var itemDelegate: WMEditorItemDelegate?

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

    public func restart() {
        WalkMePowerMode.restart()
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

    public func setTenantId(_ tenantId: String?) {
        WalkMePowerMode.setTenantId(tenantId)
    }

    public func startItem(byID itemId: String, deepLink: String?) {
        guard let id = Int(itemId) else {
            assertionFailure("Invalid itemId: \(itemId)")
            return
        }

        WalkMePowerMode.startItem(byID: id, deepLink: deepLink)
    }

    public func dismissItem() {
        WalkMePowerMode.dismissItem()
    }

    public func sendEvent(name: String, attributes: [String: String]?) {
        WalkMePowerMode.sendEvent(name: name, attributes: attributes)
    }

    public func setEventEmitter(_ emitter: WMEventEmitter) {
        // WalkMePowerMode exposes the same analytics/item callbacks as the
        // standard SDK, so forward them to the emitter (mirrors WMStandardAdapter).
        WalkMePowerMode.setAnalyticsHandler { info in
            emitter.onAnalyticsEvent(eventName: "\(info.eventType)", params: info.payload)
        }
        let delegate = WMEditorItemDelegate(emitter: emitter)
        itemDelegate = delegate // retained because the SDK holds it weakly
        WalkMePowerMode.setItemCallbacksDelegate(delegate)
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

/// Forwards WalkMePowerMode item lifecycle callbacks to the plugin emitter.
/// NSObject-based because `WMItemCallbacksDelegate` is an `@objc` protocol with
/// optional methods.
private final class WMEditorItemDelegate: NSObject, WMItemCallbacksDelegate {
    private weak var emitter: WMEventEmitter?

    init(emitter: WMEventEmitter) {
        self.emitter = emitter
    }

    func itemWillShow(_ itemInfo: WalkMeItemInfo) {
        emitter?.onItemPresented(itemId: "\(itemInfo.itemId)", itemType: itemInfo.itemType, userData: nil)
    }

    func itemDidDismiss(_ itemInfo: WalkMeItemInfo) {
        emitter?.onItemDismissed(itemId: "\(itemInfo.itemId)", actionType: itemInfo.action, userData: nil)
    }
}

/// Selected by `WalkMePlugin.swift` via `#if WALKME_EDITOR` — see Package.swift.
public func createBridge() -> WMBridge { WMEditorAdapter() }
