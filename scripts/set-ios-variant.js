#!/usr/bin/env node
/**
 * Bakes an explicit WalkMe variant pin into this plugin's ios/Package.swift.
 *
 * NOTE: this script is now OPTIONAL. Package.swift auto-detects the variant at
 * build time by reading `walkme.walkmeMode` from the host app's package.json
 * itself (walking up out of node_modules), defaulting to "standard". This
 * script only exists for setups that prefer an explicit value baked into
 * node_modules (e.g. CI, or to avoid relying on the upward file walk): it
 * reads the SAME `walkme.walkmeMode` field and writes the result into the
 * `let pinnedVariant = "..."` line, which takes precedence over auto-detection
 * (but not over the WALKME_FLAVOR env var).
 *
 * Usage (run from your app's root, i.e. next to capacitor.config.ts):
 *   npx wm-capacitor-sync-ios-variant
 *
 * Optional: wire this into your app's own package.json to pin it on install:
 *   "scripts": { "postinstall": "wm-capacitor-sync-ios-variant" }
 *
 * Your app's package.json:
 *   "walkme": { "walkmeMode": "WalkMeEditor" }   // or "WalkMe" (default if omitted)
 *
 * CI / one-off override: WALKME_FLAVOR=WalkMeEditor takes precedence over
 * package.json (matches the Android side's env var override).
 */
const fs = require('fs');
const path = require('path');

function readVariant(appRoot) {
  const envOverride = process.env.WALKME_FLAVOR;
  let rawMode = envOverride;

  if (!rawMode) {
    const pkgPath = path.join(appRoot, 'package.json');
    if (!fs.existsSync(pkgPath)) {
      console.warn(`[@walkme-mobile/capacitor-plugin] No package.json found at ${pkgPath} — defaulting to "WalkMe".`);
      return 'standard';
    }

    let pkg;
    try {
      pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    } catch (e) {
      throw new Error(`[@walkme-mobile/capacitor-plugin] Could not parse ${pkgPath}: ${e.message}`);
    }

    rawMode = pkg.walkme && pkg.walkme.walkmeMode;
    if (!rawMode) {
      console.warn(
        `[@walkme-mobile/capacitor-plugin] No "walkme.walkmeMode" found in ${pkgPath} — defaulting to "WalkMe". ` +
          'Add { "walkme": { "walkmeMode": "WalkMeEditor" } } to change it.',
      );
      return 'standard';
    }
  }

  const normalized = String(rawMode).toLowerCase();
  if (normalized === 'walkme') return 'standard';
  if (normalized === 'walkmeeditor') return 'editor';

  throw new Error(
    `[@walkme-mobile/capacitor-plugin] Unknown walkme.walkmeMode ${JSON.stringify(rawMode)} — expected "WalkMe" or "WalkMeEditor" ` +
      '(any casing), from package.json or the WALKME_FLAVOR env var.',
  );
}

function patchPackageSwift(variant) {
  const pkgPath = path.join(__dirname, '..', 'ios', 'Package.swift');
  let contents = fs.readFileSync(pkgPath, 'utf8');

  const pattern = /^let pinnedVariant = ".*"$/m;
  if (!pattern.test(contents)) {
    throw new Error(
      `[@walkme-mobile/capacitor-plugin] Could not find a "let pinnedVariant = ..." line in ${pkgPath} — ` +
        'the plugin layout may have changed; this script needs updating too.',
    );
  }

  contents = contents.replace(pattern, `let pinnedVariant = "${variant}"`);
  fs.writeFileSync(pkgPath, contents, 'utf8');
  console.log(
    `[@walkme-mobile/capacitor-plugin] ios/Package.swift set to variant "${variant}". ` +
      'Re-run "npx cap sync ios" (or Xcode: File > Packages > Reset Package Caches) to apply it.',
  );
}

const appRoot = process.cwd();
const variant = readVariant(appRoot);
patchPackageSwift(variant);
