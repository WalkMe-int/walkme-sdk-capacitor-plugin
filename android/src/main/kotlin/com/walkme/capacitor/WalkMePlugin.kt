package com.walkme.capacitor

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "WalkMe")
class WalkMePlugin : Plugin(), WMEventEmitter {

    // Exactly one of these is compiled in, per the `walkmeVariant` Gradle
    // property resolved in android/build.gradle (src/standard vs src/editor
    // source sets). See WMBridge.kt for the shared contract.
    private val bridge: WMBridge by lazy { createBridge() }

    @PluginMethod
    fun start(call: PluginCall) {
        val systemGuid = call.getString("systemGuid")
        if (systemGuid.isNullOrBlank()) {
            call.reject("systemGuid is required", "WM_INVALID_ARGS")
            return
        }
        val options = WMStartOptions(
            systemGuid = systemGuid,
            environment = call.getString("environment", "Production")!!,
            dataCenter = dataCenterToString(call) ?: "prod",
            analyticsEnabled = call.getBoolean("analyticsEnabled", true)!!,
            localLogsEnabled = call.getBoolean("localLogsEnabled", false)!!,
            language = call.getString("language"),
            userId = call.getString("userId"),
        )
        runCatching {
            bridge.setEventEmitter(this)
            bridge.start(activity, options)
        }.onSuccess { call.resolve() }
            .onFailure { call.rejectWith(it) }
    }

    @PluginMethod
    fun stop(call: PluginCall) = guarded(call) { bridge.stop() }

    @PluginMethod
    fun restart(call: PluginCall) = guarded(call) { bridge.restart() }

    @PluginMethod
    fun setUserId(call: PluginCall) = guarded(call) { bridge.setUserId(call.getString("userId")) }

    @PluginMethod
    fun setLanguage(call: PluginCall) {
        val language = call.getString("language")
        if (language.isNullOrBlank()) {
            call.reject("language is required", "WM_INVALID_ARGS")
            return
        }
        guarded(call) { bridge.setLanguage(language) }
    }

    @PluginMethod
    fun setVariable(call: PluginCall) {
        val key = call.getString("key")
        if (key.isNullOrBlank()) {
            call.reject("key is required", "WM_INVALID_ARGS")
            return
        }
        guarded(call) { bridge.setVariable(key, call.getString("value")) }
    }

    @PluginMethod
    fun setEventUserVars(call: PluginCall) {
        val values = call.getObject("values") ?: JSObject()
        val map = mutableMapOf<String, String>()
        values.keys().forEach { k -> values.getString(k)?.let { map[k] = it } }
        guarded(call) { bridge.setEventUserVars(map) }
    }

    @PluginMethod
    fun setTenantId(call: PluginCall) = guarded(call) { bridge.setTenantId(call.getString("tenantId")) }

    @PluginMethod
    fun startItemByID(call: PluginCall) {
        val itemId = call.getString("itemId")
        if (itemId.isNullOrBlank()) {
            call.reject("itemId is required", "WM_INVALID_ARGS")
            return
        }
        guarded(call) { bridge.startItemByID(itemId, call.getString("deepLink")) }
    }

    @PluginMethod
    fun dismissItem(call: PluginCall) = guarded(call) { bridge.dismissItem() }

    @PluginMethod
    fun sendEvent(call: PluginCall) {
        val name = call.getString("name")
        if (name.isNullOrBlank()) {
            call.reject("name is required", "WM_INVALID_ARGS")
            return
        }
        val attrs = call.getObject("attributes")
        // JSObject.keys() returns a raw Iterator, which `associateWith` has no
        // overload for (only Iterable/Sequence/Array/...) — go through
        // asSequence() first.
        val map = attrs?.keys()?.asSequence()?.associateWith { attrs.getString(it) ?: "" }
        guarded(call) { bridge.sendEvent(name, map) }
    }

    @PluginMethod
    fun getVariant(call: PluginCall) {
        val result = JSObject()
        result.put("variant", bridge.variantName)
        call.resolve(result)
    }

    private fun guarded(call: PluginCall, block: () -> Unit) {
        runCatching(block).onSuccess { call.resolve() }.onFailure { call.rejectWith(it) }
    }

    private fun PluginCall.rejectWith(t: Throwable) {
        if (t is WMUnsupportedInVariantException) {
            reject(t.message, "WM_UNSUPPORTED_IN_VARIANT")
        } else {
            // Capacitor's PluginCall.reject(String, String, Exception) only
            // accepts java.lang.Exception, not the broader Throwable that
            // runCatching hands us (e.g. it'd reject an Error) — wrap.
            val exception = t as? Exception ?: Exception(t)
            reject(t.message ?: "WalkMe native call failed", "WM_NATIVE_ERROR", exception)
        }
    }

    private fun dataCenterToString(call: PluginCall): String? {
        // JS side sends dataCenter as either a plain string ("prod" | "eu" |
        // "us01" | "eu01") or an object ({ custom: "qa" }) — handle both.
        call.getString("dataCenter")?.let { return it }
        val obj = call.getObject("dataCenter") ?: return null
        obj.getString("custom")?.let { return it }
        obj.getString("value")?.let { return it }
        return null
    }

    // --- WMEventEmitter: forwards native lifecycle/analytics callbacks to JS ---

    override fun onItemPresented(itemId: String, itemType: String?, userData: Map<String, Any?>?) {
        notifyListeners("itemPresented", itemInfoObject(itemId, itemType, null, userData))
    }

    override fun onItemDismissed(itemId: String, actionType: String?, userData: Map<String, Any?>?) {
        notifyListeners("itemDismissed", itemInfoObject(itemId, null, actionType, userData))
    }

    override fun onItemAction(itemId: String, args: Map<String, String>?) {
        val data = JSObject()
        data.put("itemInfo", itemInfoObject(itemId, null, null, null))
        args?.let { a ->
            val argsObj = JSObject()
            a.forEach { (k, v) -> argsObj.put(k, v) }
            data.put("args", argsObj)
        }
        notifyListeners("itemAction", data)
    }

    override fun onAnalyticsEvent(eventName: String, params: Map<String, Any?>) {
        val data = JSObject()
        data.put("eventName", eventName)
        val paramsObj = JSObject()
        params.forEach { (k, v) -> paramsObj.put(k, v) }
        data.put("params", paramsObj)
        notifyListeners("analyticsEvent", data)
    }

    private fun itemInfoObject(
        itemId: String,
        itemType: String?,
        actionType: String?,
        userData: Map<String, Any?>?,
    ): JSObject {
        val obj = JSObject()
        obj.put("itemId", itemId)
        itemType?.let { obj.put("itemType", it) }
        actionType?.let { obj.put("itemActionType", it) }
        userData?.let { ud ->
            val udObj = JSObject()
            ud.forEach { (k, v) -> udObj.put(k, v) }
            obj.put("userData", udObj)
        }
        return obj
    }
}

// `createBridge()` is a plain top-level function defined once, by whichever
// single variant source set Gradle compiled in — see WMStandardBridge.kt
// (src/standard/kotlin) and WMEditorBridge.kt (src/editor/kotlin). Only one
// of those two files is ever part of the build, so there's no name clash.
