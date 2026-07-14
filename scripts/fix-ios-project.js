#!/usr/bin/env node
/**
 * Works around two real, observed Capacitor 8 + SPM gaps that otherwise
 * require re-doing the same manual Xcode fix every time the native project
 * is regenerated:
 *
 *   1. `npx cap sync ios` regenerates ios/App/CapApp-SPM/Package.swift from
 *      scratch and — per ionic-team/capacitor#8325 — does not reliably wire
 *      locally-pathed plugin SPM packages back into it. This script re-adds
 *      the WalkMePlugin dependency + product if it's missing.
 *   2. Capacitor's iOS plugin auto-discovery scans the Objective-C runtime
 *      for classes conforming to CAPBridgedPlugin. WalkMePlugin ships as a
 *      Swift Package Manager (static-by-default) library; linkers only pull
 *      in object files from a static archive that satisfy a symbol
 *      reference, so an @objc class nothing directly calls can get dropped
 *      by the linker unless `-ObjC` is in the app target's Other Linker
 *      Flags. This script adds it if missing.
 *
 * Usage (run from your app's root, i.e. next to capacitor.config.ts):
 *   npx wm-capacitor-fix-ios-project
 *
 * Recommended: wire this into your app's own package.json so it re-applies
 * automatically after every install AND every `cap sync` (the two moments
 * that can undo it):
 *   "scripts": {
 *     "postinstall": "wm-capacitor-sync-ios-variant && wm-capacitor-fix-ios-project",
 *     "capacitor:sync:after": "wm-capacitor-fix-ios-project"
 *   }
 *
 * Assumes Capacitor's default iOS project layout (ios/App/...). Silently
 * no-ops (with a log line) if that layout isn't found, e.g. iOS platform not
 * added yet, or android-only builds.
 */
const fs = require('fs');
const path = require('path');

const LOG_PREFIX = '[@walkme-mobile/capacitor-plugin]';
const appRoot = process.cwd();

function resolvePluginIosDir() {
  // Resolve wherever `@walkme-mobile/capacitor-plugin` actually lives on
  // disk — a real node_modules install, or (local dev) a symlink from
  // `file:../...` — so the SPM `path:` we splice in is correct either way.
  const pkgJsonPath = require.resolve('@walkme-mobile/capacitor-plugin/package.json', { paths: [appRoot] });
  return path.join(path.dirname(pkgJsonPath), 'ios');
}

function insertIntoSwiftArray(text, marker, fromIndex, newEntry, alreadyPresentCheck) {
  const markerIdx = text.indexOf(marker, fromIndex);
  if (markerIdx === -1) {
    throw new Error(`${LOG_PREFIX} Could not find "${marker}" (from index ${fromIndex}) — CapApp-SPM/Package.swift layout may have changed.`);
  }
  const openIdx = markerIdx + marker.length - 1; // index of '['

  let depth = 0;
  let closeIdx = -1;
  for (let i = openIdx; i < text.length; i++) {
    if (text[i] === '[') depth++;
    else if (text[i] === ']') {
      depth--;
      if (depth === 0) {
        closeIdx = i;
        break;
      }
    }
  }
  if (closeIdx === -1) throw new Error(`${LOG_PREFIX} Could not find matching "]" for "${marker}".`);

  const arrayContent = text.slice(openIdx + 1, closeIdx);
  if (arrayContent.includes(alreadyPresentCheck)) {
    return { text, changed: false, markerIdx };
  }

  const indentMatch = arrayContent.match(/\n(\s+)\S/);
  const indent = indentMatch ? indentMatch[1] : '        ';

  let trimmedEnd = arrayContent.replace(/\s+$/, '');
  const trailingWhitespace = arrayContent.slice(trimmedEnd.length);
  if (!trimmedEnd.endsWith(',')) trimmedEnd += ',';

  const newArrayContent = `${trimmedEnd}\n${indent}${newEntry}${trailingWhitespace}`;
  const newText = text.slice(0, openIdx + 1) + newArrayContent + text.slice(closeIdx);
  return { text: newText, changed: true, markerIdx };
}

function fixCapAppSpmPackageSwift() {
  const pkgSwiftPath = path.join(appRoot, 'ios', 'App', 'CapApp-SPM', 'Package.swift');
  if (!fs.existsSync(pkgSwiftPath)) {
    console.log(`${LOG_PREFIX} No ${pkgSwiftPath} found — skipping CapApp-SPM fixup (iOS platform not added yet?).`);
    return;
  }

  const pluginIosDir = resolvePluginIosDir();
  const relPath = path.relative(path.dirname(pkgSwiftPath), pluginIosDir);

  let text = fs.readFileSync(pkgSwiftPath, 'utf8');

  const step1 = insertIntoSwiftArray(
    text,
    'dependencies: [',
    0,
    `.package(name: "WalkMePlugin", path: "${relPath}")`,
    'WalkMePlugin',
  );
  text = step1.text;

  const step2 = insertIntoSwiftArray(
    text,
    'dependencies: [',
    step1.markerIdx + 'dependencies: ['.length,
    '.product(name: "WalkMePlugin", package: "WalkMePlugin")',
    'WalkMePlugin',
  );
  text = step2.text;

  if (step1.changed || step2.changed) {
    fs.writeFileSync(pkgSwiftPath, text, 'utf8');
    console.log(`${LOG_PREFIX} Re-added WalkMePlugin to ${pkgSwiftPath}.`);
  } else {
    console.log(`${LOG_PREFIX} ${pkgSwiftPath} already references WalkMePlugin — no changes made.`);
  }
}

