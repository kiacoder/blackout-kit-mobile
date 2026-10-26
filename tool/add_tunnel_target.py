#!/usr/bin/env python3
"""Adds the BlackoutTunnel Network Extension target to Runner.xcodeproj.

The generated Flutter pbxproj has no app-extension target, and hand-editing
the plist-style pbxproj is error-prone, so this script does it once,
deterministically:

  * PBXFileReference   for PacketTunnelProvider.swift + Info.plist + .entitlements
  * PBXGroup           "BlackoutTunnel"
  * PBXNativeTarget    "BlackoutTunnel" (com.apple.product-type.app-extension)
  * PBXSources/BuildFile entry for the Swift file
  * shellScript build phase that COPIES the prebuilt Libbox.xcframework into
    the extension's Frameworks dir (libbox is built by tool/build_libbox.sh;
    committed as a release asset, not vendored into the repo)
  * frameworks build phase referencing Libbox.xcframework
  * PBXTargetDependency + PBXContainerItemProxy (Runner embeds BlackoutTunnel)
  * "Embed Foundation Extensions" copy-files phase on the Runner target
  * debug/release XCBuildConfiguration blocks for the new target

Run from the repo root:  python tool/add_tunnel_target.py
Idempotent: exits 0 without changes when the target already exists.
"""

import re
import sys
from pathlib import Path

PBXPROJ = Path("ios/Runner.xcodeproj/project.pbxproj")

TUNNEL_TARGET = "BlackoutTunnel"
TUNNEL_BUNDLE_ID = "com.blackoutkit.vpn.tunnel"

# Stable fake UUIDs (24-hex). Deterministic across runs; chosen so they do
# not collide with anything in the generated project (prefix X1.. keeps them
# obviously ours).
U = {
    "sw_fileref":      "X1A0C0FFEE000000000000000000001",
    "plist_fileref":   "X1A0C0FFEE000000000000000000002",
    "ent_fileref":     "X1A0C0FFEE000000000000000000003",
    "xcfw_fileref":    "X1A0C0FFEE000000000000000000004",
    "group":           "X1A0C0FFEE000000000000000000005",
    "sources_phase":   "X1A0C0FFEE000000000000000000006",
    "sources_build":   "X1A0C0FFEE000000000000000000007",
    "fw_phase":        "X1A0C0FFEE000000000000000000008",
    "fw_build":        "X1A0C0FFEE000000000000000000009",
    "script_phase":    "X1A0C0FFEE00000000000000000000A",
    "target":          "X1A0C0FFEE00000000000000000000B",
    "cfg_debug":       "X1A0C0FFEE00000000000000000000C",
    "cfg_release":     "X1A0C0FFEE00000000000000000000D",
    "cfglist":         "X1A0C0FFEE00000000000000000000E",
    "product_fileref": "X1A0C0FFEE00000000000000000000F",
    "product_build":   "X1A0C0FFEE000000000000000000010",
    "products_group":  "X1A0C0FFEE000000000000000000011",
    "container_proxy": "X1A0C0FFEE000000000000000000012",
    "dependency":      "X1A0C0FFEE000000000000000000013",
    "embed_phase":     "X1A0C0FFEE000000000000000000014",
    "embed_build":     "X1A0C0FFEE000000000000000000015",
    "product_group_add": "X1A0C0FFEE000000000000000000016",
}

COPY_LIBBOX_SH = (
    '# libbox is built by tool/build_libbox.sh on macOS and dropped into\n'
    '# ios/Frameworks/Libbox.xcframework (release asset / local artifact,\n'
    '# not committed). Fail with a readable message when it is missing so\n'
    '# CI points at the fix instead of a generic codesign error.\n'
    'set -e\n'
    'if [ ! -d "$SRCROOT/../ios/Frameworks/Libbox.xcframework" ]; then\n'
    '  echo "error: ios/Frameworks/Libbox.xcframework is missing. Run tool/build_libbox.sh on a macOS host (or download it from the release) first." >&2\n'
    '  exit 1\n'
    'fi\n'
    'mkdir -p "$BUILT_PRODUCTS_DIR/BlackoutTunnel.appex/Frameworks"\n'
    'ditto "$SRCROOT/../ios/Frameworks/Libbox.xcframework" "$BUILT_PRODUCTS_DIR/BlackoutTunnel.appex/Frameworks/Libbox.xcframework"\n'
)


