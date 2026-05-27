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

## First-time project setup — ask the user

Before writing any code in a new project, ask the user these questions and wait for answers:

1. **Apple Developer account type?**
   - **Paid ($99/year)** — full capabilities: Sign in with Apple, Push Notifications, App Groups, StoreKit testing on device
   - **Personal (free)** — limited: no Sign in with Apple, no push notifications, no App Groups. Use mock auth for testing, skip entitlements that require paid account.

2. **Does the app need a backend API?**
   - **Yes** — set up the full `APIClient` actor + `AuthManager` with token refresh
   - **No (offline-only)** — skip networking layer, use SwiftData only

3. **Does the app need authentication?**
   - **Yes** — ask which providers: Apple, Google, or both. Add sign-in UI on the last onboarding
     page. Sign in with Apple is required if any third-party login is offered (App Store Guideline 4.8).
   - **No** — skip auth entirely, onboarding ends with a Continue button that goes straight to home.

4. **Does the app need payments/subscriptions?**
   - **Yes** — set up StoreKit 2 with `.storekit` config file
   - **No** — skip `EntitlementManager` and paywall

5. **What is your name or company identifier?** (e.g., "alisamadi", "mycompany")
   - Used for bundle ID: `com.<identifier>.<appname>`
   - Never use generic bundle IDs like `com.streaks.app` or `com.appname.app` — they are already
     claimed globally and will fail provisioning. Always use the developer's own identifier.

Store the answers and adapt the project accordingly:

**Personal (free) account adaptations:**
- **Never** include `com.apple.developer.applesignin` in the entitlements file — Personal teams
  cannot provision this capability. Xcode will fail with: "Cannot create a iOS Development
  provisioning profile... Personal development teams do not support the Sign in with Apple capability."
- **Never** include push notification entitlements — same restriction.
- Replace Sign in with Apple with a `#if DEBUG` mock auth flow:
  ```swift
  // In your auth view, provide a dev-mode bypass:
  #if DEBUG
  Button("Dev Sign In") {
      // Skip real auth, create a mock user session
      Task { await authState.mockSignIn() }
  }
  #endif
  ```
- Add a comment at the top of the auth view:
  `// TODO: Replace mock auth with Sign in with Apple when using paid Apple Developer account`
- StoreKit sandbox testing still works on simulator without paid account
- The entitlements file should be **empty** (or omitted entirely) for personal teams — do not
  include any capabilities that require paid enrollment

**Bundle ID rules (all account types):**
- Format: `com.<developer-identifier>.<appname>` (e.g., `com.alisamadi.streaks`)
- Never use generic prefixes like `com.streaks`, `com.app`, `com.example`
- The identifier must be unique across all Apple developers globally
- Ask the user for their identifier if not already known

---

## Pre-flight checklist (read before every change)

Before implementing anything, verify:

0. **Am I writing code in the current project directory?** All code belongs inside the current
   working directory. Never create folders outside it. For new projects, use XcodeGen to generate
   a buildable `.xcodeproj` — see "Project setup" section and `references/project-setup.md`.
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

## Onboarding — rules

Onboarding is a full-screen flow, not a sheet. It must be the first thing users see.

1. **Full-screen, not a sheet.** Use a conditional root view (`if !hasOnboarded { OnboardingView() } else { MainTabView() }`). Never present onboarding as `.sheet` or `.fullScreenCover` — the home screen should not be visible behind it.
2. **Always show a Continue button.** Fixed at the bottom of every page. Users won't discover swipe-to-advance on their own. Style: `.buttonStyle(.glassProminent)`, `.tint(.blue)`, `.buttonBorderShape(.roundedRectangle(radius: 19))`, full-width, with `.sensoryFeedback(.increase, trigger:)` for haptic feedback.
3. **Last page = sign-in (if auth enabled).** Show Sign in with Apple (and Google if requested) instead of Continue. If auth is not needed, last page shows a final Continue button.
4. **Sign-in buttons must be consistent.** Don't use `SignInWithAppleButton` — it controls its own font size and height, making it impossible to match other buttons. Instead, build custom buttons for all auth options using the same shared constants (`buttonHeight`, `buttonRadius`), same font (`.system(size: 17, weight: .medium)`), and same structure (`HStack` with icon + text, `frame(maxWidth: .infinity)`, `frame(height:)`, `background()`, `clipShape(RoundedRectangle)`). Apple = black background + `apple.logo` SF Symbol. Google = white background. Dev = blue background.
5. **Inline loading on the tapped button.** When user taps a sign-in button, replace that button's label with a `ProgressView` spinner inside the same button frame — don't change the page layout. Disable all other buttons (`.disabled(isLoading)`). Track which button was tapped with an enum (`SignInSource`). After 1-2s delay, complete onboarding.
6. **Transition to home: crossfade.** When onboarding completes, use `withAnimation(.easeInOut(duration: 0.5))` to toggle the `hasOnboarded` flag. The conditional root view gives you a smooth crossfade — onboarding fades out, home fades in. No abrupt cut.
7. **Persist completion.** Store `hasOnboarded` in `@AppStorage("hasOnboarded")` so it never shows again after completion.

---

## Settings — rules

