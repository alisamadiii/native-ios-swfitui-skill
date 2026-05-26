# Building iOS SaaS Applications with Swift 6, SwiftUI, and iOS 26 Liquid Glass

**A definitive reference for AI-assisted development of social-networking and productivity iOS apps**

Target stack: Swift 6 (strict concurrency on), iOS 26 / iPadOS 26, Xcode 26, SwiftUI with the Liquid Glass design system, SwiftData, StoreKit 2, Sign in with Apple, APNs, BackgroundTasks.

---

## TL;DR (for the AI consumer)

- **Default architecture:** SwiftUI + `@Observable` view models (or a thin "feature/state" object) + structured concurrency + `URLSession` async APIs + SwiftData for local persistence + `Environment` for dependency injection. Reach for TCA only when you have many composable, state-heavy features and a team that knows it.
- **Default UI rule for iOS 26:** Recompile against the iOS 26 SDK and let standard SwiftUI components (NavigationStack, TabView, toolbars, sheets, search) adopt Liquid Glass automatically. Apply `.glassEffect()` only to *floating navigation/control* elements that sit above content — **never** to lists, cards, or content rows. Never stack glass on glass.
- **Default concurrency rule:** Enable Swift 6 language mode + complete strict concurrency. Treat the data layer as actors, treat UI/view-models as `@MainActor`-isolated `@Observable` classes, never use `@unchecked Sendable` without a documented locking strategy.

---

## Key findings

