#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project using only Python's standard library.

The checked-in project is built directly by CI; no generator or third-party Xcode
package is required to open/build it. Run this after adding/removing source files.
"""
import hashlib
import json
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
OBJECTS = {}


def identifier(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()


def add(label, isa, **values):
    key = identifier(label)
    OBJECTS[key] = {"isa": isa, **values}
    return key


def file_ref(path, file_type):
    return add("file:" + path, "PBXFileReference", lastKnownFileType=file_type,
               path=path, sourceTree="<group>")


def build_ref(target, path, ref, **extra):
    return add(f"build:{target}:{path}", "PBXBuildFile", fileRef=ref, **extra)


def render(value, level=0):
    indent = "\t" * level
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append("\t" * (level + 1) + json.dumps(str(key)) + " = " + render(item, level + 1) + ";")
        return "\n".join(lines) + "\n" + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (level + 1) + render(item, level + 1) + ",\n" for item in value) + indent + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)


def project():
    OBJECTS.clear()
    project_id = identifier("project")
    targets = {name: identifier("target:" + name) for name in ["WeatherApp", "WeatherWidgets", "WeatherAppTests"]}
    shared = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Shared").rglob("*.swift"))
    app = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "WeatherApp").rglob("*.swift"))
    widgets = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "WeatherWidgets").rglob("*.swift"))
    tests = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "WeatherAppTests").rglob("*.swift"))
    refs = {p: file_ref(p, "sourcecode.swift") for p in shared + app + widgets + tests}
    resource_types = {"Shared/Resources/Localizable.xcstrings": "text.json.xcstrings",
                      "Shared/Resources/PrivacyInfo.xcprivacy": "text.xml",
                      "WeatherApp/Assets.xcassets": "folder.assetcatalog"}
    refs.update({p: file_ref(p, typ) for p, typ in resource_types.items()})
    info_children = []
    for lang in ["en", "pt-BR"]:
        info_children.append(add("info:" + lang, "PBXFileReference", lastKnownFileType="text.plist.strings",
            name=lang, path=f"WeatherApp/Resources/{lang}.lproj/InfoPlist.strings", sourceTree="<group>"))
    info_variant = add("InfoPlist.strings", "PBXVariantGroup", children=info_children,
                       name="InfoPlist.strings", sourceTree="<group>")
    config = file_ref("Config/Project.xcconfig", "text.xcconfig")
    support_refs = [config, file_ref("Config/AppIcon.svg", "text.xml"), file_ref("README.md", "net.daringfireball.markdown")]
    for target in ["WeatherApp", "WeatherWidgets"]:
        support_refs += [file_ref(f"{target}/Info.plist", "text.plist.xml"),
                         file_ref(f"{target}/{target}.entitlements", "text.plist.entitlements")]

    products = {}
    for name, extension, typ in [("WeatherApp", "app", "wrapper.application"),
                                 ("WeatherWidgets", "appex", "wrapper.app-extension"),
                                 ("WeatherAppTests", "xctest", "wrapper.cfbundle")]:
        products[name] = add("product:" + name, "PBXFileReference", explicitFileType=typ,
                            includeInIndex=0, path=f"{name}.{extension}", sourceTree="BUILT_PRODUCTS_DIR")

    framework_refs = {}
    for name in ["SwiftUI", "WeatherKit", "CoreLocation", "WidgetKit", "Foundation", "UIKit"]:
        framework_refs[name] = add("framework:" + name, "PBXFileReference", lastKnownFileType="wrapper.framework",
            name=name + ".framework", path=f"System/Library/Frameworks/{name}.framework", sourceTree="SDKROOT")

    groups = []
    for name, paths in [("Shared", shared), ("WeatherApp", app), ("WeatherWidgets", widgets), ("WeatherAppTests", tests)]:
        groups.append(add("group:" + name, "PBXGroup", children=[refs[p] for p in paths], name=name, sourceTree="<group>"))
    groups.append(add("group:Resources", "PBXGroup", children=[refs[p] for p in resource_types] + [info_variant],
                      name="Resources", sourceTree="<group>"))
    groups.append(add("group:Configuration", "PBXGroup", children=support_refs, name="Configuration", sourceTree="<group>"))
    groups.append(add("group:Frameworks", "PBXGroup", children=list(framework_refs.values()), name="Frameworks", sourceTree="<group>"))
    products_group = add("group:Products", "PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>")
    root_group = add("group:Root", "PBXGroup", children=groups + [products_group], sourceTree="<group>")

    project_configs = []
    for mode in ["Debug", "Release"]:
        settings = {
            "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
            "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "CLANG_WARN_UNREACHABLE_CODE": "YES",
            "ENABLE_STRICT_OBJC_MSGSEND": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
            "GCC_NO_COMMON_BLOCKS": "YES", "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
            "GCC_WARN_UNDECLARED_SELECTOR": "YES", "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
            "SDKROOT": "iphoneos", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "TARGETED_DEVICE_FAMILY": "1", "SWIFT_EMIT_LOC_STRINGS": "YES",
            "STRING_CATALOG_GENERATE_SYMBOLS": "NO", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym",
            "ONLY_ACTIVE_ARCH": "YES" if mode == "Debug" else "NO",
        }
        if mode == "Debug":
            settings.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG",
                             "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "DEBUG=1"], "ENABLE_TESTABILITY": "YES"})
        else:
            settings.update({"SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})
        project_configs.append(add("config:project:" + mode, "XCBuildConfiguration", baseConfigurationReference=config,
                                   buildSettings=settings, name=mode))
    project_config_list = add("configs:project", "XCConfigurationList", buildConfigurations=project_configs,
                             defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    for target, source_paths in [("WeatherApp", shared + app), ("WeatherWidgets", shared + widgets), ("WeatherAppTests", tests)]:
        phases = [add("sources:" + target, "PBXSourcesBuildPhase", buildActionMask=2147483647,
                      files=[build_ref(target, p, refs[p]) for p in source_paths], runOnlyForDeploymentPostprocessing=0)]
        phases.append(add("frameworks:" + target, "PBXFrameworksBuildPhase", buildActionMask=2147483647,
                          files=[build_ref(target, n + ".framework", r) for n, r in framework_refs.items()],
                          runOnlyForDeploymentPostprocessing=0))
        resources = []
        if target != "WeatherAppTests":
            resources += [build_ref(target, p, refs[p]) for p in resource_types if p.startswith("Shared/")]
        if target == "WeatherApp":
            resources += [build_ref(target, "Assets.xcassets", refs["WeatherApp/Assets.xcassets"]),
                          build_ref(target, "InfoPlist.strings", info_variant)]
        phases.append(add("resources:" + target, "PBXResourcesBuildPhase", buildActionMask=2147483647,
                          files=resources, runOnlyForDeploymentPostprocessing=0))
        dependencies = []
        dependency_target = {"WeatherApp": "WeatherWidgets", "WeatherAppTests": "WeatherApp"}.get(target)
        if dependency_target:
            proxy = add("proxy:" + target, "PBXContainerItemProxy", containerPortal=project_id, proxyType=1,
                        remoteGlobalIDString=targets[dependency_target], remoteInfo=dependency_target)
            dependencies.append(add("dependency:" + target, "PBXTargetDependency", target=targets[dependency_target], targetProxy=proxy))
        if target == "WeatherApp":
            embedded = build_ref(target, "Embed WeatherWidgets", products["WeatherWidgets"],
                                 settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
            phases.append(add("embed:widgets", "PBXCopyFilesBuildPhase", buildActionMask=2147483647,
                dstPath="", dstSubfolderSpec=13, files=[embedded], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0))

        configs = []
        for mode in ["Debug", "Release"]:
            settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "SWIFT_VERSION": "5.0",
                        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
                        "GENERATE_INFOPLIST_FILE": "NO"}
            if target == "WeatherAppTests":
                settings.update({"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "$(APP_BUNDLE_IDENTIFIER).tests",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/WeatherApp.app/WeatherApp",
                    "BUNDLE_LOADER": "$(TEST_HOST)", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]})
            else:
                settings.update({"INFOPLIST_FILE": f"{target}/Info.plist", "CODE_SIGN_ENTITLEMENTS": f"{target}/{target}.entitlements",
                    "PRODUCT_BUNDLE_IDENTIFIER": "$(APP_BUNDLE_IDENTIFIER)" + (".widgets" if target == "WeatherWidgets" else ""),
                    "SWIFT_INSTALL_OBJC_HEADER": "NO"})
            if target == "WeatherWidgets":
                settings.update({"APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
                    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]})
            if target == "WeatherApp":
                settings.update({"ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "SKIP_INSTALL": "NO"})
            configs.append(add(f"config:{target}:{mode}", "XCBuildConfiguration", buildSettings=settings, name=mode))
        configs_id = add("configs:" + target, "XCConfigurationList", buildConfigurations=configs,
                         defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
        add("target:" + target, "PBXNativeTarget", buildConfigurationList=configs_id, buildPhases=phases,
            buildRules=[], dependencies=dependencies, name=target, productName=target, productReference=products[target],
            productType={"WeatherApp": "com.apple.product-type.application", "WeatherWidgets": "com.apple.product-type.app-extension",
                         "WeatherAppTests": "com.apple.product-type.bundle.unit-test"}[target])

    attributes = {targets[name]: {"CreatedOnToolsVersion": "16.4"} for name in targets}
    attributes[targets["WeatherAppTests"]]["TestTargetID"] = targets["WeatherApp"]
    for name in ["WeatherApp", "WeatherWidgets"]:
        attributes[targets[name]]["SystemCapabilities"] = {
            "com.apple.WeatherKit": {"enabled": 1}, "com.apple.ApplicationGroups.iOS": {"enabled": 1}}
    add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1640", "TargetAttributes": attributes},
        buildConfigurationList=project_config_list, compatibilityVersion="Xcode 14.0", developmentRegion="en",
        hasScannedForEncodings=0, knownRegions=["en", "pt-BR", "Base"], mainGroup=root_group,
        productRefGroup=products_group, projectDirPath="", projectRoot="", targets=list(targets.values()))
    return {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": OBJECTS, "rootObject": project_id}


def buildable(name, extension):
    return (f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier("target:" + name)}" '
            f'BuildableName="{escape(name)}.{extension}" BlueprintName="{escape(name)}" ReferencedContainer="container:WeatherApp.xcodeproj"/>')


def scheme():
    app = buildable("WeatherApp", "app")
    tests = buildable("WeatherAppTests", "xctest")
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app}</BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" language="pt-BR" region="BR">
    <Testables><TestableReference skipped="NO" parallelizable="NO">{tests}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''


if __name__ == "__main__":
    destination = ROOT / "WeatherApp.xcodeproj"
    destination.mkdir(exist_ok=True)
    (destination / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(project()) + "\n")
    schemes = destination / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / "WeatherApp.xcscheme").write_text(scheme())
    print(f"Generated project with {len(OBJECTS)} objects and a shared WeatherApp scheme.")