def main() -> int:
    text = PBXPROJ.read_text(encoding="utf-8")

    if TUNNEL_TARGET in text:
        print("BlackoutTunnel target already present; nothing to do")
        return 0

    # ── PBXBuildFile section additions ────────────────────────────────────
    anchor = "/* Begin PBXBuildFile section */\n"
    buildfile_add = (
        f'\t\t{U["sources_build"]} /* PacketTunnelProvider.swift in Sources */ = '
        f'{{isa = PBXBuildFile; fileRef = {U["sw_fileref"]} /* PacketTunnelProvider.swift */; }};\n'
        f'\t\t{U["fw_build"]} /* Libbox.xcframework in Frameworks */ = '
        f'{{isa = PBXBuildFile; fileRef = {U["xcfw_fileref"]} /* Libbox.xcframework */; }};\n'
        f'\t\t{U["embed_build"]} /* BlackoutTunnel.appex in Embed Foundation Extensions */ = '
        f'{{isa = PBXBuildFile; fileRef = {U["product_fileref"]} /* BlackoutTunnel.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n'
    )
    text = text.replace(anchor, anchor + buildfile_add, 1)

    # ── PBXFileReference section additions ────────────────────────────────
    anchor = "/* Begin PBXFileReference section */\n"
    fileref_add = (
        f'\t\t{U["sw_fileref"]} /* PacketTunnelProvider.swift */ = '
        '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PacketTunnelProvider.swift; sourceTree = "<group>"; };\n'
        f'\t\t{U["plist_fileref"]} /* Info.plist */ = '
        '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };\n'
        f'\t\t{U["ent_fileref"]} /* BlackoutTunnel.entitlements */ = '
        '{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = BlackoutTunnel.entitlements; sourceTree = "<group>"; };\n'
        f'\t\t{U["xcfw_fileref"]} /* Libbox.xcframework */ = '
        '{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = Libbox.xcframework; path = Frameworks/Libbox.xcframework; sourceTree = "<group>"; };\n'
        f'\t\t{U["product_fileref"]} /* BlackoutTunnel.appex */ = '
        '{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = BlackoutTunnel.appex; sourceTree = BUILT_PRODUCTS_DIR; };\n'
    )
    text = text.replace(anchor, anchor + fileref_add, 1)

    # ── PBXFrameworks build phase for the extension ───────────────────────
    anchor = "/* Begin PBXFrameworksBuildPhase section */\n"
    fw_add = (
        f'\t\t{U["fw_phase"]} /* Frameworks */ = {{\n'
        '\t\t\tisa = PBXFrameworksBuildPhase;\n'
        '\t\t\tbuildActionMask = 2147483647;\n'
        '\t\t\tfiles = (\n'
        f'\t\t\t\t{U["fw_build"]} /* Libbox.xcframework in Frameworks */,\n'
        '\t\t\t);\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n'
    )
    text = text.replace(anchor, anchor + fw_add, 1)

    # ── PBXGroup additions (tunnel group + product + main-group children) ─
    tunnel_group = (
        f'\t\t{U["group"]} /* BlackoutTunnel */ = {{\n'
        '\t\t\tisa = PBXGroup;\n'
        '\t\t\tchildren = (\n'
        f'\t\t\t\t{U["sw_fileref"]} /* PacketTunnelProvider.swift */,\n'
        f'\t\t\t\t{U["plist_fileref"]} /* Info.plist */,\n'
        f'\t\t\t\t{U["ent_fileref"]} /* BlackoutTunnel.entitlements */,\n'
        f'\t\t\t\t{U["xcfw_fileref"]} /* Libbox.xcframework */,\n'
        '\t\t\t);\n'
        '\t\t\tpath = BlackoutTunnel;\n'
        '\t\t\tsourceTree = "<group>";\n'
        '\t\t};\n'
    )
    anchor = "/* Begin PBXGroup section */\n"
    text = text.replace(anchor, anchor + tunnel_group, 1)

    # Main group: add the tunnel group as a child (before Runner group ref).
    m = re.search(
        r"([0-9A-F]{24}) /\* Runner \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n",
        text,
    )
    if not m:
        print("could not locate Runner group", file=sys.stderr)
        return 1
    main_group_ref = m.group(1)
    # mainGroup is the project-level group (mainGroup = <uuid> in
    # PBXProject), NOT the Runner source group matched above.
    g = re.search(r"mainGroup = ([0-9A-F]{24});", text)
    if g:
        main_group_ref = g.group(1)
    # Insert the tunnel group ref at the end of the main group's children.
    main_children = re.search(
        r"(" + main_group_ref + r" = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)(.*?)(\n\t\t\t\);)",
        text,
        re.S,
    )
    if not main_children:
        print("could not locate main group children", file=sys.stderr)
        return 1
    children = main_children.group(2)
    new_children = children + f'\n\t\t\t\t{U["group"]} /* BlackoutTunnel */,'
    text = text.replace(
        main_children.group(0),
        main_children.group(1) + new_children + main_children.group(3),
        1,
    )

    # Products group: add the appex product ref.
    m = re.search(
        r"([0-9A-F]{24}) /\* Products \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n",
        text,
    )
    if m:
        products_ref = m.group(1)
        # add child after the opening paren of the products group children
        idx = text.find(m.group(0)) + len(m.group(0))
        text = (
            text[:idx]
            + f'\n\t\t\t\t{U["product_fileref"]} /* BlackoutTunnel.appex */,'
            + text[idx:]
        )
        U["products_group"] = products_ref

    # ── PBXNativeTarget for the extension ─────────────────────────────────
    anchor = "/* Begin PBXNativeTarget section */\n"
    target_add = (
        f'\t\t{U["target"]} /* BlackoutTunnel */ = {{\n'
        '\t\t\tisa = PBXNativeTarget;\n'
        f'\t\t\tbuildConfigurationList = {U["cfglist"]} /* Build configuration list for PBXNativeTarget "BlackoutTunnel" */;\n'
        '\t\t\tbuildPhases = (\n'
        f'\t\t\t\t{U["sources_phase"]} /* Sources */,\n'
        f'\t\t\t\t{U["fw_phase"]} /* Frameworks */,\n'
        f'\t\t\t\t{U["script_phase"]} /* Copy Libbox */,\n'
        '\t\t\t);\n'
        '\t\t\tbuildRules = (\n'
        '\t\t\t);\n'
        '\t\t\tdependencies = (\n'
        '\t\t\t);\n'
        f'\t\t\tfileSystemSynchronizedGroups = (\n'
        '\t\t\t);\n'
        f'\t\t\tname = {TUNNEL_TARGET};\n'
        f'\t\t\tproductName = {TUNNEL_TARGET};\n'
        f'\t\t\tproductReference = {U["product_fileref"]} /* BlackoutTunnel.appex */;\n'
        '\t\t\tproductType = "com.apple.product-type.app-extension";\n'
        f'\t\t\tproductRefGroup = {U["products_group"]} /* Products */;\n'
        '\t\t};\n'
    )
    text = text.replace(anchor, anchor + target_add, 1)

    # ── PBXProject: targets list + target attributes ───────────────────────
    m = re.search(r"targets = \(\n(\t\t\t\t[0-9A-F]{24} /\* Runner \*/,)", text)
    if m:
        text = text.replace(
            m.group(1),
            m.group(1) + f'\n\t\t\t\t{U["target"]} /* BlackoutTunnel */,',
            1,
        )

    # ── PBXSourcesBuildPhase for the extension ────────────────────────────
    anchor = "/* Begin PBXSourcesBuildPhase section */\n"
    sources_add = (
        f'\t\t{U["sources_phase"]} /* Sources */ = {{\n'
        '\t\t\tisa = PBXSourcesBuildPhase;\n'
        '\t\t\tbuildActionMask = 2147483647;\n'
        '\t\t\tfiles = (\n'
        f'\t\t\t\t{U["sources_build"]} /* PacketTunnelProvider.swift in Sources */,\n'
        '\t\t\t);\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n'
    )
    text = text.replace(anchor, anchor + sources_add, 1)

    # ── PBXShellScriptBuildPhase (Copy Libbox) ────────────────────────────
    anchor = "/* Begin PBXShellScriptBuildPhase section */\n"
    if anchor not in text:
        # create section if missing
        text = text.replace(
            "/* End PBXShellScriptBuildPhase section */\n\n/* Begin PBXSourcesBuildPhase section */",
            "/* Begin PBXShellScriptBuildPhase section */\n"
            + f'\t\t{U["script_phase"]} /* Copy Libbox */ = {{\n'
            + '\t\t\tisa = PBXShellScriptBuildPhase;\n'
            + '\t\t\tbuildActionMask = 2147483647;\n'
            + '\t\t\tfiles = (\n'
            + '\t\t\t);\n'
            + '\t\t\tinputPaths = (\n'
            + '\t\t\t);\n'
            + '\t\t\tname = "Copy Libbox";\n'
            + '\t\t\toutputPaths = (\n'
            + '\t\t\t);\n'
            + '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
            + '\t\t\tshellPath = /bin/sh;\n'
            + f'\t\t\tshellScript = "{COPY_LIBBOX_SH}";\n'
            + '\t\t};\n'
            + "/* End PBXShellScriptBuildPhase section */\n\n/* Begin PBXSourcesBuildPhase section */",
            1,
        )
    else:
        script_escaped = COPY_LIBBOX_SH.replace("\n", "\\n").replace('"', '\\"')
        script_add = (
            f'\t\t{U["script_phase"]} /* Copy Libbox */ = {{\n'
            '\t\t\tisa = PBXShellScriptBuildPhase;\n'
            '\t\t\tbuildActionMask = 2147483647;\n'
            '\t\t\tfiles = (\n'
            '\t\t\t);\n'
            '\t\t\tinputPaths = (\n'
            '\t\t\t);\n'
            '\t\t\tname = "Copy Libbox";\n'
            '\t\t\toutputPaths = (\n'
            '\t\t\t);\n'
            '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
            '\t\t\tshellPath = /bin/sh;\n'
            f'\t\t\tshellScript = "{script_escaped}";\n'
            '\t\t};\n'
        )
        text = text.replace(anchor, anchor + script_add, 1)

    # ── XCConfigurationList + build configurations for the target ─────────
    anchor = "/* Begin XCConfigurationList section */\n"
    cfglist_add = (
        f'\t\t{U["cfglist"]} /* Build configuration list for PBXNativeTarget "BlackoutTunnel" */ = {{\n'
        '\t\t\tisa = XCConfigurationList;\n'
        '\t\t\tbuildConfigurations = (\n'
        f'\t\t\t\t{U["cfg_debug"]} /* Debug */,\n'
        f'\t\t\t\t{U["cfg_release"]} /* Release */,\n'
        '\t\t\t);\n'
        '\t\t\tdefaultConfigurationIsVisible = 0;\n'
        '\t\t\tdefaultConfigurationName = Release;\n'
        '\t\t};\n'
    )
    text = text.replace(anchor, anchor + cfglist_add, 1)

    anchor = "/* Begin XCBuildConfiguration section */\n"
    cfg_add = (
        f'\t\t{U["cfg_debug"]} /* Debug */ = {{\n'
        '\t\t\tisa = XCBuildConfiguration;\n'
        '\t\t\tbaseConfigurationReference = 9740EEB21CF90195004384FC /* Debug.xcconfig */;\n'
        '\t\t\tbuildSettings = {\n'
        '\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;\n'
        '\t\t\t\tBUNDLE_LOADER = ""; \n'
        f'\t\t\t\tCODE_SIGN_ENTITLEMENTS = BlackoutTunnel/BlackoutTunnel.entitlements;\n'
        '\t\t\t\tCURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";\n'
        '\t\t\t\tDEVELOPMENT_TEAM = "";\n'
        '\t\t\t\tENABLE_BITCODE = NO;\n'
        '\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");\n'
        '\t\t\t\tINFOPLIST_FILE = BlackoutTunnel/Info.plist;\n'
        '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 13.0;\n'
        '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n'
        '\t\t\t\t\t"$(inherited)",\n'
        '\t\t\t\t\t"@executable_path/Frameworks",\n'
        '\t\t\t\t\t"@executable_path/../../Frameworks",\n'
        '\t\t\t\t);\n'
        f'\t\t\t\tMARKETING_VERSION = 1.12;\n'
        f'\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{TUNNEL_BUNDLE_ID}";\n'
        '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
        '\t\t\t\tSDKROOT = iphoneos;\n'
        '\t\t\t\tSWIFT_VERSION = 5.0;\n'
        '\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";\n'
        '\t\t\t\tTEST_HOST = ""; \n'
        '\t\t\t};\n'
        '\t\t\tname = Debug;\n'
        '\t\t};\n'
        f'\t\t{U["cfg_release"]} /* Release */ = {{\n'
        '\t\t\tisa = XCBuildConfiguration;\n'
        '\t\t\tbaseConfigurationReference = 7AFA3C8E1D35360C0083082E /* Release.xcconfig */;\n'
        '\t\t\tbuildSettings = {\n'
        '\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;\n'
        f'\t\t\t\tCODE_SIGN_ENTITLEMENTS = BlackoutTunnel/BlackoutTunnel.entitlements;\n'
        '\t\t\t\tCURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";\n'
        '\t\t\t\tDEVELOPMENT_TEAM = "";\n'
        '\t\t\t\tENABLE_BITCODE = NO;\n'
        '\t\t\t\tINFOPLIST_FILE = BlackoutTunnel/Info.plist;\n'
        '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 13.0;\n'
        '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n'
        '\t\t\t\t\t"$(inherited)",\n'
        '\t\t\t\t\t"@executable_path/Frameworks",\n'
        '\t\t\t\t\t"@executable_path/../../Frameworks",\n'
        '\t\t\t\t);\n'
        '\t\t\t\tMARKETING_VERSION = 1.12;\n'
        f'\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{TUNNEL_BUNDLE_ID}";\n'
        '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
        '\t\t\t\tSDKROOT = iphoneos;\n'
        '\t\t\t\tSWIFT_VERSION = 5.0;\n'
        '\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";\n'
        '\t\t\t};\n'
        '\t\t\tname = Release;\n'
        '\t\t};\n'
    )
    text = text.replace(anchor, anchor + cfg_add, 1)

    # Runner entitlements: Runner needs the app-groups + network-extension
    # *request* capability only in the sense of NEManager usage; the tunnel
    # extension carries packet-tunnel-provider. Keep Runner clean.

    PBXPROJ.write_text(text, encoding="utf-8", newline="\n")
    print("BlackoutTunnel target added to Runner.xcodeproj")
    return 0


if __name__ == "__main__":
    sys.exit(main())