1. **Liquid Glass is a navigation-layer material, not a content material.** WWDC25 session #219 ("Meet Liquid Glass") states verbatim: *"You may be tempted to use Liquid Glass everywhere but it is best reserved for the navigation layer that floats above the content of your app."* Apple also explicitly says *"always avoid glass on glass"* and *"avoid tinting all your elements."* This is the single biggest UI rule that differentiates apps that feel iOS-26-native from apps that look gaudy.
2. **Most of your iOS 26 design upgrade is free.** Recompiling against the iOS 26 SDK with Xcode 26 makes NavigationBar, TabBar, Toolbar, Sheets, Popovers, Menus, Alerts, Search bars, Toggles, Sliders, and Pickers adopt Liquid Glass automatically. Custom glass should be the exception.
3. **`@Observable` (Swift 5.9+) replaces `ObservableObject`** for new code. It tracks per-property reads, so unrelated views stop recomputing when other properties change — this is the single biggest SwiftUI performance win available without architectural changes.
4. **Swift 6's strict concurrency is the new baseline.** Region-based isolation in Swift 6 means most apps need 50–70% fewer `Sendable` annotations than they would have needed under Swift 5.10's complete-checking mode. The remaining work is: actor-ify shared mutable state, mark DTOs `Sendable`, default UI to `@MainActor`.
5. **For new SwiftUI apps, SwiftData is the default — but Core Data still wins for complex cases.** SwiftData got only inheritance + bug fixes at WWDC25 (per session #291 "SwiftData: Dive into inheritance and schema migration"); production teams with shared/public CloudKit needs still fall back to Core Data + CloudKit Sharing.
6. **`List` is dramatically faster than `ScrollView + LazyVStack`** for long homogenous content — Adam Gelatka's STRV benchmark on iPhone 15 Pro / iOS 17.5.1 measured 5.53s vs 52.3s scrolling 1,000 image rows, with 4.6 vs 78 hangs. Don't reach for LazyVStack unless List's layout doesn't fit.
7. **Sign in with Apple is mandatory if you offer any third-party login.** App Store Review Guideline §4.8 verbatim: *"Apps that exclusively use a third-party or social login service (such as Facebook Login, Google Sign-In, Sign in with Twitter, Sign In with LinkedIn, Login with Amazon, or WeChat Login) to set up or authenticate the user's primary account with the app must also offer Sign in with Apple as an equivalent option."*
8. **StoreKit 2 with SwiftUI views (`SubscriptionStoreView`, `StoreView`, `ProductView`) is the modern path.** iOS 26 added `SubscriptionOfferView` for upgrade/downgrade/crossgrade merchandising and extended offer-code support to consumables and non-consumables. The original StoreKit framework was deprecated in iOS 18.

---

## Details

### 1. Animations in SwiftUI (iOS 26)

#### 1.1 The animation toolbox — when to use what

| API | Use it for | Avoid when |
|---|---|---|
| `withAnimation { state = ... }` | Imperative state changes triggered from gestures, buttons, async completions | You're already inside a SwiftUI binding setter that has its own transaction |
| `.animation(_:value:)` | Declarative: "animate whenever this value changes" | You only want animation on a single event — use `withAnimation` instead |
| `.transition(_:)` | View insertion/removal inside an `if`/`ForEach` | The view stays in the tree the whole time — use matched geometry or animatable instead |
| `matchedGeometryEffect(id:in:)` | "Hero" transitions between two distinct view representations of the same logical thing | The element never leaves the hierarchy — use `.animation(_:value:)` |
| `.phaseAnimator(_:content:)` / `PhaseAnimator` (iOS 17+) | Looping or trigger-driven multi-phase animations on a single view | You need per-property timing — use keyframes |
| `KeyframeAnimator` / `.keyframeAnimator` (iOS 17+) | Multi-property choreographed sequences (scale + rotation + opacity at different beats) | The animation is a simple spring |
| `@Animatable` macro (iOS 26) | Custom `Shape`s or views with many animatable properties | You only have one animatable property |

#### 1.2 Liquid Glass animation APIs (iOS 26, new)

- **`GlassEffectContainer { ... }`** groups glass elements so they morph smoothly into each other rather than crossfading. From WWDC25 #323 "Build a SwiftUI app with the new design": *"To combine multiple glass elements, use the GlassEffectContainer. This grouping is essential for visual correctness… glass cannot sample other glass, so having nearby glass elements in different containers will result in inconsistent behavior."*
- **`.glassEffectID(_:in:)`** identifies elements that should morph together inside a container (the glass-equivalent of `matchedGeometryEffect`).
- **`GlassEffectTransition`** with cases `.identity`, `.matchedGeometry` (default), `.materialize`.
- **`@Animatable` macro** auto-synthesizes `AnimatablePair`/`AnimatableData` for shapes; use `@AnimatableIgnored` to skip a stored property. From WWDC25 #256 "What's new in SwiftUI": *"Using the new Animatable macro, I'm able to delete the custom animatable data property and let SwiftUI automatically synthesize it for me."*
- **`.backgroundExtensionEffect()`** mirrors/blurs background content into the safe-area edges so glass toolbars sit over coherent imagery.

#### 1.3 Best practices

```swift
// ✅ GOOD — implicit animation tied to a value
struct LikeButton: View {
    @State private var liked = false
    var body: some View {
        Image(systemName: liked ? "heart.fill" : "heart")
            .scaleEffect(liked ? 1.2 : 1)
            .animation(.snappy, value: liked)   // only re-runs when `liked` changes
            .onTapGesture { liked.toggle() }
    }
}

// ✅ GOOD — phase animator for a multi-step pulse
.phaseAnimator([1.0, 1.15, 1.0]) { content, scale in
    content.scaleEffect(scale)
} animation: { _ in .smooth(duration: 0.4) }

// ✅ GOOD — matched geometry hero transition
@Namespace private var ns
if expanded {
    BigCard().matchedGeometryEffect(id: post.id, in: ns)
} else {
    SmallCard().matchedGeometryEffect(id: post.id, in: ns)
}
```

#### 1.4 Worst practices (anti-patterns that cause jank)

```swift
// ❌ BAD — global withAnimation around a network call
Button("Refresh") {
    withAnimation {
        Task { posts = try await api.fetchPosts() } // animation transaction is gone by the time `posts` updates
    }
}

// ✅ FIX — animate when the value lands
Button("Refresh") {
    Task {
        let new = try await api.fetchPosts()
        withAnimation(.smooth) { posts = new }
    }
}

// ❌ BAD — implicit .animation() with no value (deprecated, animates EVERYTHING)
SomeView().animation(.default)

// ❌ BAD — applying matchedGeometryEffect AFTER a fixed .frame()
Color.red.frame(width: 100, height: 100)
    .matchedGeometryEffect(id: "x", in: ns) // inner frame overrides matched size

// ✅ FIX — put matchedGeometryEffect on the flexible color first
Color.red.matchedGeometryEffect(id: "x", in: ns).frame(width: 100, height: 100)
```

(The matchedGeometry ordering pitfall is documented by Chris Eidhof at chris.eidhof.nl.)

**Other animation worst practices:**
- Animating layout-affecting properties inside a scrolling `List`/`LazyVStack` — the body re-evaluations cascade. Prefer transforms (`scaleEffect`, `rotationEffect`, `offset`) and `drawingGroup()` where appropriate.
- Triggering animations from non-`Equatable` state changes that fire every frame.
- Wrapping huge view subtrees in `withAnimation` — only animate the smallest possible subview.
- Using `Animation.linear(duration: 0)` to "skip" animation instead of `Transaction.disablesAnimations = true` or wrapping the mutation outside `withAnimation`.

#### 1.5 Performance considerations

- iOS animations are GPU-cheap when they're transforms/opacity, expensive when they cause Core Animation commits that re-rasterize content.
- Profile with **Instruments → SwiftUI template** and watch the *View Body*, *View Properties*, and *Core Animation Commits* lanes. If a body re-evaluates on every frame of an animation, you've coupled state too broadly.
- Use the Xcode 15+ animation completion handler (`withAnimation(.smooth) { ... } completion: { ... }`) instead of dispatching with arbitrary delays.

---

### 2. Native UI Components & the Liquid Glass Design System (iOS 26)

#### 2.1 What Liquid Glass actually is

Apple introduced Liquid Glass at WWDC 2025 across iOS 26, iPadOS 26, macOS Tahoe 26, watchOS 26, tvOS 26 and visionOS 26. Apple Newsroom (June 9, 2025): *"It's crafted with a new material called Liquid Glass. This translucent material reflects and refracts its surroundings, while dynamically transforming to help bring greater focus to content."* Apple session #219 calls it *"a new digital meta-material that dynamically bends and shapes light"*; it uses **lensing** (bending light) rather than the traditional **blur** (scattering light).

#### 2.2 The cardinal rule — and Apple says it explicitly

From WWDC25 #219 "Meet Liquid Glass":

> *"You may be tempted to use Liquid Glass everywhere but it is best reserved for the navigation layer that floats above the content of your app."*

And:

> *"Always avoid glass on glass. Stacking Liquid Glass elements on top of each other can quickly make the interface feel cluttered and confusing."*

And on tinting:

> *"Tinting should only be used to bring emphasis to primary elements and actions in the UI… Avoid tinting all your elements. When every element is tinted, nothing stands out."*

And on variants:

> *"There are two to choose from: Regular and Clear. They should never be mixed, as they each have their own characteristics and specific use cases."*

Clear is only permissible when all three conditions hold: (1) the element is over media-rich content, (2) the content layer won't be negatively affected by a dimming layer, (3) the content above is bold and bright.

#### 2.3 Free upgrades — just recompile

When you build against iOS 26 SDK with Xcode 26, these components adopt Liquid Glass automatically:

- `NavigationStack` / `NavigationSplitView` bars
- `TabView` (now inset, capsule-shaped, with morphing)
- `.toolbar` items
- Sheets, popovers, menus, alerts
- `.searchable` search field
- Toggles, sliders, pickers (during interaction)

```swift
// ✅ GOOD — get Liquid Glass for free
NavigationStack {
    List(items) { item in Row(item: item) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { ... }
            }
        }
}
```

#### 2.4 Custom glass — the right way

```swift
// ✅ GOOD — floating action button on the navigation layer
ZStack(alignment: .bottomTrailing) {
    List(items) { Row(item: $0) }   // content layer stays flat
    Button(action: compose) { Label("New Post", systemImage: "square.and.pencil") }
        .padding()
        .glassEffect(.regular.interactive())  // floats over content
        .padding()
}

// ✅ GOOD — morphing group of glass buttons
@Namespace private var ns
GlassEffectContainer(spacing: 16) {
    HStack {
        Button("Like")    { }.glassEffect().glassEffectID("like", in: ns)
        Button("Comment") { }.glassEffect().glassEffectID("comment", in: ns)
        if showShare {
            Button("Share") { }.glassEffect().glassEffectID("share", in: ns)
        }
    }
}
```

#### 2.5 Worst practices for Liquid Glass

```swift
// ❌ BAD — applying glass to a content row
List {
    ForEach(posts) { post in
        PostRow(post: post).glassEffect()  // violates Apple's content-vs-navigation rule
    }
}

// ❌ BAD — glass on glass
.glassEffect().padding().background(.regularMaterial).glassEffect()

// ❌ BAD — tinting every control
.glassEffect(.regular.tint(.purple))   // on every button — destroys hierarchy

// ❌ BAD — putting two adjacent glass elements in different containers (they sample inconsistently)
HStack {
    GlassEffectContainer { Button("A"){}.glassEffect() }
    GlassEffectContainer { Button("B"){}.glassEffect() }
}
// ✅ FIX — one container holds both
GlassEffectContainer { HStack { Button("A"){}.glassEffect(); Button("B"){}.glassEffect() } }
```

#### 2.6 New SwiftUI iOS 26 component APIs you should know

- **New `Tab` initializer with roles**, including `Tab("Search", systemImage: "magnifyingglass", role: .search) { SearchView() }` — renders as a separate "search island" capsule in the tab bar.
- **`.tabBarMinimizeBehavior(.onScrollDown)`** — tab bar collapses on scroll and re-expands on scroll-up.
- **`.tabViewBottomAccessory { ... }`** — for Now-Playing-style mini bars over the tab bar.
- **`.searchToolbarBehavior(.minimize)`** — collapses search into a button when search isn't the primary task.
- **`ToolbarSpacer(.fixed)` / `ToolbarSpacer(.flexible)`** — splits toolbar items into groups that morph independently during transitions.
- **`.navigationSubtitle(_:)`**, **`.listSectionMargins(_:_:)`**, **`.backgroundExtensionEffect()`**.
- **`.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`** — bring Liquid Glass to any button.
- **`#Playground` macro** in Xcode 26 for inline Swift playgrounds.

#### 2.7 Apple HIG principles for iOS 26

The iOS 26 HIG re-states three principles: **Hierarchy**, **Harmony**, **Consistency**.

- *Hierarchy:* "Establish a clear visual hierarchy where controls and interface elements elevate and distinguish the content beneath them."
- *Harmony:* "Align with the concentric design of the hardware and software to create harmony between interface elements, system experiences, and devices."
- *Consistency:* "Adopt platform conventions to maintain a consistent design that continuously adapts across window sizes and displays."

Accessibility: Liquid Glass respects **Reduce Transparency** (frostier glass), **Increase Contrast** (predominantly black/white with contrast borders), and **Reduce Motion** (disables elastic morph). From session #219: *"These are available automatically whenever you use the new material."* Never force-disable them.

#### 2.8 When to use native vs custom

Native first. The HIG and Apple developer docs are explicit: most apps need **only** to recompile to get the new design. Build a custom view *only* when:

1. There's no native equivalent (e.g., a custom drawing/canvas).
2. Brand identity requires it AND the native control can't be styled enough.
3. The interaction model is genuinely novel.

Otherwise, customizing native components (e.g., `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, `.toolbarRole`, `.containerBackground`) is preferable to reimplementing them.

---

### 3. Data Fetching & Networking

#### 3.1 The default: `URLSession` async/await

```swift
// ✅ GOOD — a thin, testable, generic client
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

actor APIClient: HTTPClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode) }
        return (data, http)
    }
}

