// swift-tools-version: 5.9
import PackageDescription

// --- WalkMe variant: "standard" (walkme-ios-sdk) or "editor" (Power Mode) -
// Don't hand-edit this line in node_modules — it gets overwritten by
// `npx wm-capacitor-sync-ios-variant`, which reads the choice from your
// app's own wm-capacitor.config.json (see plugin README). That script is
// the source of truth; this literal is just its last-applied value plus the
// default ("standard") for anyone who never runs it.
let walkmeVariant = "editor"

// "Auto-track latest, same major line" per the chosen versioning strategy —
// mirrors the Android side's Gradle `+` dynamic version. A future *major*
// WalkMe release requires bumping the base version below by hand (SwiftPM
// treats major bumps as potentially breaking and won't cross them
// automatically), same tradeoff as any real dependency-pinning strategy.
let walkmeStandardMinVersion = "1.1.2"
// Was "0.1.6" (the editor SDK's old 0.x beta line). WalkMe has since shipped
// a stable 1.x line (currently 1.1.2), but SPM's `from:` caps resolution at
// the next major version — so the 0.1.6 floor was silently preventing this
// plugin from ever crossing into 1.x, no matter how often packages were
// re-resolved. Bumped to track the new major line; bump again by hand
// whenever WalkMe ships 2.x.
let walkmeEditorMinVersion = "1.1.2"

var adapterTargetName: String { walkmeVariant == "editor" ? "WalkMeEditorAdapter" : "WalkMeStandardAdapter" }

// Lottie is a runtime dependency of WalkMe's prebuilt SDK binaries (both
// variants), not of this plugin's own Swift code — the adapters never
// `import Lottie`. WalkMe's *.framework has a hard-coded
// `@rpath/Lottie.framework/Lottie` load command, so the app must ship a
// *dynamic* framework named exactly `Lottie.framework` or it crashes on
// launch with "Library not loaded: @rpath/Lottie.framework/Lottie".
//
// We can't get that from lottie-ios's SPM products: its `Lottie` product is
// static (no framework bundle is produced, so the load command is
// unsatisfied) and its `Lottie-Dynamic` product builds
// `Lottie-Dynamic.framework/Lottie-Dynamic` — right Mach-O, wrong name.
// airbnb ships a prebuilt *dynamic* `Lottie.xcframework` per release whose
// framework/binary are both literally `Lottie`, so a binaryTarget pointing
// at it produces `Lottie.framework` with the exact name/`@rpath` install id
// WalkMe expects, and Xcode auto-embeds it (it's a dynamic binary target) —
// no host-app Xcode step, single copy of Lottie in the bundle.
//
// Tradeoff vs. the source dependency: a binaryTarget pins one exact version
// (no `from:` range), so bumping Lottie means updating BOTH the URL and the
// checksum below by hand. Keep >= what the WalkMe SDKs require (4.6.0+).
// Checksum: `swift package compute-checksum Lottie.xcframework.zip`.
let lottieVersion = "4.6.1"
let lottieChecksum = "03d3f3b085da9479bcab7b0ad4b6d75a88425d27bf3c7582698fddce14c9181f"

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
        .package(url: "https://github.com/WalkMe-int/walkme-ios-sdk.git", from: Version(stringLiteral: walkmeStandardMinVersion)),
        .package(url: "https://github.com/WalkMe-int/walkme-ios-sdk-editor.git", from: Version(stringLiteral: walkmeEditorMinVersion)),
        // Lottie is vendored as a binaryTarget below (see the comment on
        // `lottieVersion`), not as a source package dependency.
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
        // Prebuilt dynamic Lottie.framework required at runtime by WalkMe's
        // SDK binaries — see the `lottieVersion` comment above for why this is
        // a binaryTarget rather than the lottie-ios SPM package.
        .binaryTarget(
            name: "Lottie",
            url: "https://github.com/airbnb/lottie-ios/releases/download/\(lottieVersion)/Lottie.xcframework.zip",
            checksum: lottieChecksum
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
                .target(name: "Lottie"),
            ],
            path: "Sources/WalkMeStandardAdapter"
        ),
        .target(
            name: "WalkMeEditorAdapter",
            dependencies: [
                .target(name: "WMBridgeCore"),
                .product(name: "WalkMeEditor", package: "walkme-ios-sdk-editor"),
                .target(name: "Lottie"),
            ],
            path: "Sources/WalkMeEditorAdapter"
        ),
    ]
)
