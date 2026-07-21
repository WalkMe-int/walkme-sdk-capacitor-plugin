// swift-tools-version: 5.9
import PackageDescription
import Foundation

// --- WalkMe variant resolution -------------------------------------------
// The variant ("standard" = walkme-ios-sdk, "editor" = walkme-ios-sdk-editor /
// Power Mode) is a BUILD-TIME choice. On Android, Gradle's multi-project graph
// lets build.gradle read the app's package.json directly; SwiftPM has no view
// of the consuming app, so this manifest reads it itself — it walks up from its
// own location (inside the app's node_modules) to find the host app's
// package.json and its `walkme.walkmeMode` field. Same field/key the Android
// side and walkme-react-native-sdk read.
//
// Variant resolution order (first hit wins):
//   1. WALKME_FLAVOR env var   — CI / one-off override (matches Android)
//   2. `pinnedVariant` below   — optional hard pin (see wm-capacitor-sync-ios-variant)
//   3. host app package.json   — `walkme.walkmeMode`
//   4. "standard"              — default when nothing is set
//
// Accepted mode values, any casing: "WalkMe" -> standard, "WalkMeEditor" -> editor.
//
// The same `walkme` object may also pin an exact SDK version:
//   "walkme": { "walkmeMode": "WalkMeEditor", "walkmeVersion": "1.1.3" }
// walkmeVersion (or the WALKME_VERSION env var) exact-pins the *active* variant's
// SDK package; omitted -> the `from:` floor below (auto-track latest in major).
//
// Note: file reads/env are allowed inside SwiftPM's manifest sandbox (writes and
// network are not). Any failure here falls through to the "standard" default
// rather than breaking resolution.

// Optional hard pin. Normally left empty ("") so the app's package.json wins.
// `npx wm-capacitor-sync-ios-variant` may write "standard" or "editor" here for
// setups that prefer an explicit value baked into node_modules.
let pinnedVariant = ""

func normalizeWalkmeMode(_ raw: String) -> String? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "walkme", "standard": return "standard"
    case "walkmeeditor", "editor": return "editor"
    default: return nil
    }
}

// Host app's `walkme` config from package.json (both fields optional).
struct WalkmeHostConfig {
    var mode: String?
    var version: String?
}

// Reads the `walkme` object from a package.json at `url`. Returns nil when
// there's no usable `walkme` entry (e.g. the plugin's own package.json), so the
// upward walk keeps climbing past it.
func walkmeHostConfig(at url: URL) -> WalkmeHostConfig? {
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let walkme = json["walkme"] as? [String: Any] else {
        return nil
    }
    let mode = walkme["walkmeMode"] as? String
    let version = walkme["walkmeVersion"] as? String
    if mode == nil && version == nil { return nil }
    return WalkmeHostConfig(mode: mode, version: version)
}

// Walks up from this manifest (inside the app's node_modules) to the first
// package.json carrying a `walkme` config.
//   Layout: <app>/node_modules/@walkme-mobile/capacitor-plugin/ios/Package.swift
// The plugin's own package.json has no `walkme` key, so it's skipped naturally.
func findWalkmeHostConfig() -> WalkmeHostConfig? {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<8 {
        if let cfg = walkmeHostConfig(at: dir.appendingPathComponent("package.json")) {
            return cfg
        }
        let parent = dir.deletingLastPathComponent()
        if parent == dir { break } // reached filesystem root
        dir = parent
    }
    return nil
}

let walkmeHost = findWalkmeHostConfig()

// Variant: WALKME_FLAVOR env > pinnedVariant > package.json walkmeMode > "standard".
func resolveWalkmeVariant() -> String {
    if let env = ProcessInfo.processInfo.environment["WALKME_FLAVOR"], !env.isEmpty {
        if let variant = normalizeWalkmeMode(env) { return variant }
        print("warning: [WalkMePlugin] Unknown WALKME_FLAVOR \"\(env)\" — expected WalkMe or WalkMeEditor; ignoring.")
    }
    if !pinnedVariant.isEmpty {
        if let variant = normalizeWalkmeMode(pinnedVariant) { return variant }
        print("warning: [WalkMePlugin] Unknown pinnedVariant \"\(pinnedVariant)\" — ignoring.")
    }
    if let mode = walkmeHost?.mode, let variant = normalizeWalkmeMode(mode) { return variant }
    return "standard"
}

// Exact SDK version override: WALKME_VERSION env > package.json walkmeVersion.
// nil = no override -> use the `from:` floor below (auto-track latest in major).
func resolveWalkmeVersion() -> String? {
    if let env = ProcessInfo.processInfo.environment["WALKME_VERSION"], !env.isEmpty {
        return env
    }
    return walkmeHost?.version
}

let walkmeVariant = resolveWalkmeVariant()
let walkmeVersionOverride = resolveWalkmeVersion()