1. **Profile edit = native Form sheet.** Tap the account row → `.sheet` with a `Form` inside `NavigationStack`. Use native `Section` grouping, native `TextField` (no custom styling). Cancel + Save in toolbar. `.presentationDetents([.large])`.
2. **Avatar = PhotosPicker.** Use `PhotosPicker(selection:matching:.images)` for avatar — user picks from their photo album. Show circular preview with a camera overlay icon. Store image as `Data` (not SF Symbols). Placeholder: `person.circle.fill` in gray.
3. **Subscription = custom animated sheet.** Don't just wrap `SubscriptionStoreView` in a sheet — build a custom paywall with: hero icon with `.symbolEffect(.pulse)`, staggered feature list animations, plan picker cards (monthly/yearly with savings badge), gradient CTA button with inline loading spinner, manage/restore links, and legal text. Use `.presentationDetents([.large])`.
4. **Inline loading on purchase button.** Same pattern as onboarding sign-in: spinner replaces button label, button stays in place, other controls disabled.

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

| Anti-pattern                                  | Why                                                 | Fix                              |
| --------------------------------------------- | --------------------------------------------------- | -------------------------------- |
| `.glassEffect()` on list rows or cards        | Apple explicitly forbids glass on content           | Remove it; content stays flat    |
| Glass on glass                                | "Always avoid glass on glass" — Apple               | One glass layer only             |
| `ObservableObject` + `@Published` in new code | `@Observable` tracks per-property, massive perf win | Migrate to `@Observable`         |
| `LazyVStack` for >50 homogeneous rows         | 10x slower than `List` in benchmarks                | Use `List`                       |
| `withAnimation { Task { await ... } }`        | Animation transaction gone by await                 | `withAnimation` after data lands |
| `@unchecked Sendable` without lock            | Data race waiting to happen                         | Use actor or add documented lock |
| `try!` or force-unwrap on network data        | Crash in production                                 | Proper error handling            |
| `DispatchQueue.main.async` in async code      | Swift 6 anti-pattern                                | `@MainActor` isolation           |
| `.onAppear { Task { } }`                      | No auto-cancellation on disappear                   | `.task { }` modifier             |
| `Data(contentsOf:)` on URL synchronously      | Blocks calling thread                               | `URLSession` async               |
| Onboarding as `.sheet`/`.fullScreenCover`     | Home visible behind it, feels like modal not flow   | Conditional root view            |
| Onboarding page without Continue button       | Users won't discover swipe gesture                  | Always show bottom CTA           |
| `SignInWithAppleButton` mixed with custom btns| Uncontrollable font/height breaks consistency       | Custom button with `apple.logo`  |
| Full-page loading spinner on auth             | Jarring layout shift, hides context                 | Inline spinner inside tapped btn |
| Custom styled text fields in profile edit     | Looks non-native, breaks iOS feel                   | Native `Form` + `TextField`      |
| SF Symbol grid for avatar picker              | Not personal, users want their own photos           | `PhotosPicker` from photo album  |
| Tinting every glass element                   | "When every element is tinted, nothing stands out"  | Tint only primary CTA            |
| Mixing Regular and Clear glass variants       | "They should never be mixed" — Apple                | Pick one per context             |

---

## Project setup — XcodeGen (new projects)

The project must be fully buildable from the command line. No manual Xcode configuration.
Use XcodeGen to generate the `.xcodeproj` from a `project.yml` file.

Read `references/project-setup.md` for the complete `project.yml` template, entitlements,
Info.plist, and directory structure.

**The sequence — follow this exactly for every new project:**

1. Check XcodeGen is installed: `which xcodegen || brew install xcodegen`
2. Create folder structure inside the current project directory:
   `AppName/{Models,DTOs,Services,Protocols,ViewModels,Views,Resources}`
3. Write all Swift source files
4. Write `AppName/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
5. Write `AppName/Resources/AppName.entitlements` (Sign in with Apple, etc.)
6. Write `project.yml` at the project root
7. Run `xcodegen generate` to create the `.xcodeproj`
8. Build the project from the command line and verify it compiles:
   ```bash
   xcodebuild -project AppName.xcodeproj -scheme AppName -sdk iphonesimulator \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1
   ```
9. If the build fails, read the errors, fix them, and rebuild. Repeat until the build succeeds.
   Common issues: missing imports, typos in type names, SwiftData model issues, concurrency errors.
10. Only after a clean build, open with `open AppName.xcodeproj`

**The project is not done until it builds successfully.** Never hand off a project to the user
with compile errors. Always run the build, fix all errors, and confirm a clean build before
telling the user the project is ready.

**Assets.xcassets minimum** — always create this so the project compiles:

```json
// AppName/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
{
  "images": [{"filename": "","idiom": "universal","platform": "ios","size": "1024x1024"}],
  "info": {"author": "xcode", "version": 1}
}

// AppName/Resources/Assets.xcassets/Contents.json
{
  "info": {"author": "xcode", "version": 1}
}

// AppName/Resources/Assets.xcassets/AccentColor.colorset/Contents.json
{
  "colors": [{"idiom": "universal"}],
  "info": {"author": "xcode", "version": 1}
}
```
