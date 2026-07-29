# @walkme-mobile/capacitor-plugin

Capacitor bridge for **WalkMe** and WalkMe Power Mode (**WalkMeEditor**) SDKs on **Android** and **iOS**.

## Overview

- One JS/TS API (`WalkMe`) bridges to the native SDK on both platforms.
- Two **flavors**: standard **WalkMe** and Power Mode **WalkMeEditor**. Pick the flavor once in your app's `package.json` — no code changes needed.

|                     | Android              | iOS                    |
| ------------------- | -------------------- | ---------------------- |
| Min OS               | Android 7.0 (API 24) | iOS 14                 |
| Native SDK source    | JitPack               | Swift Package Manager  |
| Required Capacitor    | 6+ (Android)          | 8+ |

The two variants of each native SDK must never be linked into the same app build (per WalkMe's own docs), so which one this plugin compiles against is a **one-time native project setting**, not a runtime choice.

> This plugin ships only a Swift Package Manager manifest for iOS — no CocoaPods `.podspec` — so a CocoaPods-based Capacitor iOS project cannot consume it. (CocoaPods itself is being sunset industry-wide — the CocoaPods Specs repo goes read-only Dec 2, 2026 — so this is the forward-compatible path.) The WalkMe iOS SDK is distributed only via SPM, so SPM support isn't optional — Capacitor 8 is the first version where SPM is the default iOS project structure, which is why iOS requires 8+ with no earlier fallback.

---

## Installation

```bash
npm install @walkme-mobile/capacitor-plugin
npx cap sync
```

The plugin is autolinked on both platforms once the steps below are wired in — no manual native registration needed beyond that.

---

## Select a Flavor

Add a `walkme` block to your app's `package.json`. **Both platforms read this same field** — you only set it once:

```json
{
  "dependencies": {
    "@walkme-mobile/capacitor-plugin": "..."
  },
  "walkme": {
    "walkmeMode": "WalkMeEditor"
  }
}
```

| `walkmeMode` value       | SDK                                       |
| ------------------------ | ------------------------------------------ |
| omitted, or `"WalkMe"`    | standard **WalkMe** (default)             |
| `"WalkMeEditor"`          | Power Mode (**WalkMeEditor**)             |

Values are case-insensitive. An unrecognized value fails the build on Android (`GradleException` with a clear message); on iOS it logs a warning during SPM resolution and falls back to `"standard"` rather than failing the build.

**CI / one-off override (either platform):** the `WALKME_FLAVOR` env var takes precedence over `package.json` — e.g. `WALKME_FLAVOR=WalkMeEditor npx cap sync`.

Even though the config lives in one place, Android and iOS still *apply* it differently under the hood, because Gradle and Swift Package Manager aren't symmetric — see the platform sections below.

---

## Android Setup

### 1. Apply the bridge Gradle script in `android/app/build.gradle`

Add one line at the top of your app's `build.gradle`:

```groovy
apply from: "../../node_modules/@walkme-mobile/capacitor-plugin/android/walkme.gradle"
```

The script reads `walkme.walkmeMode` from your app's `package.json`, validates it early (a typo fails the build with a clear message instead of a confusing "could not resolve dependency" error later), and adds the JitPack repository automatically — no manual repo config needed. (Gradle repository declarations inside the plugin's own `build.gradle` aren't enough on their own: Gradle resolves `:app`'s classpath using only `:app`'s own — or the build's centrally-managed — repositories, never a dependency project's.)

Nothing else to run beyond that: `@walkme-mobile/capacitor-plugin/android/build.gradle` reads `walkme.walkmeMode` straight out of your app's `package.json` at every build (Gradle's real multi-project graph makes this possible).

### 2. (Optional) Pin a specific SDK version

In your app's root `android/build.gradle`:

```groovy
ext {
    walkmeVersion       = '1.1.2'  // for the WalkMe (standard) flavor
    walkmeEditorVersion = '1.1.2'  // for the WalkMeEditor flavor
}
```

