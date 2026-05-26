---
name: native-ios-swiftui
description: >
  Premium native iOS app development with SwiftUI, iOS 26 Liquid Glass, Swift 6 strict concurrency,
  SwiftData, StoreKit 2, and Sign in with Apple. Enforces production-quality architecture, animations,
  and design from day one. Use this skill whenever building any iOS or iPadOS app from scratch, adding
  features to existing SwiftUI projects, designing screens or views, implementing authentication,
  setting up in-app purchases or subscriptions, creating animations, building networking layers, or
  working with SwiftData persistence. Also trigger when the user mentions Swift, SwiftUI, Xcode,
  iOS app, iPhone app, iPad app, mobile app (in Apple context), Liquid Glass, or any iOS framework
  like StoreKit, AuthenticationServices, or BackgroundTasks — even if they don't explicitly ask
  for this skill.
---

# Native iOS SwiftUI Skill

Build every iOS app like a senior Swift engineer would — with native components, strict concurrency,
and production-ready patterns. This skill is your pre-flight checklist: read it before writing any
SwiftUI view, networking code, animation, auth flow, or payment screen.

## Why this skill exists

SwiftUI with iOS 26 gives you a massive amount of polish for free — Liquid Glass navigation bars,
tab bars, toolbars, sheets — but only if you let the system work. The most common AI mistake is
over-customizing: applying `.glassEffect()` to content rows, stacking glass on glass, wrapping
network calls in `withAnimation`, using `LazyVStack` when `List` is 10x faster. This skill
prevents those mistakes and channels effort into what actually matters.

---

## Pre-flight checklist (read before every change)

Before implementing anything, verify:

0. **Am I writing code in the current project directory?** All code belongs inside the existing
   project. Never create a new Xcode project or folder outside the current working directory.
   If the project is empty, create files directly inside it.
1. **Am I using a native component where one exists?** Check `references/design-system.md` for the
   component catalog. SwiftUI has built-in solutions for navigation, tabs, search, toolbars, sheets,
   alerts, menus, toggles, sliders, pickers, and subscription paywalls. Use them.
2. **Is my glass only on the navigation layer?** `.glassEffect()` belongs on floating controls that
   sit above content — FABs, floating toolbars, action buttons. Never on list rows, cards, or
   content containers. Never glass on glass.
3. **Is my view model `@MainActor @Observable`?** Not `ObservableObject`. Not `@StateObject`.
4. **Are my services actors?** Networking, caching, auth token management — all actors.
5. **Am I using `List` for long homogeneous content?** Not `ScrollView + LazyVStack` unless layout
   demands it.
6. **Am I animating the result, not the request?** `withAnimation` wraps the state change when data
   arrives, not the async call that fetches it.

---

## Architecture — one pattern, no decisions needed

```
App
├── Views/          (SwiftUI views, thin, declarative)
├── ViewModels/     (@MainActor @Observable classes, one per screen)
├── Services/       (actor-based: APIClient, AuthManager, ImageCache)
├── Models/         (SwiftData @Model classes + Sendable DTOs)
└── App.swift       (entry point, .modelContainer, .backgroundTask)
```

**The rule:** Views own state via `@State` on an `@Observable` view model. View models call actor
services. Services never touch UI. Dependencies flow via initializer injection (screen-local) or
`@Environment` (cross-cutting like auth, analytics, current user).

Read `references/architecture.md` for the full pattern with code examples, dependency injection
setup, and the `ViewState<T>` pattern for loading/error/loaded states.

---

## Design system — iOS 26 Liquid Glass

The single most important design rule: **Liquid Glass is a navigation-layer material, not a content
material.** Apple says it verbatim. Recompiling against iOS 26 SDK gives you glass on nav bars, tab
bars, toolbars, sheets, popovers, menus, alerts, search bars, toggles, sliders, and pickers for
free. Custom glass is the exception.

Read `references/design-system.md` before building any screen. It covers:
- What you get for free (just recompile)
- When and how to apply custom `.glassEffect()`
- The `GlassEffectContainer` grouping rule
- Tab bar APIs (search role, minimize behavior, bottom accessory)
- Toolbar organization with `ToolbarSpacer`
- Tinting rules (only primary CTAs)
- Accessibility (Reduce Transparency, Increase Contrast, Reduce Motion — all automatic)

---

## Animations

Good iOS animations are transforms and opacity — they're GPU-cheap. Bad animations cause layout
recalculations inside scroll views.