struct Endpoint<Response: Decodable & Sendable>: Sendable {
    let path: String
    let method: String
    let body: Data?
}

extension APIClient {
    func send<R>(_ endpoint: Endpoint<R>) async throws -> R {
        var req = URLRequest(url: URL(string: "https://api.example.com" + endpoint.path)!)
        req.httpMethod = endpoint.method
        req.httpBody = endpoint.body
        let (data, _) = try await data(for: req)
        return try JSONDecoder().decode(R.self, from: data)
    }
}
```

#### 3.2 Auth tokens — use an actor

A common bug is multiple concurrent requests each triggering a refresh. An `actor AuthManager` with a single in-flight `Task<Tokens, Error>` solves this — at most one refresh runs at a time, every other caller `await`s it (Mark Kazakov, "Modern Networking in iOS with URLSession and async/await – Part 2," DEV community: *"When multiple network requests need a valid token simultaneously, we must avoid refreshing the token more than once at the same time. Using a Swift actor ensures that only one refresh call happens concurrently."*).

#### 3.3 Persistence: SwiftData vs Core Data vs SQLite

| Need | Pick |
|---|---|
| New project, iOS 17+, SwiftUI, simple-to-moderate graph, want minimal boilerplate | **SwiftData** |
| Public CloudKit, complex migrations, multi-process access, very large datasets, existing Core Data investment | **Core Data** |
| Need full SQL control / cross-platform with Android | **GRDB.swift** or raw SQLite |

WWDC 2025 added only model inheritance to SwiftData (per session #291 "SwiftData: Dive into inheritance and schema migration") plus two small fixes: a bug preventing view updates when mutating data under `@ModelActor`, and the ability to use `Codable`-conforming properties in predicates (both backwards-compatible to iOS 17). No Core Data updates were announced. The current advice from many production users (reported on Michael Tsai's blog, October 2025): SwiftData is now viable for many real apps in Xcode 26, but "serious" use cases involving sharing/public CloudKit still tend to fall back to Core Data + CloudKit + Sharing. Hybrid use is possible but requires architecting two layers.

```swift
// ✅ GOOD — SwiftData model
@Model final class Post {
    @Attribute(.unique) var id: UUID
    var body: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var comments: [Comment] = []
    init(id: UUID = .init(), body: String, createdAt: Date = .now) {
        self.id = id; self.body = body; self.createdAt = createdAt
    }
}