If omitted, the latest published version (`+`) is used.

---

## iOS Setup

> Swift Package Manager has no equivalent of Gradle's project graph — a package's `Package.swift` has no way to see "the app that's consuming me" or read its files. This plugin's `ios/Package.swift` works around that itself: it walks up from its own location (inside your `node_modules`) to find your app's `package.json` and reads `walkme.walkmeMode` (and optional `walkmeVersion`) directly — no script or build step needed for variant selection. The one real gap Android doesn't have is a Capacitor/SPM project-wiring bug (below), which does need a one-time setup step that then runs automatically forever.

### 1. Fix the Capacitor 8 SPM gap + linker flag

```bash
npx wm-capacitor-fix-ios-project
```

There's an open upstream issue (ionic-team/capacitor#8325) where `npx cap sync ios` regenerates `ios/App/CapApp-SPM/Package.swift` from scratch and doesn't reliably keep locally-pathed plugin SPM packages wired into it — so this plugin can silently disappear from your app's dependency graph on **every** `cap sync`, not just the first one, producing a `{"code":"UNIMPLEMENTED"}` error at runtime with no other symptoms. Separately, because this plugin ships as a Swift Package Manager (static-by-default) library, iOS's Objective-C-runtime-based plugin auto-discovery needs the app target's **Other Linker Flags** to include `-ObjC`, or the linker can drop the plugin's classes as "unreferenced."

