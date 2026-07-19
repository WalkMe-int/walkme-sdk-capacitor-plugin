package com.walkme.capacitor

import android.app.Activity
import com.walkme.api.WalkMeEventUserVarsKey
import com.walkme.api.WalkMeStartOptions
import com.walkme.api.WalkmeDataCenter
import com.walkme.pm.WalkmeSdkPowerMode

/**
 * Backs the plugin with `com.walkme.pm.WalkmeSdkPowerMode` (Power Mode /
 * editor artifact). `WalkmeSdkPowerMode` exposes restart/dismissItem/tenantId,
 * so those are forwarded like any other call. The only real gap vs. the
 * standard SDK today is item-analytics listener registration, which the editor
 * SDK doesn't surface — see [setEventEmitter].
 */
class WMEditorBridge : WMBridge {

    override val variantName = "editor"

    override fun start(activity: Activity, options: WMStartOptions) {
        val startOptions = WalkMeStartOptions(
            systemGuid = options.systemGuid,
            environment = options.environment,
            dataCenter = toDataCenter(options.dataCenter),
        )
        WalkmeSdkPowerMode.start(activity, startOptions)
        options.language?.let { WalkmeSdkPowerMode.setLanguage(it) }
        options.userId?.let { WalkmeSdkPowerMode.setUserId(it) }
    }

    override fun stop() = WalkmeSdkPowerMode.stop()

    override fun restart() = WalkmeSdkPowerMode.restart()

    override fun setUserId(userId: String?) = WalkmeSdkPowerMode.setUserId(userId)

    override fun setLanguage(language: String) = WalkmeSdkPowerMode.setLanguage(language)

    override fun setVariable(key: String, value: String?) = WalkmeSdkPowerMode.setVariable(key, value)

    override fun setEventUserVars(values: Map<String, String>) {
        val mapped = values.mapNotNull { (k, v) ->
            runCatching { WalkMeEventUserVarsKey.valueOf(k) }.getOrNull()?.let { it to v }
        }.toMap()
        WalkmeSdkPowerMode.setEventUserVars(mapped)
    }

    override fun setTenantId(tenantId: String?) =
        WalkmeSdkPowerMode.setTenantId(tenantId)

    override fun startItemByID(itemId: String, deepLink: String?) =
        WalkmeSdkPowerMode.startItemByID(itemId.toInt(), deepLink)

    override fun dismissItem() = WalkmeSdkPowerMode.dismissItem()

    override fun sendEvent(name: String, attributes: Map<String, String>?) =
        WalkmeSdkPowerMode.sendEvent(name, attributes)

    override fun setEventEmitter(emitter: WMEventEmitter) {
        // The editor SDK's public API (per WalkMe README) does not expose
        // item-info / analytics listener registration the way the standard
        // SDK does, so there is nothing to wire up here today. Kept as a
        // no-op (rather than throwing) since start() always calls this.
    }

    private fun toDataCenter(value: String): WalkmeDataCenter = when (value) {
        "eu" -> WalkmeDataCenter.eu
        "us01" -> WalkmeDataCenter.us01
        "eu01" -> WalkmeDataCenter.eu01
        "prod" -> WalkmeDataCenter.prod
        else -> WalkmeDataCenter.Custom(value)
    }
}

fun createBridge(): WMBridge = WMEditorBridge()