// In your App:
.modelContainer(for: Post.self)
```

#### 3.4 Caching strategies

- **HTTP cache:** for read-heavy endpoints, configure `URLCache` (e.g., 10 MB memory / 50 MB disk) and use `URLRequest.cachePolicy = .useProtocolCachePolicy`. Respect server `Cache-Control`/`ETag`.
- **Offline-first:** persist canonical models in SwiftData; treat the network as a sync source. Pattern: read from SwiftData → fire async refresh → write back.
- **Image cache:** use `NukeUI` (third-party) or `AsyncImage` for prototypes; for production social feeds prefer Nuke/Kingfisher with disk LRU.
- **In-memory micro-cache:** an `actor` with a `[Key: Value]` dict and TTL is enough for many SaaS feeds.

#### 3.5 Error handling patterns

```swift
enum APIError: Error, Sendable {
    case invalidResponse
    case status(Int)
    case decoding(any Error)
    case offline
    case unauthorized
}
```

Surface errors to UI via an `@Observable` view-model state machine:

```swift
enum ViewState<T: Sendable>: Sendable {
    case idle, loading, loaded(T), failed(APIError)
}
```

Never `try!` network calls; never force-unwrap optional headers/JSON; never silently swallow errors in a `Task { try? ... }` without logging.

#### 3.6 Worst practices

- Calling `Data(contentsOf:)` on a URL synchronously — blocks the thread (main if called from MainActor).
- Using `.shared` everywhere with no configurability — kills testability.
- Force-unwrapping `URL(string:)` in production code.
- Ignoring Swift 6 sendability warnings on response models — make every DTO `Sendable`.
- Hand-rolling Combine pipelines for sequential requests when `async/await` is shorter and Swift 6-friendlier.

---

### 4. Swift 6 Strict Concurrency

#### 4.1 Sendable conformance

- Value types with `Sendable` stored properties are implicitly `Sendable`.
- Classes need `final` + immutable state, **or** an actor, **or** `@unchecked Sendable` with documented synchronization.
- DTOs, endpoints, errors, and any type that crosses an isolation boundary must be `Sendable`.

```swift
// ✅ GOOD
struct User: Sendable, Codable { let id: UUID; let name: String }

