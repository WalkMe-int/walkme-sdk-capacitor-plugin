#!/usr/bin/env node
/**
 * Applies the app's chosen WalkMe variant to this plugin's ios/Package.swift.
 *
 * Why this exists: on Android, Gradle has a real multi-project graph, so our
 * android/build.gradle can just read `walkme.walkmeMode` straight out of the
 * *app's* package.json at every build — zero extra steps for the developer.
 * Swift Package Manager has no equivalent concept; a package's Package.swift
 * has no way to see "the app that's consuming me" or read its files during
 * manifest resolution. So there's no way to make iOS as frictionless as
 * Android — this script is the closest practical substitute: it reads the
 * SAME `walkme.walkmeMode` field the Android side reads (single source of
 * truth, and the same key walkme-react-native-sdk uses), then copies that
 * choice into the plugin's Package.swift.
 *
 * Usage (run from your app's root, i.e. next to capacitor.config.ts):
 *   npx wm-capacitor-sync-ios-variant
 *
 * Recommended: wire this into your app's own package.json so it happens
 * automatically:
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

  const pattern = /^let walkmeVariant = ".*"$/m;
  if (!pattern.test(contents)) {
    throw new Error(
      `[@walkme-mobile/capacitor-plugin] Could not find a "let walkmeVariant = ..." line in ${pkgPath} — ` +
        'the plugin layout may have changed; this script needs updating too.',
    );
  }

  contents = contents.replace(pattern, `let walkmeVariant = "${variant}"`);
  fs.writeFileSync(pkgPath, contents, 'utf8');
  console.log(
    `[@walkme-mobile/capacitor-plugin] ios/Package.swift set to variant "${variant}". ` +
      'Re-run "npx cap sync ios" (or Xcode: File > Packages > Reset Package Caches) to apply it.',
  );
}

const appRoot = process.cwd();
const variant = readVariant(appRoot);
patchPackageSwift(variant);