// "Auto-track latest, same major line" per the chosen versioning strategy —
// mirrors the Android side's Gradle `+` dynamic version. A future *major*
// WalkMe release requires bumping the base version below by hand (SwiftPM
// treats major bumps as potentially breaking and won't cross them
// automatically), same tradeoff as any real dependency-pinning strategy.
let walkmeStandardMinVersion = "1.1.4"
// Was "0.1.6" (the editor SDK's old 0.x beta line). WalkMe has since shipped
// a stable 1.x line (currently 1.1.2), but SPM's `from:` caps resolution at
// the next major version — so the 0.1.6 floor was silently preventing this
// plugin from ever crossing into 1.x, no matter how often packages were
// re-resolved. Bumped to track the new major line; bump again by hand
// whenever WalkMe ships 2.x.
let walkmeEditorMinVersion = "1.1.4"

var adapterTargetName: String { walkmeVariant == "editor" ? "WalkMeEditorAdapter" : "WalkMeStandardAdapter" }

// Builds a WalkMe SDK package requirement. The *active* variant honors an exact
// walkmeVersion/WALKME_VERSION override; the inactive one (resolved but never
// linked) always uses its `from:` floor, since that exact version may not exist
// in the other SDK's separate release line.
func walkmeSDKDependency(url: String, floor: String, isActive: Bool) -> Package.Dependency {
    if isActive, let raw = walkmeVersionOverride {
        if let exact = Version(raw) {
            return .package(url: url, exact: exact)
        }
        print("warning: [WalkMePlugin] Invalid walkmeVersion \"\(raw)\" — expected e.g. 1.1.3; using floor \(floor).")
    }
    return .package(url: url, from: Version(stringLiteral: floor))
}

let package = Package(
    name: "WalkMePlugin",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "WalkMePlugin", targets: ["WalkMePlugin"])
    ],
    dependencies: [
        // Custom range (not `from:`) because `from:` treats major bumps as
        // breaking and would cap this at <8.0.0 — but Capacitor 8's own
        // generated CapApp-SPM pins capacitor-swift-pm to an exact 8.x
        // version, which must fall inside this plugin's range too, or SPM
        // fails with "Dependencies could not be resolved" (two disjoint
        // version requirements for the same package). Widen the upper bound
        // by hand if/when Capacitor 9 ships.
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", "7.0.0"..<"9.0.0"),
        walkmeSDKDependency(url: "https://github.com/WalkMe-int/walkme-ios-sdk.git", floor: walkmeStandardMinVersion, isActive: walkmeVariant == "standard"),
        walkmeSDKDependency(url: "https://github.com/WalkMe-int/walkme-ios-sdk-editor.git", floor: walkmeEditorMinVersion, isActive: walkmeVariant == "editor"),
        // Lottie is a runtime dependency of WalkMe's prebuilt SDK binaries (both
        // variants), not of this plugin's own Swift code — the adapters never
        // `import Lottie`. WalkMe's *.framework has a hard-coded
        // `@rpath/Lottie.framework/Lottie` load command, so the app must ship a
        // *dynamic* framework named exactly `Lottie.framework` or it crashes on
        // launch with "Library not loaded: @rpath/Lottie.framework/Lottie".
        //
        // `lottie-spm` is airbnb's official SPM distribution of the prebuilt
        // *dynamic* `Lottie.xcframework` (framework/binary both literally
        // `Lottie`), so it satisfies that load command and Xcode auto-embeds it
        // — no host-app Xcode step. Preferred over lottie-ios's source products
        // (whose `Lottie` product is static and `Lottie-Dynamic` produces the
        // wrong framework name) and over a hand-rolled binaryTarget (which
        // pins one exact version + checksum and can't dedupe with a host app's
        // own Lottie): as a shared package, SPM unifies it with an app that also
        // uses lottie-spm. Same choice as the sibling walkme-flutter plugin.
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.6.0"),
    ],
    targets: [
        .target(
            name: "WalkMePlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .target(name: "WMBridgeCore"),
                .target(name: adapterTargetName),
            ],
            path: "Sources/WalkMePlugin",
            // Selects which adapter WalkMePlugin.swift imports via `#if WALKME_EDITOR`.
            // Keeps this in lockstep with `adapterTargetName` above.
            swiftSettings: walkmeVariant == "editor" ? [.define("WALKME_EDITOR")] : []
        ),
        // Shared protocol/types (WMBridge, WMStartOptions, ...). Kept as its
        // own target so it can be depended on by WalkMePlugin *and* both
        // adapters without a dependency cycle.
        .target(
            name: "WMBridgeCore",
            path: "Sources/WMBridgeCore"
        ),
        // Only ONE of these two adapter targets ends up in the link graph —
        // whichever one WalkMePlugin depends on above — even though both
        // targets are declared, so both WalkMe packages are only *resolved*
        // (source fetched), never both *linked* into the same binary.
        .target(
            name: "WalkMeStandardAdapter",
            dependencies: [
                .target(name: "WMBridgeCore"),
                .product(name: "WalkMe", package: "walkme-ios-sdk"),
                .product(name: "Lottie", package: "lottie-spm"),
            ],
            path: "Sources/WalkMeStandardAdapter"
        ),
        .target(
            name: "WalkMeEditorAdapter",
            dependencies: [
                .target(name: "WMBridgeCore"),
                .product(name: "WalkMeEditor", package: "walkme-ios-sdk-editor"),
                .product(name: "Lottie", package: "lottie-spm"),
            ],
            path: "Sources/WalkMeEditorAdapter"
        ),
    ]
)
