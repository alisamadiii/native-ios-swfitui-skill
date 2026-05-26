#!/bin/bash
# Setup script for native-ios-swiftui skill
# Run this in the root of any new iOS project

set -e

SKILL_REPO="https://github.com/alisamadiii/native-ios-swfitui-skill.git"
SKILL_NAME="native-ios-swiftui"
TMP_DIR=$(mktemp -d)

echo "Setting up native-ios-swiftui skill..."

# 1. Clone skill repo to temp
git clone --depth 1 "$SKILL_REPO" "$TMP_DIR" 2>/dev/null

# 2. Copy skill into .claude/skills/
mkdir -p .claude/skills
cp -r "$TMP_DIR/$SKILL_NAME" ".claude/skills/$SKILL_NAME"

# 3. Cleanup
rm -rf "$TMP_DIR"

echo "Skill installed at .claude/skills/$SKILL_NAME"

# 4. Create CLAUDE.md if it doesn't exist
if [ ! -f "CLAUDE.md" ]; then
    PROJECT_NAME=$(basename "$(pwd)")
    cat > CLAUDE.md << 'CLAUDEEOF'
# Project Instructions

## Stack

- **Platform:** iOS 26 / iPadOS 26
- **Language:** Swift 6 (strict concurrency)
- **UI:** SwiftUI + Liquid Glass design system
- **IDE:** Xcode 26
- **Architecture:** MVVM with @Observable view models + actor services
- **Persistence:** SwiftData
- **Networking:** Actor-based APIClient with async/await
- **Auth:** Sign in with Apple (primary)
- **Payments:** StoreKit 2 with SubscriptionStoreView
- **Background:** BGAppRefreshTask + background URLSession

## Rules

- **All code goes in the current project directory.** Never create a new folder or Xcode project outside this directory. Use the existing Xcode project and folder structure. If the project is empty, create files directly inside it — do not scaffold a separate project alongside it.
- Read the `native-ios-swiftui` skill before implementing any view, animation, networking, auth, or payment code.
- Use native SwiftUI components first. Only customize when native falls short.
- Liquid Glass goes on navigation layer only — never on content rows or cards. Never glass on glass.
- Every view model: `@MainActor @Observable`. Every service: `actor`. Every DTO: `Sendable`.
- Use `List` for long homogeneous content, not `LazyVStack`.
- Use `.task { }` instead of `.onAppear { Task { } }`.
- Animate when data arrives, not when request fires.
- Sign in with Apple is mandatory if any third-party login exists.
- Store auth tokens in Keychain, never UserDefaults.
- Use `.storekit` configuration file for payment testing.

## Project structure

```
Views/          — SwiftUI views, thin, declarative
ViewModels/     — @MainActor @Observable, one per screen
Services/       — Actor-based: APIClient, AuthManager
Models/         — @Model (SwiftData) + Sendable DTOs
```

## Build & run

```bash
# Build
xcodebuild -scheme <SCHEME> -sdk iphonesimulator build

# Test
xcodebuild -scheme <SCHEME> -sdk iphonesimulator test
```
CLAUDEEOF
    echo "CLAUDE.md created"
else
    echo "CLAUDE.md already exists — skipped"
fi

echo "Done. Start a new Claude Code session to activate the skill."
