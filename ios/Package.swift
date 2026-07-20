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