// ✅ GOOD — actor for mutable shared state
actor ImageCache {
    private var store: [URL: Data] = [:]
    func image(for url: URL) -> Data? { store[url] }
    func insert(_ data: Data, for url: URL) { store[url] = data }
}

// ⚠️ ACCEPTABLE WITH DOC — unchecked with a real lock
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}
```

#### 4.2 Actor isolation

- One actor = one serial execution context. Calls from outside become `await`.
- Reach for `nonisolated` on members that don't touch mutable state and need to be callable synchronously.
- Use **`@MainActor`** on view models and any code that touches UIKit/SwiftUI state. With Swift 6.2's "Approachable Concurrency," many small apps can default to MainActor-isolation everywhere and only break out to background actors when profiling demands it (per Antoine van der Lee, "Approachable Concurrency in Swift 6.2," avanderlee.com).

#### 4.3 Region-based isolation (Swift 6)

Swift 6 introduces *region-based isolation*: the compiler tracks which values flow between isolation domains and only complains when a real race is possible. Practical effect: many "non-Sendable" warnings from the Swift 5.10 era disappear. Per Fora Soft's Swift 6 migration writeup ("Swift 6 Explained," forasoft.com): *"In a typical app migration, region-based isolation cuts the number of Sendable annotations you need to add by 50–70%."*

#### 4.4 Common worst practices

```swift
// ❌ BAD — silencing concurrency with @unchecked Sendable on a mutable class
final class UserCache: @unchecked Sendable {
    var users: [User] = []   // RACY — no lock, no actor
}

// ❌ BAD — DispatchQueue.main.async hop from inside an async function
func load() async {
    let data = try? await api.fetch()
    DispatchQueue.main.async { self.data = data }  // use @MainActor instead
}

// ❌ BAD — `Task { @MainActor in ... }` inside a SwiftUI view body
var body: some View {
    Text(label).onAppear {
        Task { @MainActor in ... }    // use `.task { ... }` which auto-cancels on disappear
    }
}

// ❌ BAD — capturing `self` strongly in an unbounded Task
class FeedVM {
    func start() {
        Task {
            while true { await self.poll() }   // never cancelled
        }
    }
}
// ✅ FIX — store the task, cancel on deinit; or use `.task(id:)` in the view
```

#### 4.5 Migration playbook (production-tested phases, from Fora Soft)

1. **Phase 1:** Build on Swift 5.10 with `SWIFT_STRICT_CONCURRENCY=complete` as warnings. Track warnings burn-down in CI.
2. **Phase 2:** Replace global mutable singletons with actors or `@MainActor` types.
3. **Phase 3:** Add `Sendable`/`sending` annotations on library boundaries.
4. **Phase 4:** Flip `-swift-version 6`. With warnings at zero, this is a quiet day.

---

### 5. Architecture Patterns

#### 5.1 Default: SwiftUI + `@Observable` + lightweight services

```swift
// ✅ GOOD — Observable view model, MainActor isolated
@MainActor
@Observable
final class FeedViewModel {
    private(set) var state: ViewState<[Post]> = .idle
    private let api: any FeedServicing

    init(api: any FeedServicing) { self.api = api }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await api.fetchPosts())
        } catch {
            state = .failed(error as? APIError ?? .invalidResponse)
        }
    }
}

