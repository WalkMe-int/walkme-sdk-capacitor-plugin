import Foundation
import WMBridgeCore
import WalkMe

/// Backs the plugin with `WalkMeSDK` from the `WalkMe` SPM product (core / non-editor).
public final class WMStandardAdapter: WMBridge {

    public init() {}

    public let variantName = "standard"

    // WalkMeSDK.itemCallbacksDelegate is a `weak` property, so the adapter must
    // hold the strong reference or the delegate deallocates immediately and item
    // callbacks never fire.
    private var itemDelegate: WMStandardItemDelegate?

    public func start(options: WMStartOptions) {
        let startOptions = WalkMeStartOptions(systemGuid: options.systemGuid)
        startOptions.environment = options.environment
        startOptions.dataCenter = Self.toDataCenter(options.dataCenter)
        startOptions.analyticMode = options.analyticsEnabled ? .on : .off
        options.language.map { startOptions.language = $0 }
        options.userId.map { startOptions.userId = $0 }
        WalkMeSDK.start(options: startOptions)
    }

    public func stop() {
        WalkMeSDK.stop()
    }

    public func restart() {
        WalkMeSDK.restart()
    }

    public func setUserId(_ userId: String?) {
        WalkMeSDK.setUserId(userId)
    }

    public func setLanguage(_ language: String) {
        WalkMeSDK.setLanguage(language)
    }

    public func setVariable(key: String, value: String?) {
        WalkMeSDK.setVariable(key: key, value: value)
    }

    public func setEventUserVars(_ values: [String: String]) {
        var mapped: [WalkMeEventUserVarsKey: String] = [:]
        for (key, value) in values {
            if let typedKey = WalkMeEventUserVarsKey(rawValue: key) {
                mapped[typedKey] = value
            }
        }
        WalkMeSDK.setEventUserVars(mapped)
    }

    public func setTenantId(_ tenantId: String?) {
        WalkMeSDK.setTenantId(tenantId)
    }

    public func startItem(byID itemId: String, deepLink: String?) {
        WalkMeSDK.startItem(byID: itemId, deepLink: deepLink)
    }

    public func dismissItem() {
        WalkMeSDK.dismissItem()
    }

    public func sendEvent(name: String, attributes: [String: String]?) {
        WalkMeSDK.sendEvent(name: name, attributes: attributes)
    }

    public func setEventEmitter(_ emitter: WMEventEmitter) {
        WalkMeSDK.setAnalyticsHandler { info in
            emitter.onAnalyticsEvent(eventName: "\(info.eventType)", params: info.payload)
        }
        let delegate = WMStandardItemDelegate(emitter: emitter)
        itemDelegate = delegate // retained because the SDK holds it weakly
        WalkMeSDK.setItemCallbacksDelegate(delegate)
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

private final class WMStandardItemDelegate: NSObject, WMItemCallbacksDelegate {
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
public func createBridge() -> WMBridge { WMStandardAdapter() }
