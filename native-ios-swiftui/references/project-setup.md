# Project Setup Reference — XcodeGen

## Table of Contents
1. Why XcodeGen
2. Complete setup flow
3. project.yml template
4. Entitlements
5. Info.plist
6. StoreKit configuration
7. Build and run

---

## 1. Why XcodeGen

Xcode project files (`.xcodeproj`) are complex and not human-writable. XcodeGen generates them
from a simple YAML file. This means AI can create a fully buildable project from scratch.

**Requirement:** XcodeGen must be installed (`brew install xcodegen`). Check before using.

## 2. Complete setup flow

Every new project follows this exact sequence:

```
1. Create folder structure (Models/, Views/, ViewModels/, Services/, etc.)
2. Write all Swift source files
3. Write project.yml
4. Write entitlements file (if needed)
5. Write Info.plist (if needed)
6. Run `xcodegen generate`
7. Open .xcodeproj in Xcode
```

After `xcodegen generate`, the project is ready to build and run. No manual Xcode configuration.

## 3. project.yml template

This is the standard template for an iOS 26 SwiftUI app. Adapt the name and sources.

**Important:** Replace `<developer-id>` with the user's actual identifier (ask them).
Never use generic bundle IDs — they will fail provisioning because they're already claimed.

```yaml
name: AppName
options:
  bundleIdPrefix: com.<developer-id>
  deploymentTarget:
    iOS: "26.0"
  xcodeVersion: "26.0"
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    GENERATE_INFOPLIST_FILE: true
    CURRENT_PROJECT_VERSION: "1"
    MARKETING_VERSION: "1.0.0"

targets:
  AppName:
    type: application
    platform: iOS
    sources:
      - path: AppName
        excludes:
          - "**/.DS_Store"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.<developer-id>.appname
        INFOPLIST_FILE: AppName/Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: AppName/Resources/AppName.entitlements
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        PRODUCT_NAME: "$(TARGET_NAME)"
        SWIFT_EMIT_LOC_STRINGS: "YES"
        INFOPLIST_KEY_UILaunchScreen_Generation: true
        INFOPLIST_KEY_UISupportedInterfaceOrientations: "UIInterfaceOrientationPortrait"
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
    entitlements:
      path: AppName/Resources/AppName.entitlements
      properties:
        com.apple.developer.applesignin:
          - Default
```

### With StoreKit configuration

Add under the target's `scheme` section:

```yaml
targets:
  AppName:
    # ... all the above ...
    scheme:
      testTargets: []
      storeKitConfiguration: AppName/Resources/Products.storekit
```

### With app groups (for widgets)

```yaml
    entitlements:
      path: AppName/Resources/AppName.entitlements
      properties:
        com.apple.developer.applesignin:
          - Default
        com.apple.security.application-groups:
          - group.com.<developer-id>.appname
```

## 4. Entitlements file

Create at `AppName/Resources/AppName.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>
</dict>
</plist>
```

Add more entitlements as needed (push notifications, app groups, etc.).

## 5. Info.plist

Create at `AppName/Resources/Info.plist` — only needed for custom keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>com.<developer-id>.appname.refresh</string>
    </array>
    <key>UIBackgroundModes</key>
    <array>
        <string>fetch</string>
        <string>remote-notification</string>
    </array>
</dict>
</plist>
```

If no custom keys needed, set `GENERATE_INFOPLIST_FILE: true` in settings and skip this file.

## 6. StoreKit configuration

Create `AppName/Resources/Products.storekit` through Xcode:
File → New → File → StoreKit Configuration File

This cannot be generated as a text file — it must be created through Xcode's GUI.
However, after initial creation it can be edited as JSON.

Alternative: tell the user to create it manually after project generation, and document
the product IDs and prices in a comment in the entitlement manager.

## 7. Build and run

```bash
# Generate the Xcode project
cd /path/to/project
xcodegen generate

# Open in Xcode
open AppName.xcodeproj

# Or build from command line
xcodebuild -project AppName.xcodeproj -scheme AppName -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run on simulator
xcodebuild -project AppName.xcodeproj -scheme AppName -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
open -a Simulator
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/AppName.app
xcrun simctl launch booted com.<developer-id>.appname
```

## Full directory structure after setup

```
ProjectRoot/
├── project.yml                          # XcodeGen spec
├── AppName.xcodeproj/                   # Generated — do not edit manually
├── AppName/
│   ├── App.swift
│   ├── Models/
│   │   ├── SomeModel.swift
│   │   └── DTOs/
│   │       └── SomeDTO.swift
│   ├── Services/
│   │   ├── APIClient.swift
│   │   ├── AuthManager.swift
│   │   └── Protocols/
│   │       └── SomeServicing.swift
│   ├── ViewModels/
│   │   └── SomeViewModel.swift
│   ├── Views/
│   │   ├── Feature/
│   │   │   └── FeatureView.swift
│   │   └── Components/
│   │       └── SharedComponent.swift
│   └── Resources/
│       ├── Assets.xcassets/
│       │   └── AppIcon.appiconset/
│       │       └── Contents.json
│       ├── AppName.entitlements
│       ├── Info.plist
│       └── Products.storekit
└── .claude/
    └── skills/
        └── native-ios-swiftui/
```