This script fixes both, and is safe to re-run any number of times (it only adds what's missing — see "How the iOS fix script works" below for the mechanics).

### 2. Wire the script into your `package.json`

```json
"scripts": {
  "postinstall": "wm-capacitor-fix-ios-project",
  "capacitor:sync:after": "wm-capacitor-fix-ios-project"
}
```

`capacitor:sync:after` is an official [Capacitor CLI hook](https://capacitorjs.com/docs/cli/hooks) — with it wired in, the fix reapplies automatically after every `npm install` *and* every `cap sync`, the two moments that can undo it. You should never need to hand-edit `CapApp-SPM/Package.swift` or the Xcode project's linker flags again.

### 3. Install & run

```bash
npm install
npx cap sync ios
npx cap open ios
```

In Xcode: quit and reopen after the first sync (so it re-resolves Swift packages), Product → Clean Build Folder, then build & run.

To switch flavors later, just edit `walkme.walkmeMode` in `package.json` and re-run `npx cap sync ios` — `Package.swift` picks up the new value on the next SPM resolution, no extra command needed.

---

## How the iOS fix script works

The script ships inside this npm package (`scripts/`) and is exposed as a `bin` entry, so `npx` finds it without any path fiddling.

### `wm-capacitor-fix-ios-project`

Two independent fixes, both idempotent (re-running only adds what's missing, never duplicates):

1. **Re-adds this plugin to `ios/App/CapApp-SPM/Package.swift`.** Locates wherever `@walkme-mobile/capacitor-plugin` actually resolves to on disk (a real `node_modules` install, or — in local development — a `file:` symlink to a sibling folder), computes the correct relative SPM `path:`, and splices in the `.package(...)` + `.product(...)` entries if they're missing.
2. **Adds `-ObjC` to the app target's Other Linker Flags.** Uses the `xcode` npm package *read-only*, purely to locate the exact build-configuration UUIDs belonging to the app's own `PBXNativeTarget` (not the project-level defaults, and not any test targets). The actual edit is a direct text splice into `project.pbxproj`, not the `xcode` package's own `writeSync()` — in testing, that full-file re-serialization duplicated `OTHER_LDFLAGS` into unrelated project-level configs instead of only the intended target, which is not a risk worth taking against a real Xcode project file.

Both assume Capacitor's default iOS project layout (`ios/App/...`). They no-op with a log line (not an error) if that layout isn't found — e.g. the iOS platform hasn't been added yet.

---

## Usage

### Quick start

```ts
import { WalkMe } from '@walkme-mobile/capacitor-plugin';

await WalkMe.start({ systemGuid: 'YOUR_SYSTEM_GUID', environment: 'Production', dataCenter: 'prod' });
```

Replace `YOUR_SYSTEM_GUID` with the GUID from your WalkMe console. All other `start` options are optional — see [`WalkMeStartOptions`](#walkmestartoptions) below.

### Other methods

```ts
await WalkMe.stop();
await WalkMe.restart();
await WalkMe.setUserId({ userId: 'user-123' });
await WalkMe.setVariable({ key: 'plan', value: 'premium' });
await WalkMe.setEventUserVars({ values: { NAME: 'John Doe', ROLE: 'admin' } });
await WalkMe.setLanguage({ language: 'en' });
await WalkMe.sendEvent({ name: 'button_clicked', attributes: { screen: 'home' } });
await WalkMe.startItemByID({ itemId: '42' });
await WalkMe.dismissItem();
const { variant } = await WalkMe.getVariant(); // 'standard' | 'editor'
```

### Item lifecycle listeners

```ts
const presented = await WalkMe.addListener('itemPresented', (info) => {
  console.log('Item shown:', info.itemId);
});
const dismissed = await WalkMe.addListener('itemDismissed', (info) => {
  console.log('Item dismissed:', info.itemId);
});
const action = await WalkMe.addListener('itemAction', (event) => {
  console.log('Item action:', event.itemInfo.itemActionType, event.args); // Android only carries args
});

// Clean up when no longer needed:
await presented.remove();
await dismissed.remove();
await action.remove();
```

### Analytics listener

```ts
const analytics = await WalkMe.addListener('analyticsEvent', (event) => {
  console.log('Analytics event:', event.eventName, event.params);
});

// later:
await analytics.remove();
// or clear everything at once:
await WalkMe.removeAllListeners();
```

---

## API Reference

See `src/definitions.ts` for the full, authoritative TypeScript surface. Summary:

| Method                          | Parameters                    | Description                                       |
| -------------------------------- | ------------------------------ | --------------------------------------------------- |
| `start(options)`                 | `WalkMeStartOptions`            | Start the SDK                                       |
| `stop()`                         | —                               | Stop the SDK                                        |
| `restart()`                      | —                               | Re-initialize with the same options as the last `start()` |
| `setUserId(options)`              | `{ userId: string \| null }`    | Set the end-user id                                 |
| `setLanguage(options)`            | `{ language: string }`          | Set the display language                            |
| `setVariable(options)`            | `SetVariableOptions`             | Set a segmentation variable                         |
| `setEventUserVars(options)`       | `{ values: Partial<Record<WalkMeEventUserVarsKey, string>> }` | Set event user attributes  |
| `setTenantId(options)`            | `{ tenantId: string \| null }`  | Set/clear the tenant id (max 50 chars, persisted)   |
| `startItemByID(options)`          | `StartItemOptions`               | Force-play a promotion by item id, optional deep link |
| `dismissItem()`                   | —                               | Dismiss the currently presented item (not launchers) |
| `sendEvent(options)`              | `SendEventOptions`                | Send a custom event                                 |
| `getVariant()`                    | —                               | Which native variant (`'standard'` \| `'editor'`) this build was linked against |
| `addListener(eventName, cb)`      | see below                       | Register a listener for one of the 4 event types    |
| `removeAllListeners()`            | —                               | Clear every registered listener                     |

Both variants support the full method set above. The item lifecycle / analytics listeners are the one exception: they never fire on the editor (WalkMeEditor) variant, which doesn't expose those native callbacks.

### `WalkMeStartOptions`

| Property           | Type                   | Required | Default        |
| ------------------- | ----------------------- | -------- | -------------- |
| `systemGuid`         | `string`                 | ✅        | —              |
| `environment`        | `string`                 |          | `'Production'` |
| `dataCenter`         | `'prod' \| 'eu' \| 'us01' \| 'eu01' \| { custom: string }` |  | `'prod'`       |
| `analyticsEnabled`   | `boolean` (standard only) |          | `true`         |
| `localLogsEnabled`   | `boolean`                |          | `false`        |
| `language`           | `string`                 |          | —              |
| `userId`             | `string`                 |          | —              |

### Event listeners

| Event name        | Callback payload    | Notes                                                |
| ------------------ | -------------------- | ------------------------------------------------------ |
| `itemPresented`     | `WMItemInfo`          | Fired right before a deployable item is shown         |
| `itemDismissed`     | `WMItemInfo`          | Fired after a deployable item is dismissed            |
| `itemAction`        | `WMItemActionEvent`   | Fired on a user action within an item; `args` is Android-only |
| `analyticsEvent`    | `WMAnalyticsEvent`    | Fired after an analytics event is posted to WalkMe    |

### `WMItemInfo`

| Field              | Type                | Notes                                     |
| -------------------- | -------------------- | -------------------------------------------- |
| `itemId`              | `string`              |                                               |
| `itemType`            | `string?`             | e.g. `"Flow"` / `"ShoutOut"` / `"Launcher"`  |
| `itemActionType`      | `string?`             | Dismiss/action type, depending on the event  |
| `userData`            | `WMUserData?`         | Device/session metadata                      |

### `WMUserData`

| Field               | Type       |
| --------------------- | ----------- |
| `userAttributesMap`   | `Record<string, string>?` |
| `sessionDuration`     | `number?`  |
| `deviceVersion`       | `string?`  |
| `deviceId`            | `string?`  |
| `deviceModel`         | `string?`  |
| `deviceOrientation`   | `string?`  |
| `appVersion`          | `string?`  |
| `appName`             | `string?`  |
| `locale`              | `string?`  |
| `sdkVer`              | `string?`  |
| `sessionId`           | `string?`  |
| `isNewUser`           | `boolean?` |
| `timezone`            | `string?`  |
| `network`             | `string?`  |
| `systemName`          | `string?`  |
| `timestamp`           | `number?`  |

### `WMAnalyticsEvent`

| Field       | Type                     | Description                     |
| ------------ | ------------------------- | ---------------------------------- |
| `eventName`  | `string`                  | e.g. `"play"`, `"click"`, `"activity"` |
| `params`     | `Record<string, unknown>` | Full event payload                 |

---

## Troubleshooting (iOS)

| Symptom                                                          | Cause                                                | Fix                                                                          |
| ------------------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `{"code":"UNIMPLEMENTED"}` from any WalkMe call                     | Plugin missing from `ios/App/CapApp-SPM/Package.swift` (`cap sync` regression, ionic-team/capacitor#8325) or missing `-ObjC` linker flag | Run `npx wm-capacitor-fix-ios-project`; confirm it's wired into `postinstall` + `capacitor:sync:after` |
| SPM resolution logs `warning: [WalkMePlugin] Unknown ...` and the wrong variant links | Typo in `walkme.walkmeMode` (or `WALKME_FLAVOR`)        | Use exactly `WalkMe` or `WalkMeEditor` (any casing) — an unrecognized value falls back to `"standard"` rather than failing the build (Android fails the build on this instead), so check for this warning if the wrong SDK links |
| SPM: "Dependencies could not be resolved" — two version requirements for `capacitor-swift-pm` | Your Capacitor version's generated `CapApp-SPM` pins an exact `capacitor-swift-pm` version outside this plugin's supported range | File an issue/bump the plugin — the range in `ios/Package.swift` needs widening for that Capacitor version |
| Launch crash: `Library not loaded: @rpath/Lottie.framework/Lottie` | `Lottie.framework` missing from the app bundle | Should not happen — the plugin depends on `lottie-spm` (airbnb's prebuilt dynamic `Lottie.xcframework`), which auto-embeds `Lottie.framework`. If you hit this, do a clean SPM re-resolve (Xcode → File → Packages → Reset Package Caches, or delete `DerivedData`) and confirm `App.app/Frameworks/Lottie.framework` exists after building. |
| Editor SDK Compose-related build errors (Android, not iOS)         | Host app already declares its own Compose BOM at a different version | Reconcile manually — see "Known gaps" below                                     |
| Unsure whether the *latest* WalkMe SDK version was actually picked up | SPM's `from:`/range constraints, or a stale `Package.resolved` | Compare `ios/App/App.xcodeproj/.../Package.resolved` (`walkme-ios-sdk` / `walkme-ios-sdk-editor` entry) against the latest tag at `github.com/WalkMe-int/walkme-ios-sdk(-editor)/tags`; if behind, delete `Package.resolved` and Xcode → File → Packages → Reset Package Caches |

For anything not covered here: Xcode → Product → Clean Build Folder, then quit and reopen Xcode (forces Swift package re-resolution) before assuming something deeper is wrong.

---

## Versioning strategy

Both platforms track the newest compatible release automatically rather than a hand-pinned version:

- **Android**: Gradle dynamic version `+` against JitPack (or a hand-pinned `walkmeVersion`/`walkmeEditorVersion`, see Android setup step 2).
- **iOS**: SwiftPM `from: "<version>"` (same-major auto-upgrade) for the WalkMe SDKs; a custom range for `capacitor-swift-pm` (see `ios/Package.swift` comments).

A **major** version bump from WalkMe on either platform needs a manual update:
- Android: the JitPack dependency coordinate has no major-version concept to bound, so nothing needs changing there, but test before rolling out.
- iOS: the `from:` base version in `ios/Package.swift` (`walkmeStandardMinVersion` / `walkmeEditorMinVersion`) must be bumped by hand, since SPM's `from:` treats a major version bump as a hard ceiling. **This has already bitten this plugin once** — the editor SDK floor was left at an old `0.x` beta version after WalkMe shipped a stable `1.x` line, silently capping every resolve at the old major line with no error or warning. Check the Troubleshooting table above periodically.

---

## Known gaps / next steps for a production build

1. **iOS SPM + Capacitor 8**: open upstream issue (ionic-team/capacitor#8325) where plugin SPM products aren't always exposed/kept wired into the generated Xcode project. Handled by `npx wm-capacitor-fix-ios-project` as long as it's wired into both `postinstall` and `capacitor:sync:after` — see iOS Setup above.
2. **Lottie framework embedding**: WalkMe's iOS SDK binaries hard-require a *dynamic* framework named exactly `Lottie.framework` (`@rpath/Lottie.framework/Lottie`). Handled automatically: the plugin depends on **`lottie-spm`** (airbnb's official SPM distribution of the prebuilt dynamic `Lottie.xcframework`) in `ios/Package.swift`, so `Lottie.framework` builds with the correct name and Xcode auto-embeds it — no host-app Xcode step. Uses a `from:` version range (no hand-managed checksum), and being a shared package it unifies cleanly with a host app that also uses `lottie-spm`.
3. **Editor SDK Compose deps** (Android): currently always added when `walkmeMode` resolves to `WalkMeEditor`; if the host app already declares its own Compose BOM at a different version, reconcile manually.
4. **`xcode` npm package dependency**: `wm-capacitor-fix-ios-project` uses it read-only (to locate build configuration UUIDs), then edits `project.pbxproj` via direct text splicing rather than the package's own `writeSync()` (see "How the iOS fix script works" above). Worth re-checking if the `xcode` package is ever upgraded.
5. **Variant setup ergonomics**: handled via the shared `walkme.walkmeMode` field in `package.json` (see "Select a Flavor" above). Android reads it via Gradle's project graph; iOS's `Package.swift` reads it directly off the host app's `package.json` via an upward file walk — neither platform needs a sync step for this.

## License

Commercial