function fixOtherLinkerFlags() {
  const pbxprojPath = path.join(appRoot, 'ios', 'App', 'App.xcodeproj', 'project.pbxproj');
  if (!fs.existsSync(pbxprojPath)) {
    console.log(`${LOG_PREFIX} No ${pbxprojPath} found — skipping -ObjC fixup (iOS platform not added yet?).`);
    return;
  }

  // We only use the `xcode` package to LOCATE the app target's build
  // configuration UUIDs (read-only). We deliberately do NOT call its
  // project.writeSync() — in testing, that full-file re-serialization
  // duplicated build settings into unrelated project-level configs instead
  // of only the intended target. Instead we splice the flag into the raw
  // text ourselves, touching nothing outside the two exact blocks found.
  let xcode;
  try {
    xcode = require('xcode');
  } catch (e) {
    console.warn(`${LOG_PREFIX} Could not load the "xcode" package (${e.message}) — skipping -ObjC fixup. Add it manually: App target > Build Settings > Other Linker Flags > -ObjC.`);
    return;
  }

  const project = xcode.project(pbxprojPath);
  project.parseSync();

  const nativeTargets = project.pbxNativeTargetSection();
  let appTargetUuid = null;
  for (const uuid in nativeTargets) {
    if (uuid.endsWith('_comment')) continue;
    const target = nativeTargets[uuid];
    if (target && target.productType === '"com.apple.product-type.application"') {
      appTargetUuid = uuid;
      break;
    }
  }
  if (!appTargetUuid) {
    console.warn(`${LOG_PREFIX} Could not find an application target in ${pbxprojPath} — skipping -ObjC fixup.`);
    return;
  }

  const configListUuid = nativeTargets[appTargetUuid].buildConfigurationList;
  const configList = project.pbxXCConfigurationList()[configListUuid];
  if (!configList) {
    console.warn(`${LOG_PREFIX} Could not find build configuration list ${configListUuid} — skipping -ObjC fixup.`);
    return;
  }
  const targetConfigUuids = configList.buildConfigurations.map((c) => c.value);

  let text = fs.readFileSync(pbxprojPath, 'utf8');
  const FLAG = '-ObjC';
  let changedCount = 0;

  for (const uuid of targetConfigUuids) {
    const blockStartMarker = new RegExp(`^\\t\\t${uuid} \\/\\* [^*]+ \\*\\/ = \\{`, 'm');
    const m = blockStartMarker.exec(text);
    if (!m) continue;
    const blockStart = m.index;
    const openBraceIdx = text.indexOf('{', blockStart);
    let depth = 0;
    let closeBraceIdx = -1;
    for (let i = openBraceIdx; i < text.length; i++) {
      if (text[i] === '{') depth++;
      else if (text[i] === '}') {
        depth--;
        if (depth === 0) {
          closeBraceIdx = i;
          break;
        }
      }
    }
    if (closeBraceIdx === -1) continue;

    const block = text.slice(openBraceIdx, closeBraceIdx + 1);
    if (new RegExp(`OTHER_LDFLAGS[\\s\\S]*?${FLAG.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')}`).test(block)) {
      continue; // already present in this config
    }

    let newBlock;
    const arrayMatch = block.match(/(\n(\t+)OTHER_LDFLAGS = \(\n)([\s\S]*?)(\n\2\);)/);
    const scalarMatch = block.match(/\n(\t+)OTHER_LDFLAGS = ([^\n;]+);/);

    if (arrayMatch) {
      const [whole, head, indent, items, tail] = arrayMatch;
      newBlock = block.replace(whole, `${head}${items}\n${indent}\t${FLAG},${tail}`);
    } else if (scalarMatch) {
      const [whole, indent, existingValue] = scalarMatch;
      const cleaned = existingValue.replace(/^"(.*)"$/, '$1');
      newBlock = block.replace(
        whole,
        `\n${indent}OTHER_LDFLAGS = (\n${indent}\t"$(inherited)",\n${indent}\t"${cleaned}",\n${indent}\t${FLAG},\n${indent});`,
      );
    } else {
      const bsMatch = block.match(/(buildSettings = \{\n)(\t+)/);
      if (!bsMatch) continue;
      const [whole, head, indent] = bsMatch;
      newBlock = block.replace(
        whole,
        `${head}${indent}OTHER_LDFLAGS = (\n${indent}\t"$(inherited)",\n${indent}\t${FLAG},\n${indent});\n${indent}`,
      );
    }

    text = text.slice(0, openBraceIdx) + newBlock + text.slice(closeBraceIdx + 1);
    changedCount++;
  }

  if (changedCount > 0) {
    fs.writeFileSync(pbxprojPath, text, 'utf8');
    console.log(`${LOG_PREFIX} Added -ObjC to ${changedCount} app target build configuration(s) in ${pbxprojPath}.`);
  } else {
    console.log(`${LOG_PREFIX} -ObjC already present on all app target build configurations — no changes made.`);
  }
}

fixCapAppSpmPackageSwift();
fixOtherLinkerFlags();
