# Native iOS SwiftUI Skill

A Claude Code skill that enforces production-quality patterns for building iOS apps with Swift 6, SwiftUI, iOS 26 Liquid Glass, SwiftData, StoreKit 2, and Sign in with Apple.

## What it does

Before every implementation — views, animations, networking, auth, payments — Claude reads the skill and follows best practices automatically. No manual invocation needed.

**Covers:**
- iOS 26 Liquid Glass design system (what to use, what to avoid)
- Animations (toolbox, anti-patterns, glass morphing)
- Architecture (MVVM + `@Observable` + actor services)
- Networking (actor-based `APIClient`, token refresh, caching)
- Authentication (Sign in with Apple, OAuth, Keychain)
- Data persistence (SwiftData, offline-first sync)
- Payments (StoreKit 2, `SubscriptionStoreView`, entitlements)

## Installation

### Option A: One-liner (recommended)

Run this in the root of your iOS project:

```bash
curl -sL https://raw.githubusercontent.com/alisamadiii/native-ios-swfitui-skill/main/setup-ios-skill.sh | bash
```

This will:
1. Clone the skill into `.claude/skills/native-ios-swiftui/`
2. Create a `CLAUDE.md` with project rules and structure

### Option B: Manual

```bash
# 1. Clone the repo
git clone https://github.com/alisamadiii/native-ios-swfitui-skill.git /tmp/ios-skill

# 2. Copy skill into your project
mkdir -p .claude/skills
cp -r /tmp/ios-skill/native-ios-swiftui .claude/skills/native-ios-swiftui

# 3. Cleanup
rm -rf /tmp/ios-skill
```

Then create a `CLAUDE.md` in your project root (see `setup-ios-skill.sh` for a template).

## After installation

Start a new Claude Code session. The skill auto-triggers whenever you work on Swift/SwiftUI code.

## Skill structure

```
native-ios-swiftui/
├── SKILL.md                      # Core rules, pre-flight checklist, hard stops
└── references/
    ├── design-system.md          # Liquid Glass, component catalog, accessibility
    ├── architecture.md           # MVVM + @Observable, ViewState, DI patterns
    ├── animations.md             # Animation toolbox, glass morphing, anti-patterns
    ├── networking.md             # Actor APIClient, token refresh, caching
    ├── auth.md                   # Sign in with Apple, OAuth, Keychain
    ├── data.md                   # SwiftData models, queries, offline-first sync
    └── payments.md               # StoreKit 2, entitlements, SubscriptionStoreView
```
