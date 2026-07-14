import Foundation
import Capacitor
import WMBridgeCore

#if WALKME_EDITOR
import WalkMeEditorAdapter
#else
import WalkMeStandardAdapter
#endif

@objc(WalkMePlugin)
public class WalkMePlugin: CAPPlugin, CAPBridgedPlugin, WMEventEmitter {

    public let identifier = "WalkMePlugin"
    public let jsName = "WalkMe"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "restart", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setUserId", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setLanguage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setVariable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEventUserVars", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTenantId", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startItemByID", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "dismissItem", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sendEvent", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getVariant", returnType: CAPPluginReturnPromise),
    ]

    // Exactly one of WMStandardAdapter / WMEditorAdapter is compiled+linked
    // in, chosen by `walkmeVariant` in Package.swift (see the `#if
    // WALKME_EDITOR` import above). This bridge never needs to know which.
    //
    // Named `wmBridge`, not `bridge` — CAPPlugin (our superclass) already
    // declares a public `bridge` property (the Capacitor bridge instance).
    // Reusing that name here would make Swift treat this as an override of
    // an unrelated, differently-typed inherited property, which is what
    // produced "Overriding property must be as accessible as its enclosing
    // type" (the override was `private`, less accessible than the public
    // class requires).
    private lazy var wmBridge: WMBridge = createBridge()

    @objc func start(_ call: CAPPluginCall) {
        guard let systemGuid = call.getString("systemGuid"), !systemGuid.isEmpty else {
            call.reject("systemGuid is required", "WM_INVALID_ARGS")
            return
        }
        let options = WMStartOptions(
            systemGuid: systemGuid,
            environment: call.getString("environment") ?? "Production",
            dataCenter: Self.dataCenterString(call) ?? "prod",
            analyticsEnabled: call.getBool("analyticsEnabled") ?? true,
            localLogsEnabled: call.getBool("localLogsEnabled") ?? false,
            language: call.getString("language"),
            userId: call.getString("userId")
        )
        wmBridge.setEventEmitter(self)
        wmBridge.start(options: options)
        call.resolve()
    }

    @objc func stop(_ call: CAPPluginCall) {
        wmBridge.stop()
        call.resolve()
    }

    @objc func restart(_ call: CAPPluginCall) {
        guarded(call) { try wmBridge.restart() }
    }

    @objc func setUserId(_ call: CAPPluginCall) {
        wmBridge.setUserId(call.getString("userId"))
        call.resolve()
    }

    @objc func setLanguage(_ call: CAPPluginCall) {
        guard let language = call.getString("language"), !language.isEmpty else {
            call.reject("language is required", "WM_INVALID_ARGS")
            return
        }
        wmBridge.setLanguage(language)
        call.resolve()
    }

    @objc func setVariable(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), !key.isEmpty else {
            call.reject("key is required", "WM_INVALID_ARGS")
            return
        }
        wmBridge.setVariable(key: key, value: call.getString("value"))
        call.resolve()
    }

    @objc func setEventUserVars(_ call: CAPPluginCall) {
        let values = (call.getObject("values") ?? [:]).compactMapValues { $0 as? String }
        wmBridge.setEventUserVars(values)
        call.resolve()
    }

    @objc func setTenantId(_ call: CAPPluginCall) {
        guarded(call) { try wmBridge.setTenantId(call.getString("tenantId")) }
    }

    @objc func startItemByID(_ call: CAPPluginCall) {
        guard let itemId = call.getString("itemId"), !itemId.isEmpty else {
            call.reject("itemId is required", "WM_INVALID_ARGS")
            return
        }
        wmBridge.startItem(byID: itemId, deepLink: call.getString("deepLink"))
        call.resolve()
    }

    @objc func dismissItem(_ call: CAPPluginCall) {
        guarded(call) { try wmBridge.dismissItem() }
    }

    @objc func sendEvent(_ call: CAPPluginCall) {
        guard let name = call.getString("name"), !name.isEmpty else {
            call.reject("name is required", "WM_INVALID_ARGS")
            return
        }
        let attrs = (call.getObject("attributes") ?? [:]).compactMapValues { $0 as? String }
        wmBridge.sendEvent(name: name, attributes: attrs)
        call.resolve()
    }

    @objc func getVariant(_ call: CAPPluginCall) {
        call.resolve(["variant": wmBridge.variantName])
    }

    private func guarded(_ call: CAPPluginCall, _ block: () throws -> Void) {
        do {
            try block()
            call.resolve()
        } catch let error as WMBridgeError {
            call.reject(error.description, "WM_UNSUPPORTED_IN_VARIANT")
        } catch {
            call.reject(error.localizedDescription, "WM_NATIVE_ERROR", error)
        }
    }

    private static func dataCenterString(_ call: CAPPluginCall) -> String? {
        // JS side sends dataCenter as either a plain string ("prod" | "eu" |
        // "us01" | "eu01") or an object ({ custom: "qa" }) — handle both.
        if let plain = call.getString("dataCenter") { return plain }
        guard let obj = call.getObject("dataCenter") else { return nil }
        if let custom = obj["custom"] as? String { return custom }
        if let value = obj["value"] as? String { return value }
        return nil
    }

    // MARK: - WMEventEmitter

    public func onItemPresented(itemId: String, itemType: String?, userData: [String: Any]?) {
        notifyListeners("itemPresented", data: itemInfoDict(itemId, itemType, nil, userData))
    }

    public func onItemDismissed(itemId: String, actionType: String?, userData: [String: Any]?) {
        notifyListeners("itemDismissed", data: itemInfoDict(itemId, nil, actionType, userData))
    }

    public func onItemAction(itemId: String, args: [String: String]?) {
        var data: [String: Any] = ["itemInfo": itemInfoDict(itemId, nil, nil, nil)]
        if let args = args { data["args"] = args }
        notifyListeners("itemAction", data: data)
    }

    public func onAnalyticsEvent(eventName: String, params: [String: Any]) {
        notifyListeners("analyticsEvent", data: ["eventName": eventName, "params": params])
    }

    private func itemInfoDict(
        _ itemId: String,
        _ itemType: String?,
        _ actionType: String?,
        _ userData: [String: Any]?
    ) -> [String: Any] {
        var dict: [String: Any] = ["itemId": itemId]
        if let itemType = itemType { dict["itemType"] = itemType }
        if let actionType = actionType { dict["itemActionType"] = actionType }
        if let userData = userData { dict["userData"] = userData }
        return dict
    }
}
