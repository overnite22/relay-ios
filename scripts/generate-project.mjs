// Génère Relay.xcodeproj (projet, cibles, schéma partagé). Ne pas éditer le projet à la main :
// relancer `node scripts/generate-project.mjs` après tout ajout, suppression ou déplacement de fichier .swift.
import fs from "node:fs";
import path from "node:path";

const previous = fs.existsSync("Relay.xcodeproj/project.pbxproj") ? fs.readFileSync("Relay.xcodeproj/project.pbxproj", "utf8") : "";
function existing(key, fallback, pattern) {
  const values = [...new Set([...previous.matchAll(new RegExp(key + "\\s*=\\s*\"?([^\";\\s]+)\"?;", "g"))].map((m) => m[1]))];
  if (values.length > 1 || (values.length === 1 && !pattern.test(values[0]))) throw new Error("Invalid or conflicting " + key);
  return values[0] ?? fallback;
}
// BUNDLE_PREFIX permet une identité de signature personnelle.
const bundlePrefix = process.env.BUNDLE_PREFIX || "io.github.overnite22";
if (!/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(bundlePrefix)) throw new Error("Invalid BUNDLE_PREFIX");
const version = process.env.APP_VERSION || existing("MARKETING_VERSION", "0.1.0", /^\d+\.\d+\.\d+$/);
const build = process.env.APP_BUILD || existing("CURRENT_PROJECT_VERSION", "1", /^\d+$/);
if (!/^\d+\.\d+\.\d+$/.test(version) || !/^\d+$/.test(build)) throw new Error("Invalid APP_VERSION / APP_BUILD");
const deployment = "26.0";

const objects = [];
let sequence = 1;
const id = () => (sequence++).toString(16).toUpperCase().padStart(24, "0");
const add = (body, key = id()) => { objects.push([key, body]); return key; };
const q = JSON.stringify;
const list = (items) => "(" + items.join(", ") + (items.length ? "," : "") + ")";
const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))
  .flatMap((e) => (e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)])).filter((f) => f.endsWith(".swift"));

const projectID = id(), mainGroupID = id(), productsID = id(), appTargetID = id();
const packageRef = add("isa = XCLocalSwiftPackageReference; relativePath = RelayKit;");
const packageFolder = add('isa = PBXFileReference; lastKnownFileType = wrapper; path = RelayKit; sourceTree = "<group>";');
const groups = [], productIDs = [], targetIDs = [];
const infoKeys = [
  "INFOPLIST_KEY_CFBundleDisplayName = Relay;",
  "INFOPLIST_KEY_UILaunchScreen_Generation = YES;",
  'INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";',
  "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;",
  "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;",
  'INFOPLIST_KEY_NSCameraUsageDescription = "Relay utilise la caméra uniquement pour lire le QR code d\'appairage affiché par Relay web. Aucune image n\'est enregistrée ni envoyée.";',
  'INFOPLIST_KEY_NSFaceIDUsageDescription = "Face ID protège l\'affichage des mots de passe, clés et codes du coffre Relay.";',
  'INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Relay se connecte à votre serveur Relay, qui peut se trouver sur votre réseau local.";',
  "INFOPLIST_KEY_CFBundleAllowMixedLocalizations = YES;",
].join(" ");

function target(name, dir, productType, kind) {
  const targetID = kind === "app" ? appTargetID : id();
  targetIDs.push(targetID);
  const files = walk(dir).map((f) => {
    const ref = add("isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = " + q(f.replaceAll("\\", "/")) + "; sourceTree = SOURCE_ROOT;");
    return { ref, build: add("isa = PBXBuildFile; fileRef = " + ref + ";") };
  });
  const resources = kind !== "app" ? [] : [
    ["Relay/Resources/Assets.xcassets", "folder.assetcatalog"],
    ["Relay/Resources/PrivacyInfo.xcprivacy", "text.xml"],
  ].map(([file, type]) => {
    const ref = add("isa = PBXFileReference; lastKnownFileType = " + type + "; path = " + q(file) + "; sourceTree = SOURCE_ROOT;");
    return { ref, build: add("isa = PBXBuildFile; fileRef = " + ref + ";") };
  });
  groups.push(add("isa = PBXGroup; children = " + list([...files, ...resources].map((f) => f.ref)) + "; name = " + name + '; sourceTree = "<group>";'));
  const product = add("isa = PBXFileReference; explicitFileType = " + (kind === "app" ? "wrapper.application" : "wrapper.cfbundle") +
    "; includeInIndex = 0; path = " + name + (kind === "app" ? ".app" : ".xctest") + "; sourceTree = BUILT_PRODUCTS_DIR;");
  productIDs.push(product);
  const packageDeps = [];
  const frameworkFiles = [];
  if (kind === "app") {
    const dep = add("isa = XCSwiftPackageProductDependency; package = " + packageRef + "; productName = RelayKit;");
    packageDeps.push(dep);
    frameworkFiles.push(add("isa = PBXBuildFile; productRef = " + dep + ";"));
  }
  const phases = [
    add("isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = " + list(files.map((f) => f.build)) + "; runOnlyForDeploymentPostprocessing = 0;"),
    add("isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = " + list(frameworkFiles) + "; runOnlyForDeploymentPostprocessing = 0;"),
    add("isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = " + list(resources.map((f) => f.build)) + "; runOnlyForDeploymentPostprocessing = 0;"),
  ];
  const common = "PRODUCT_NAME = \"$(TARGET_NAME)\"; PRODUCT_BUNDLE_IDENTIFIER = " + bundlePrefix + "." + name +
    "; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic; SWIFT_VERSION = 5.0; SWIFT_STRICT_CONCURRENCY = minimal;" +
    " IPHONEOS_DEPLOYMENT_TARGET = " + deployment + "; TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";" +
    " SUPPORTS_MACCATALYST = NO; SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO; ";
  const specific = kind === "app"
    ? "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; " + infoKeys +
      " CURRENT_PROJECT_VERSION = " + build + "; MARKETING_VERSION = " + version + "; "
    : kind === "ui" ? "TEST_TARGET_NAME = Relay; "
    : 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Relay.app/Relay"; BUNDLE_LOADER = "$(TEST_HOST)"; ';
  const configs = ["Debug", "Release"].map((c) => add("isa = XCBuildConfiguration; name = " + c + "; buildSettings = { " + common + specific + "};"));
  const configList = add("isa = XCConfigurationList; buildConfigurations = " + list(configs) + "; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;");
  const deps = [];
  if (kind !== "app") {
    const proxy = add("isa = PBXContainerItemProxy; containerPortal = " + projectID + "; proxyType = 1; remoteGlobalIDString = " + appTargetID + "; remoteInfo = Relay;");
    deps.push(add("isa = PBXTargetDependency; target = " + appTargetID + "; targetProxy = " + proxy + ";"));
  }
  add("isa = PBXNativeTarget; buildConfigurationList = " + configList + "; buildPhases = " + list(phases) + "; buildRules = (); dependencies = " +
    list(deps) + "; name = " + name + "; packageProductDependencies = " + list(packageDeps) + "; productName = " + name +
    "; productReference = " + product + "; productType = " + q(productType) + ";", targetID);
  return targetID;
}