Read `references/animations.md` before adding any animation. Key rules:
- Use `.animation(_:value:)` for declarative, `withAnimation` for imperative
- Animate when value lands, not when request fires
- Use `matchedGeometryEffect` for hero transitions between two representations
- Use `PhaseAnimator` for multi-step loops, `KeyframeAnimator` for choreographed sequences
- Glass morphing uses `GlassEffectContainer` + `.glassEffectID(_:in:)`
- Never animate layout-affecting properties inside scrolling lists

---

## Networking

One `APIClient` actor. One `Endpoint<R: Decodable & Sendable>` struct. One `AuthManager` actor
with single-flight token refresh.

Read `references/networking.md` for the complete implementation including:
- The generic `APIClient` actor pattern
- Auth token refresh with single in-flight `Task` (prevents duplicate refreshes)
- Error handling with `APIError` enum and `ViewState<T>`
- Caching strategies (HTTP cache, offline-first SwiftData, image cache)
- When to use configured API instance vs raw URLSession (third-party URLs like S3 presigned)

---

## Authentication

Sign in with Apple is mandatory if you offer any third-party login (App Store Guideline 4.8).
Make it the primary path regardless — it's the smoothest UX on iOS.

Read `references/auth.md` for:
- Complete Sign in with Apple implementation with nonce
- Critical gotcha: Apple sends name/email only on first sign-in
- Server-side verification requirements
- OAuth via `ASWebAuthenticationSession`
- Token storage in Keychain

---

## Data persistence — SwiftData

SwiftData is the default for new iOS 17+ projects. Use `@Model` classes, wire up with
`.modelContainer(for:)` in your App.

Read `references/data.md` for:
- Model definition patterns with `@Attribute` and `@Relationship`
- When to fall back to Core Data (shared/public CloudKit, complex migrations)
- Offline-first sync pattern: read SwiftData -> async fetch -> write back
- Schema migration

---

## Payments — StoreKit 2

Use the SwiftUI-native StoreKit views. `SubscriptionStoreView` handles products, prices,
localization, restore, and purchase in one component.

Read `references/payments.md` for:
- `SubscriptionStoreView` paywall implementation
- `StoreView` and `ProductView` for non-subscription products
- Listening to `Transaction.updates` for entitlement changes
- `.storekit` configuration for local testing
- App Store Server Notifications V2
- When to use RevenueCat/Glassfy

---

## Concurrency — Swift 6 strict

Swift 6 language mode with complete strict concurrency is the baseline. Region-based isolation
cuts annotation noise by 50-70% compared to Swift 5.10.

Rules:
- View models: `@MainActor @Observable`
- Services: `actor`
- DTOs: `struct` conforming to `Sendable` and `Codable`
- Never use `@unchecked Sendable` without a documented lock
- Never use `DispatchQueue.main.async` — use `@MainActor`
- Never use `.onAppear { Task { } }` — use `.task { }` (auto-cancels)
- Store long-lived tasks, cancel on deinit

---

## Hard stops — never do these

These will be caught in review. Don't ship them:

| Anti-pattern | Why | Fix |
|---|---|---|
| `.glassEffect()` on list rows or cards | Apple explicitly forbids glass on content | Remove it; content stays flat |
| Glass on glass | "Always avoid glass on glass" — Apple | One glass layer only |
| `ObservableObject` + `@Published` in new code | `@Observable` tracks per-property, massive perf win | Migrate to `@Observable` |
| `LazyVStack` for >50 homogeneous rows | 10x slower than `List` in benchmarks | Use `List` |
| `withAnimation { Task { await ... } }` | Animation transaction gone by await | `withAnimation` after data lands |
| `@unchecked Sendable` without lock | Data race waiting to happen | Use actor or add documented lock |
| `try!` or force-unwrap on network data | Crash in production | Proper error handling |
| `DispatchQueue.main.async` in async code | Swift 6 anti-pattern | `@MainActor` isolation |
| `.onAppear { Task { } }` | No auto-cancellation on disappear | `.task { }` modifier |
| `Data(contentsOf:)` on URL synchronously | Blocks calling thread | `URLSession` async |
| Tinting every glass element | "When every element is tinted, nothing stands out" | Tint only primary CTA |
| Mixing Regular and Clear glass variants | "They should never be mixed" — Apple | Pick one per context |

---

## Project setup checklist (new projects)

When starting a new iOS project:

1. Xcode 26, iOS 26 deployment target, Swift 6 language mode
2. Enable capabilities: Push Notifications, Sign in with Apple, Background Modes (App Refresh + Remote Notifications)
3. Create `.storekit` configuration file for payment testing
4. Set up folder structure: Views/, ViewModels/, Services/, Models/
5. Create `APIClient` actor and `AuthManager` actor
6. Add `@Model` classes for SwiftData
7. Wire `.modelContainer(for:)` in App.swift
8. Build with native components first — customize only when native falls short
