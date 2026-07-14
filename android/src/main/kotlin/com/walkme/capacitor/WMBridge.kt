package com.walkme.capacitor

import android.app.Activity

/**
 * Common contract implemented by exactly one of [WMStandardBridge] (backed by
 * `com.walkme.sdk.WalkMeSDK`) or [WMEditorBridge] (backed by
 * `com.walkme.pm.WalkmeSdkPowerMode`) — whichever one Gradle compiled in for
 * this build's `walkmeVariant`. [WalkMePlugin] talks only to this interface,
 * so it never needs to know which native artifact is actually present.
 *
 * Methods documented as "standard only" in the WalkMe SDK README throw
 * [UnsupportedOperationException] from the editor implementation; the plugin
 * layer turns that into a rejected promise with code `WM_UNSUPPORTED_IN_VARIANT`.
 */
interface WMBridge {

    val variantName: String // "standard" | "editor"

    fun start(activity: Activity, options: WMStartOptions)
    fun stop()

    fun restart()

    fun setUserId(userId: String?)
    fun setLanguage(language: String)
    fun setVariable(key: String, value: String?)
    fun setEventUserVars(values: Map<String, String>)
    fun setTenantId(tenantId: String?)

    fun startItemByID(itemId: String, deepLink: String?)

    fun dismissItem()

    fun sendEvent(name: String, attributes: Map<String, String>?)

    /** Registers native callbacks; bridge implementations forward these to [WMEventEmitter]. */
    fun setEventEmitter(emitter: WMEventEmitter)
}

/** Startup options shared across variants (mirrors `WalkMeStartOptions` on both native SDKs). */
data class WMStartOptions(
    val systemGuid: String,
    val environment: String = "Production",
    val dataCenter: String = "prod",
    val analyticsEnabled: Boolean = true,
    val localLogsEnabled: Boolean = false,
    val language: String? = null,
    val userId: String? = null,
)

/** Sink the bridge implementations push native lifecycle/analytics events into. */
interface WMEventEmitter {
    fun onItemPresented(itemId: String, itemType: String?, userData: Map<String, Any?>?)
    fun onItemDismissed(itemId: String, actionType: String?, userData: Map<String, Any?>?)
    fun onItemAction(itemId: String, args: Map<String, String>?)
    fun onAnalyticsEvent(eventName: String, params: Map<String, Any?>)
}

/** Thrown by a bridge for methods its variant doesn't support; mapped to a rejected JS promise. */
class WMUnsupportedInVariantException(method: String, variant: String) :
    UnsupportedOperationException("$method is not supported by the '$variant' WalkMe variant")