target("Relay", "Relay", "com.apple.product-type.application", "app");
const unit = target("RelayTests", "RelayTests", "com.apple.product-type.bundle.unit-test", "unit");
const ui = target("RelayUITests", "RelayUITests", "com.apple.product-type.bundle.ui-testing", "ui");
add("isa = PBXGroup; children = " + list(productIDs) + '; name = Products; sourceTree = "<group>";', productsID);
add("isa = PBXGroup; children = " + list([packageFolder, ...groups, productsID]) + '; sourceTree = "<group>";', mainGroupID);
const projectConfigs = ["Debug", "Release"].map((c) => add("isa = XCBuildConfiguration; name = " + c + "; buildSettings = { SDKROOT = iphoneos; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SWIFT_OPTIMIZATION_LEVEL = " +
  q(c === "Debug" ? "-Onone" : "-O") + "; " + (c === "Debug" ? "ENABLE_TESTABILITY = YES; ONLY_ACTIVE_ARCH = YES; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;" : 'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";') + " };"));
const projectConfigList = add("isa = XCConfigurationList; buildConfigurations = " + list(projectConfigs) + "; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;");
add("isa = PBXProject; attributes = { LastUpgradeCheck = 2600; }; buildConfigurationList = " + projectConfigList +
  '; compatibilityVersion = "Xcode 15.0"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, Base); mainGroup = ' + mainGroupID +
  "; packageReferences = " + list([packageRef]) + "; productRefGroup = " + productsID + '; projectDirPath = ""; projectRoot = ""; targets = ' + list(targetIDs) + ";", projectID);

objects.sort((a, b) => a[0].localeCompare(b[0]));
fs.mkdirSync("Relay.xcodeproj/xcshareddata/xcschemes", { recursive: true });
fs.writeFileSync("Relay.xcodeproj/project.pbxproj", "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n" +
  objects.map(([k, v]) => k + " = { " + v + " };").join("\n") + "\n}; rootObject = " + projectID + "; }\n");
const ref = (key, name) => '<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="' + key + '" BuildableName="' + name +
  (name === "Relay" ? ".app" : ".xctest") + '" BlueprintName="' + name + '" ReferencedContainer="container:Relay.xcodeproj"/>';
fs.writeFileSync("Relay.xcodeproj/xcshareddata/xcschemes/Relay.xcscheme", '<?xml version="1.0" encoding="UTF-8"?>\n' +
  '<Scheme LastUpgradeVersion="2600" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>' +
  '<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">' + ref(appTargetID, "Relay") + "</BuildActionEntry></BuildActionEntries></BuildAction>" +
  '<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>' +
  '<TestableReference skipped="NO">' + ref(unit, "RelayTests") + '</TestableReference><TestableReference skipped="NO">' + ref(ui, "RelayUITests") + "</TestableReference></Testables></TestAction>" +
  '<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO">' +
  '<BuildableProductRunnable runnableDebuggingMode="0">' + ref(appTargetID, "Relay") + "</BuildableProductRunnable></LaunchAction>" +
  '<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">' + ref(appTargetID, "Relay") + "</BuildableProductRunnable></ProfileAction>" +
  '<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n');
console.log("Projet généré : " + targetIDs.length + " cibles, version " + version + " (" + build + ").");
