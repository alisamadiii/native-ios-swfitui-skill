# iOS 26 Liquid Glass Design System Reference

## Table of Contents
1. What you get for free
2. Custom glass — when and how
3. GlassEffectContainer grouping
4. Tab bar APIs
5. Toolbar organization
6. Tinting rules
7. Component catalog
8. Accessibility

---

## 1. What you get for free (just recompile against iOS 26 SDK)

These adopt Liquid Glass automatically — no code changes:
- `NavigationStack` / `NavigationSplitView` bars
- `TabView` (inset, capsule-shaped, morphing)
- `.toolbar` items
- Sheets, popovers, menus, alerts
- `.searchable` search field
- Toggles, sliders, pickers (during interaction)

```swift
// This is all you need — glass nav bar and toolbar are free
NavigationStack {
    List(items) { item in
        Row(item: item)
    }
    .navigationTitle("Feed")
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Add", systemImage: "plus") { showCompose = true }
        }
    }
}
```

## 2. Custom glass — when and how

Apply `.glassEffect()` ONLY to floating navigation/control elements that sit above content:
- Floating action buttons (FABs)
- Custom floating toolbars
- Floating mini-players or status bars
- Action button groups that hover over content

```swift
// CORRECT — floating action button on navigation layer
ZStack(alignment: .bottomTrailing) {
    List(items) { Row(item: $0) }  // content layer stays flat

    Button(action: compose) {
        Label("New Post", systemImage: "square.and.pencil")
    }
    .padding()
    .glassEffect(.regular.interactive())
    .padding()
}

// CORRECT — floating mini-player above tab bar
TabView {
    // tabs...
}
.tabViewBottomAccessory {
    NowPlayingBar()
        .glassEffect(.regular)
}
```

**Never apply glass to:**
- List rows or cells
- Card views
- Content containers
- Backgrounds
- Another glass element (no glass on glass)

## 3. GlassEffectContainer grouping

When multiple glass elements are near each other, wrap them in ONE `GlassEffectContainer`.
This ensures they morph smoothly and sample the background consistently.

```swift
// CORRECT — one container for adjacent glass elements
@Namespace private var ns

GlassEffectContainer(spacing: 16) {
    HStack {
        Button("Like") { }
            .glassEffect()
            .glassEffectID("like", in: ns)
        Button("Comment") { }
            .glassEffect()
            .glassEffectID("comment", in: ns)
        if showShare {
            Button("Share") { }
                .glassEffect()
                .glassEffectID("share", in: ns)
        }
    }
}

// WRONG — separate containers for adjacent elements
HStack {
    GlassEffectContainer { Button("A") { }.glassEffect() }
    GlassEffectContainer { Button("B") { }.glassEffect() }  // inconsistent sampling
}
```

`glassEffectID(_:in:)` is the glass equivalent of `matchedGeometryEffect` — use it for elements
that should morph into each other when they appear/disappear.

## 4. Tab bar APIs (iOS 26)

```swift
TabView {
    Tab("Home", systemImage: "house") {
        HomeView()
    }

    Tab("Explore", systemImage: "compass") {
        ExploreView()
    }

    // Search gets its own "island" capsule in the tab bar
    Tab("Search", systemImage: "magnifyingglass", role: .search) {
        SearchView()
    }

    Tab("Profile", systemImage: "person") {
        ProfileView()
    }
}
// Collapse tab bar on scroll down, re-expand on scroll up
.tabBarMinimizeBehavior(.onScrollDown)
// Mini-bar above the tab bar (Now Playing style)
.tabViewBottomAccessory {
    MiniPlayerView()
}
```

## 5. Toolbar organization

```swift
.toolbar {
    // Groups separated by spacers morph independently during transitions
    ToolbarItem(placement: .topBarLeading) {
        Button("Menu", systemImage: "line.3.horizontal") { }
    }

    ToolbarSpacer(.flexible)  // pushes next items to the right

    ToolbarItem(placement: .topBarTrailing) {
        Button("Filter", systemImage: "line.3.horizontal.decrease") { }
    }

    ToolbarItem(placement: .topBarTrailing) {
        Button("Add", systemImage: "plus") { }
    }
}

// Collapse search into a button when it's not the primary task
.searchToolbarBehavior(.minimize)

// Subtitle under the navigation title
.navigationSubtitle("42 items")
```

## 6. Tinting rules

Tinting brings emphasis to primary elements. Use it sparingly — when everything is tinted,
nothing stands out.

```swift
// CORRECT — tint only the primary CTA
Button("Subscribe") { }
    .glassEffect(.regular.tint(.blue))  // primary action stands out

Button("Maybe Later") { }
    .glassEffect(.regular)  // secondary action, no tint

// WRONG — tinting everything
ForEach(actions) { action in
    Button(action.title) { }
        .glassEffect(.regular.tint(.purple))  // destroys hierarchy
}
```

## 7. Component catalog — reach for native first

| Need | Native component | Custom needed? |
|---|---|---|
| Navigation | `NavigationStack` / `NavigationSplitView` | No |
| Tabs | `TabView` with `Tab` | No |
| Lists | `List` | No, unless layout doesn't fit |
| Search | `.searchable(text:)` | No |
| Toolbar buttons | `.toolbar { ToolbarItem }` | No |
| Sheets | `.sheet(isPresented:)` | No |
| Alerts | `.alert(_:isPresented:)` | No |
| Menus | `Menu` | No |
| Toggles | `Toggle` | No |
| Sliders | `Slider` | No |
| Pickers | `Picker` | No |
| Date pickers | `DatePicker` | No |
| Glass buttons | `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` | No |
| Paywall | `SubscriptionStoreView` | No |
| Product display | `StoreView` / `ProductView` | No |
| Sign in with Apple | `SignInWithAppleButton` | No |
| Custom floating control | `.glassEffect()` on your view | Yes — only on nav layer |
| Canvas/drawing | `Canvas` / custom `Shape` | Yes |

## 8. Accessibility

Liquid Glass automatically respects these accessibility settings — never override them:

- **Reduce Transparency** — glass becomes frostier, more opaque
- **Increase Contrast** — predominantly black/white with contrast borders
- **Reduce Motion** — disables elastic morph animations

These adaptations happen automatically when you use `.glassEffect()` and standard components.
Do not force-disable them or add conditional logic to work around them.

### Glass variants

Two variants exist: **Regular** and **Clear**. Never mix them.

**Clear** is only allowed when ALL three conditions hold:
1. The element is over media-rich content
2. The content layer won't be negatively affected by a dimming layer
3. The content above is bold and bright

Default to Regular. Use Clear only for media-centric screens (photo viewer, video player).

### Background extension

Use `.backgroundExtensionEffect()` to mirror/blur background content into safe-area edges,
so glass toolbars sit over coherent imagery instead of a hard edge.
