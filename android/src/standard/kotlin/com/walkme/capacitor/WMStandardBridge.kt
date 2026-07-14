package com.walkme.capacitor

import android.app.Activity
import com.walkme.api.WalkMeEventUserVarsKey
import com.walkme.api.WalkMeStartOptions
import com.walkme.api.WalkmeDataCenter
import com.walkme.api.info.WMItemInfo
import com.walkme.api.info.WMItemInfoListener
import com.walkme.sdk.WalkMeSDK
import org.json.JSONObject

/** Backs the plugin with `com.walkme.sdk.WalkMeSDK` (core / non-editor artifact). */
class WMStandardBridge : WMBridge {

    override val variantName = "standard"

    override fun start(activity: Activity, options: WMStartOptions) {
        val startOptions = WalkMeStartOptions(
            systemGuid = options.systemGuid,
            environment = options.environment,
            dataCenter = toDataCenter(options.dataCenter),
        )
        startOptions.analyticsEnabled = options.analyticsEnabled
        startOptions.localLogsEnabled = options.localLogsEnabled
        WalkMeSDK.start(activity, startOptions)
        options.language?.let { WalkMeSDK.setLanguage(it) }
        options.userId?.let { WalkMeSDK.setUserId(it) }
    }

    override fun stop() = WalkMeSDK.stop()

    override fun restart() = WalkMeSDK.restart()

    override fun setUserId(userId: String?) = WalkMeSDK.setUserId(userId)

    override fun setLanguage(language: String) = WalkMeSDK.setLanguage(language)

    override fun setVariable(key: String, value: String?) = WalkMeSDK.setVariable(key, value)

    override fun setEventUserVars(values: Map<String, String>) {
        val mapped = values.mapNotNull { (k, v) ->
            runCatching { WalkMeEventUserVarsKey.valueOf(k) }.getOrNull()?.let { it to v }
        }.toMap()
        WalkMeSDK.setEventUserVars(mapped)
    }

    override fun setTenantId(tenantId: String?) = WalkMeSDK.setTenantId(tenantId)

    override fun startItemByID(itemId: String, deepLink: String?) = WalkMeSDK.startItemByID(itemId.toInt(), deepLink)

    override fun dismissItem() = WalkMeSDK.dismissItem()

    override fun sendEvent(name: String, attributes: Map<String, String>?) = WalkMeSDK.sendEvent(name, attributes)

    override fun setEventEmitter(emitter: WMEventEmitter) {
        WalkMeSDK.setItemInfoListener(object : WMItemInfoListener {
            override fun onItemPresented(itemInfo: WMItemInfo) {
                emitter.onItemPresented(itemInfo.itemId, itemInfo.itemActionType, userDataMap(itemInfo))
            }

            override fun onItemDismissed(itemInfo: WMItemInfo) {
                emitter.onItemDismissed(itemInfo.itemId, itemInfo.itemActionType, userDataMap(itemInfo))
            }

            override fun onItemAction(itemInfo: WMItemInfo, args: Map<String, String>?) {
                emitter.onItemAction(itemInfo.itemId, args)
            }
        })

        WalkMeSDK.setAnalyticsListener { eventName, params ->
            emitter.onAnalyticsEvent(
                eventName,
                jsonToMap(params)
            )
        }
    }

    private fun userDataMap(itemInfo: WMItemInfo): Map<String, Any?> =
        itemInfo.userData.let {
            mapOf(
                "sessionDuration" to it.sessionDuration,
                "deviceVersion" to it.deviceVersion,
                "deviceId" to it.deviceId,
                "deviceModel" to it.deviceModel,
                "appVersion" to it.appVersion,
                "appName" to it.appName,
                "locale" to it.locale,
                "sdkVer" to it.sdkVer,
                "sessionId" to it.sessionId,
                "isNewUser" to it.isNewUser,
                "timezone" to it.timezone,
                "network" to it.network,
                "systemName" to it.systemName,
                "timestamp" to it.timestamp,
            )
        }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> =
        json.keys().asSequence().associateWith { json.opt(it) }

    private fun toDataCenter(value: String): WalkmeDataCenter = when (value) {
        "eu" -> WalkmeDataCenter.eu
        "us01" -> WalkmeDataCenter.us01
        "eu01" -> WalkmeDataCenter.eu01
        "prod" -> WalkmeDataCenter.prod
        else -> WalkmeDataCenter.Custom(value)
    }
}

fun createBridge(): WMBridge = WMStandardBridge()
