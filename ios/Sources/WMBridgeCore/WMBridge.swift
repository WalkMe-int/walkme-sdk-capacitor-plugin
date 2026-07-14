import Foundation

/// Common contract implemented by exactly one of `WMStandardAdapter` (backed
/// by `WalkMeSDK` from the `WalkMe` product) or `WMEditorAdapter` (backed by
/// `WalkMePowerMode` from the `WalkMeEditor` product) — whichever adapter
/// target Package.swift links in for the chosen `walkmeVariant`.
///
/// Methods documented as "standard only" in the WalkMe SDK README throw
/// `WMBridgeError.unsupportedInVariant` from the editor implementation.
public protocol WMBridge: AnyObject {
    var variantName: String { get } // "standard" | "editor"

    func start(options: WMStartOptions)
    func stop()

    /// Standard variant only.
    func restart() throws

    func setUserId(_ userId: String?)
    func setLanguage(_ language: String)
    func setVariable(key: String, value: String?)
    func setEventUserVars(_ values: [String: String])

    /// Standard variant only.
    func setTenantId(_ tenantId: String?) throws

    func startItem(byID itemId: String, deepLink: String?)

    /// Standard variant only.
    func dismissItem() throws

    func sendEvent(name: String, attributes: [String: String]?)

    /// Registers native callbacks; adapters forward these to the emitter.
    func setEventEmitter(_ emitter: WMEventEmitter)
}

public struct WMStartOptions {
    public let systemGuid: String
    public let environment: String
    public let dataCenter: String // "prod" | "eu" | "us01" | "eu01" | custom string
    public let analyticsEnabled: Bool
    public let localLogsEnabled: Bool
    public let language: String?
    public let userId: String?

    public init(
        systemGuid: String,
        environment: String = "Production",
        dataCenter: String = "prod",
        analyticsEnabled: Bool = true,
        localLogsEnabled: Bool = false,
        language: String? = nil,
        userId: String? = nil
    ) {
        self.systemGuid = systemGuid
        self.environment = environment
        self.dataCenter = dataCenter
        self.analyticsEnabled = analyticsEnabled
        self.localLogsEnabled = localLogsEnabled
        self.language = language
        self.userId = userId
    }
}

public protocol WMEventEmitter: AnyObject {
    func onItemPresented(itemId: String, itemType: String?, userData: [String: Any]?)
    func onItemDismissed(itemId: String, actionType: String?, userData: [String: Any]?)
    func onItemAction(itemId: String, args: [String: String]?)
    func onAnalyticsEvent(eventName: String, params: [String: Any])
}

public enum WMBridgeError: Error, CustomStringConvertible {
    case unsupportedInVariant(method: String, variant: String)

    public var description: String {
        switch self {
        case let .unsupportedInVariant(method, variant):
            return "\(method) is not supported by the '\(variant)' WalkMe variant"
        }
    }
}
