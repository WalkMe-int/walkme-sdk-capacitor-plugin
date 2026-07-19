/**
 * WalkMe Capacitor plugin — unified TypeScript API.
 *
 * This single API surfaces BOTH WalkMe native SDK variants:
 *  - "standard"  -> walkme-android-sdk        / walkme-ios-sdk
 *  - "editor"    -> walkme-android-sdk-editor  / walkme-ios-sdk-editor (Power Mode)
 *
 * Which variant is actually compiled into the app is a native, build-time
 * decision (see README "Choosing a variant") because the underlying WalkMe
 * artifacts must not be linked together. Both variants currently support the
 * full API surface below; the one real editor gap is the item/analytics
 * listeners, which simply never fire on the editor variant.
 */

export type WalkmeDataCenter = 'prod' | 'eu' | 'us01' | 'eu01' | { custom: string };

export interface WalkMeStartOptions {
  /** WalkMe system GUID (required). */
  systemGuid: string;
  /** Environment name, e.g. "Production". Defaults to "Production". */
  environment?: string;
  /** Data center region. Defaults to "prod". */
  dataCenter?: WalkmeDataCenter;
  /**
   * When false, the SDK does not send analytics/events to WalkMe.
   * Standard variant only; ignored (always effectively "on") on editor.
   * Defaults to true.
   */
  analyticsEnabled?: boolean;
  /** Verbose native logging. Defaults to false. */
  localLogsEnabled?: boolean;
  /** Default UI language code. */
  language?: string;
  /** End-user id, applied at start instead of a follow-up setUserId call. */
  userId?: string;
}

export type WalkMeEventUserVarsKey = 'NAME' | 'ROLE' | 'TYPE' | 'STATUS' | 'INFO';

export interface WMUserData {
  userAttributesMap?: Record<string, string>;
  sessionDuration?: number;
  deviceVersion?: string;
  deviceId?: string;
  deviceModel?: string;
  deviceOrientation?: string;
  appVersion?: string;
  appName?: string;
  locale?: string;
  sdkVer?: string;
  sessionId?: string;
  isNewUser?: boolean;
  timezone?: string;
  network?: string;
  systemName?: string;
  timestamp?: number;
}

export interface WMItemInfo {
  itemId: string;
  /** "Flow" | "ShoutOut" | "Launcher" (standard/iOS) or dismiss-action type, depending on event. */
  itemType?: string;
  itemActionType?: string;
  userData?: WMUserData;
}

export interface WMItemActionEvent {
  itemInfo: WMItemInfo;
  args?: Record<string, string>;
}

export interface WMAnalyticsEvent {
  eventName: string;
  params: Record<string, unknown>;
}

export interface StartItemOptions {
  itemId: string;
  /** Optional deep link URI opened (same-package ACTION_VIEW / openURL) before the item plays. */
  deepLink?: string;
}

export interface SendEventOptions {
  name: string;
  attributes?: Record<string, string>;
}

export interface SetVariableOptions {
  key: string;
  value?: string | null;
}

export interface WalkMePlugin {
  /** Initialize and show WalkMe for the current session. */
  start(options: WalkMeStartOptions): Promise<void>;
  /** Tear down the SDK and release resources. */
  stop(): Promise<void>;
  /** Re-initialize with the same options/host as the last successful start(). */
  restart(): Promise<void>;
  setUserId(options: { userId: string | null }): Promise<void>;
  setLanguage(options: { language: string }): Promise<void>;
  setVariable(options: SetVariableOptions): Promise<void>;
  setEventUserVars(options: { values: Partial<Record<WalkMeEventUserVarsKey, string>> }): Promise<void>;
  /** Set/clear the tenant id (max 50 chars, persisted across sessions). */
  setTenantId(options: { tenantId: string | null }): Promise<void>;
  /** Force-play a promotion by item id, optionally resolving a deep link first. */
  startItemByID(options: StartItemOptions): Promise<void>;
  /** Dismiss the currently presented item (not launchers). */
  dismissItem(): Promise<void>;
  sendEvent(options: SendEventOptions): Promise<void>;

  /** Fired right before a deployable item is shown. */
  addListener(
    eventName: 'itemPresented',
    listenerFunc: (info: WMItemInfo) => void,
  ): Promise<import('@capacitor/core').PluginListenerHandle>;
  /** Fired after a deployable item is dismissed. */
  addListener(
    eventName: 'itemDismissed',
    listenerFunc: (info: WMItemInfo) => void,
  ): Promise<import('@capacitor/core').PluginListenerHandle>;
  /** Fired when the user performs an action on a deployable (e.g. button click). */
  addListener(
    eventName: 'itemAction',
    listenerFunc: (event: WMItemActionEvent) => void,
  ): Promise<import('@capacitor/core').PluginListenerHandle>;
  /** Fired after an analytics event is successfully posted to WalkMe. */
  addListener(
    eventName: 'analyticsEvent',
    listenerFunc: (event: WMAnalyticsEvent) => void,
  ): Promise<import('@capacitor/core').PluginListenerHandle>;

  removeAllListeners(): Promise<void>;

  /** Returns which native variant ("standard" | "editor") this build was linked against. */
  getVariant(): Promise<{ variant: 'standard' | 'editor' }>;
}