// Wire up via init injection or environment:
struct FeedView: View {
    @State private var vm: FeedViewModel
    init(api: any FeedServicing) { _vm = State(wrappedValue: FeedViewModel(api: api)) }
    var body: some View {
        List { /* … */ }
            .task { await vm.load() }
    }
}
```

`@Observable` replaces `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`. SwiftUI now tracks **per-property** reads, so unrelated views stop recomputing when other properties change — a major performance win, especially for lists. Antoine van der Lee documents the speedup; Donny Wals explains the SwiftUI redraw model.

#### 5.2 When to use TCA (The Composable Architecture)

Use TCA if **all** of these are true:

- The app has many composable features and you want a single, enforced unidirectional flow.
- The team is comfortable with reducers, effects, and dependency keys.
- You want exhaustive testable state machines (TestStore is excellent).

TCA cons reported by teams who migrated away (Aleksa Simić, themobilekit.com; Rod Schmidt, rodschmidt.com): steeper onboarding for juniors, heavier compile times, more boilerplate, and pressure to "fight SwiftUI's defaults." Many large teams in 2025 land on **MVVM + Clean Architecture** with modular Swift packages instead.

#### 5.3 Dependency Injection — pick one of three

| Approach | When |
|---|---|
| **Initializer injection** | Default for view models — explicit, testable. |
| **`@Environment` with custom keys** | Cross-cutting concerns (theming, services, current user). |
| **Third-party (Swinject / swift-dependencies)** | Deep graphs, many features, factory needs. |

```swift
// ✅ Initializer-based
final class ProfileViewModel { let api: any UserServicing; init(api: any UserServicing) { self.api = api } }

// ✅ Environment-based
private struct AnalyticsKey: EnvironmentKey { static let defaultValue: any AnalyticsService = NoopAnalytics() }
extension EnvironmentValues { var analytics: any AnalyticsService {
    get { self[AnalyticsKey.self] } set { self[AnalyticsKey.self] = newValue } } }
```

**Worst:** singletons everywhere (`AnalyticsService.shared` referenced inside every view), implicitly-unwrapped DI properties (crash on missing inject), or DI containers shoved into every view.

#### 5.4 State management worst practices

- One mega-view model holding 30+ properties — splits view body re-renders into broad re-evaluations even with `@Observable`. Break by feature.
- Storing derived data as `@Published`/observable instead of computing it.
- `@State` on a reference type without `@Observable` — won't update the view.
- `@StateObject` is now legacy (`ObservableObject` only); use `@State` to own an `@Observable` instance, `@Bindable` to derive bindings.

---

### 6. Performance & Optimization

#### 6.1 Lists — measured guidance

For long, homogenous, cell-shaped data, **`List`** wins decisively. Adam Gelatka's STRV benchmark ("SwiftUI: List vs LazyVStack," strv.com), tested on iPhone 15 Pro / iOS 17.5.1 scrolling 1,000 high-resolution image rows: *"Scrolling to the bottom took 5.53 seconds with the List, whereas LazyVStack took a staggering 52.3 seconds… List experienced 4.6 hangs, while LazyVStack logged 78."* `List` recycles cells like `UITableView`; `LazyVStack` instantiates and retains views as the user scrolls.

- Use `LazyVStack` only when you need layout flexibility `List` can't give you, or when datasets are small.
- Avoid the `.id()` modifier on `List` children — it disables lazy loading. (`LazyVStack` is unaffected.)
- Ensure rows conform to `Identifiable` with a *stable* ID. Unstable IDs cause unnecessary recreation, lost scroll position, and broken animations.

```swift
// ✅ GOOD
List(posts) { post in PostRow(post: post) }    // post: Identifiable, stable id

// ❌ BAD
List(posts.indices, id: \.self) { i in PostRow(post: posts[i]) }  // unstable identity
```

#### 6.2 View identity and equatability

- Wrap pure subviews in `EquatableView` or use `.equatable()` when you control their inputs and they're expensive to recompute.
- Don't pass large structs through bindings unnecessarily — bindings invalidate broadly.
- Don't put `let _ = print(...)` in `body` and ship it.

#### 6.3 Massive view bodies — refactor by composition

Per John Sundell's "Avoiding massive SwiftUI views" (swiftbysundell.com): extract reusable components (`InfoView`, `PostRow`), group repeating modifiers into `extension Image { func asThumbnail() }`, and use factory objects to build destination screens so the parent view doesn't carry the cognitive load.

#### 6.4 Instruments

Use the **SwiftUI** Instruments template. Key lanes (per Donny Wals, donnywals.com/using-instruments-to-profile-a-swiftui-app):

- **View Body** — counts body re-evaluations. If a view re-evaluates unexpectedly, you've coupled it to state it doesn't need.
- **View Properties** — what state was tracked.
- **Core Animation Commits** — GPU work per redraw.
- **Time Profiler** — per-function time; great for finding slow `body` computations.

Always profile on a **device**, not the simulator.

#### 6.5 Memory management

- Cancel `Task`s on view disappear (use `.task { ... }` — auto-cancels — instead of `.onAppear { Task { ... } }`).
- Watch for closure captures of `self` in long-lived Tasks; mark `[weak self]` where appropriate.
- For Combine holdouts: store cancellables in a single `Set<AnyCancellable>` that's released with the view-model.

---

### 7. SaaS-specific concerns

#### 7.1 Authentication

**Sign in with Apple is mandatory** if your app exclusively uses any third-party social login. App Store Review Guideline §4.8 verbatim: *"Apps that exclusively use a third-party or social login service (such as Facebook Login, Google Sign-In, Sign in with Twitter, Sign In with LinkedIn, Login with Amazon, or WeChat Login) to set up or authenticate the user's primary account with the app must also offer Sign in with Apple as an equivalent option."*

Use the native SwiftUI button:

```swift
import AuthenticationServices

SignInWithAppleButton(.signIn) { request in
    request.requestedScopes = [.fullName, .email]
    request.nonce = sha256(currentNonce)   // generate a per-request nonce
} onCompletion: { result in
    switch result {
    case .success(let auth):
        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        // Send cred.identityToken + currentNonce to your backend; verify the JWT (sub == account_id, aud == bundle ID).
    case .failure(let error):
        // Log & surface
    }
}
.signInWithAppleButtonStyle(.black)
.frame(height: 50)
```

Key gotchas:

- Apple sends `fullName`/`email` **only on first sign-in**. Persist them server-side immediately or you lose them.
- Subsequent logins may return an Apple **private-relay email** that can change. Treat `sub` (account_id) as the immutable primary key, not the email.
- Always verify the identity token server-side (verify signature against Apple's JWKS, check `iss`, `aud` matches your bundle ID, `exp`).
- Use a cryptographically random nonce (`SecRandomCopyBytes`) hashed with SHA-256.

For OAuth (Google, GitHub, etc.), prefer `ASWebAuthenticationSession` over an embedded webview — Apple requires it for many flows and it gives the user the Apple-trusted "Sign In" sheet.

#### 7.2 Real-time data (social/productivity)

- **WebSockets:** `URLSessionWebSocketTask` works but is low-level. For production, third-party SDKs (Pusher, Ably, Firestore listeners, Supabase Realtime) handle reconnection + presence.
- **CloudKit subscriptions / SwiftData sync:** great for user-private data; not great for many-to-many social graphs.
- **Push as transport:** silent push (`content-available: 1`) is rate-limited by APNs and not guaranteed; never rely on it for must-deliver UI updates.
- Use an **actor** for the WebSocket connection, expose an `AsyncStream<Event>` to the UI.

#### 7.3 Push notifications (APNs)

- Use **APNs token-based authentication** (a `.p8` key — only two per Apple account), never the older certificate-based flow.
- Add Push Notifications capability + Background Modes (Remote notifications) + a Notification Service Extension for rich content.
- Request permission contextually — *after* the user has seen value, not on first launch.
- Provide deep-link routing from notification payload (`userInfo`) into your `NavigationStack` path on tap.
- Set `apns-priority: 10` for user-visible, `5` for background.
- Per Apple's "Creating the Remote Notification Payload" guide: *"For regular remote notifications, the maximum size is 4KB (4096 bytes)."* Use a Notification Service Extension to download attachments by URL rather than embedding them.

#### 7.4 In-app purchases & subscriptions (StoreKit 2)

- Use the SwiftUI-native StoreKit views: `SubscriptionStoreView(groupID:)`, `StoreView(ids:)`, `ProductView(id:)`. They handle products, prices, localization, restore, and purchase.
- Listen to entitlement updates with `for await update in Transaction.updates { ... }` to grant/revoke access in near real-time; verify with `update.payloadValue` (StoreKit 2 auto-verifies the JWS).
- Use `subscriptionStatusTask(for:)` to react to subscription status changes inside views.
- iOS 26 added **`SubscriptionOfferView`** for merchandising upgrade/downgrade/crossgrade offers and expanded **offer codes to consumables and non-consumables**.
- Use a **`.storekit` configuration file** for local testing without hitting App Store Connect — fastest iteration loop.
- For server-side validation, enable **App Store Server Notifications V2** so you get refunds, billing issues, and renewals as soon as Apple knows. RevenueCat's "iOS In-App Subscription Tutorial with StoreKit 2 and Swift" calls this out: *"Enabling App Store Server Notifications is the best practice and the most efficient way of keeping subscription status and refunded transactions up to date."*
- Consider RevenueCat or Glassfy as managed entitlement backends — they remove most of the server-side StoreKit work.

```swift
// ✅ GOOD — minimal paywall
SubscriptionStoreView(groupID: "598392E1") {
    VStack {
        Image(systemName: "star.fill").font(.system(size: 48))
        Text("Unlock Pro").font(.title.bold())
    }
}
.subscriptionStoreControlStyle(.buttons)
.storeButton(.visible, for: .restorePurchases)
```

#### 7.5 Background tasks

Use the SwiftUI lifecycle:

```swift
@main
struct MyApp: App {
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup { ContentView() }
            .backgroundTask(.appRefresh("com.example.feed.refresh")) {
                await FeedSyncer.shared.refresh()
            }
            .onChange(of: phase) { _, newPhase in
                if newPhase == .background { scheduleRefresh() }
            }
    }

    func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: "com.example.feed.refresh")
        req.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
```

Also register the identifier in Info.plist under `BGTaskSchedulerPermittedIdentifiers`. Per Apple's BackgroundTasks documentation for `BGAppRefreshTaskRequest`, the system grants up to 30 seconds of execution time per launch — exceed it and the system throttles future runs. Use `URLSessionConfiguration.background(withIdentifier:)` for long downloads so the system can wake your app when the transfer completes.

---

## Recommendations

### For starting a new iOS-only SaaS app today

1. **Project setup (day 1):** Xcode 26, iOS 26 deployment target, Swift 6 language mode, complete strict concurrency. Sign the project for Push Notifications, Sign in with Apple, and Background Modes (App Refresh + Background Fetch + Remote Notifications) up front.
2. **Architecture (week 1):** SwiftUI views + one `@MainActor @Observable` view model per screen. Services as `actor`s behind protocols. Inject via initializer for screen-local services, via `@Environment` for cross-cutting (auth, analytics, current user). Skip TCA unless your team has shipped TCA before.
3. **Persistence (week 1):** SwiftData for new data. If you need shared/public CloudKit, plan Core Data + CloudKit Sharing from the start instead — migrating later is painful.
4. **Networking (week 1):** One `APIClient` actor, `Endpoint<R: Decodable & Sendable>`, an `AuthManager` actor with single-flight refresh. No third-party HTTP libraries — `URLSession` is sufficient.
5. **UI (ongoing):** Build with native components. Don't apply `.glassEffect()` anywhere until you've verified the layout works with the automatic Liquid Glass. When you do, only on floating controls, inside a `GlassEffectContainer`, never tinted unless it's a primary CTA.
6. **Monetization (before public beta):** StoreKit 2 with `SubscriptionStoreView`. Use a `.storekit` config from day one. Enable App Store Server Notifications V2 the day you create your first product.
7. **Auth (before public beta):** Sign in with Apple as the primary path; OAuth via `ASWebAuthenticationSession` if needed. Verify identity tokens server-side.

### Thresholds that change these defaults

| Trigger | Action |
|---|---|
| You have >5 features that all manipulate global state, and >3 senior engineers | Evaluate TCA seriously |
| Your social graph needs shared/public CloudKit records | Choose Core Data + CloudKit Sharing over SwiftData |
| Instruments shows >10% of frames dropped in scrolling lists | Replace `LazyVStack` with `List`, verify `Identifiable` IDs are stable |
| You need >30 seconds of background work | Switch from `BGAppRefreshTask` to `BGProcessingTask` and/or background `URLSession` |
| You're shipping to iOS 17/18 as well | Use Point-Free's `Perception` library to backport `@Observable` |
| You're hitting StoreKit edge cases (refunds, billing issues, win-back) | Adopt RevenueCat or Glassfy rather than building entitlement infra |

---

## Caveats

- **Liquid Glass is brand-new.** Some third-party "best practices" articles cited here describe APIs from beta builds; verify exact signatures against `developer.apple.com/documentation/swiftui` for the Xcode 26 release.
- **SwiftData maturity is debated.** Multiple production engineers (reported on Michael Tsai's blog, October 2025) report falling back to Core Data + CloudKit Sharing for non-trivial use cases. If your social network needs shared/public records, plan for Core Data.
- **TCA is polarizing.** It is the most powerful architecture in the Swift ecosystem and the most controversial — Lazar Otasevic on Medium ("TCA in SwiftUI: The Composable Architecture or just The Complicated Antipattern?") argues it reinvents what SwiftUI already does well, while Aleksa Simić ("MVVM vs TCA") praises it but reports migration pain. Default to MVVM unless the team explicitly chooses TCA.
- **The STRV `List` vs `LazyVStack` benchmark** is workload-specific (1,000 high-resolution image rows on iPhone 15 Pro / iOS 17.5.1). For simpler row content the gap narrows; always measure your own workload.
- **WWDC25 session quotes** above (e.g., "best reserved for the navigation layer," "always avoid glass on glass") are verbatim from Apple's official session transcripts (#219, #256, #323, #356) at `developer.apple.com/videos`. They are the authoritative source even if some developer-blog interpretations conflict.
- **`@unchecked Sendable`** is a foot-gun — every use must be paired with a documented synchronization mechanism (a lock, a queue, immutability). The compiler trusts you; reviewers should not.
- **Sign in with Apple §4.8** applies only to apps that *exclusively* use third-party social login as the primary auth — apps that support email+password (or other "first-party" account creation) alongside third-party login are technically exempt, but offering it anyway is good UX.