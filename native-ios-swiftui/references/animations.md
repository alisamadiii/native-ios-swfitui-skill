# Animations Reference — SwiftUI + iOS 26

## Table of Contents

1. Animation toolbox — when to use what
2. Liquid Glass animation APIs
3. Best practice patterns
4. Anti-patterns that cause jank
5. Performance rules

---

## 1. Animation toolbox

| API                             | Use for                                                            | Avoid when                                           |
| ------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------- |
| `withAnimation { state = ... }` | Imperative state changes from gestures, buttons, async completions | Inside a binding setter that has its own transaction |
| `.animation(_:value:)`          | Declarative: "animate whenever this value changes"                 | You only want animation on a single event            |
| `.transition(_:)`               | View insertion/removal inside `if`/`ForEach`                       | View stays in the tree — use matched geometry        |
| `matchedGeometryEffect(id:in:)` | Hero transitions between two view representations of same thing    | Element never leaves hierarchy                       |
| `.phaseAnimator(_:content:)`    | Looping or trigger-driven multi-phase animations                   | Need per-property timing — use keyframes             |
| `KeyframeAnimator`              | Multi-property choreographed sequences                             | Animation is a simple spring                         |
| `@Animatable` macro (iOS 26)    | Custom shapes with many animatable properties                      | Only one animatable property                         |

## 2. Liquid Glass animation APIs (iOS 26)

### GlassEffectContainer

Groups glass elements so they morph smoothly into each other. Essential for visual correctness —
glass cannot sample other glass, so nearby glass elements in different containers look inconsistent.

```swift
@Namespace private var ns

GlassEffectContainer(spacing: 16) {
    HStack {
        ForEach(tabs) { tab in
            Button(tab.title) { selected = tab }
                .glassEffect()
                .glassEffectID(tab.id, in: ns)  // morphs between tabs
        }
    }
}
```

### GlassEffectTransition

Controls how glass elements appear/disappear:

- `.identity` — no transition effect
- `.matchedGeometry` (default) — morphs between positions
- `.materialize` — glass "materializes" in/out

### backgroundExtensionEffect

Mirrors/blurs background content into safe-area edges so glass toolbars sit over coherent imagery.

```swift
.toolbar {
    ToolbarItem(placement: .bottomBar) {
        HStack { /* controls */ }
    }
}
.backgroundExtensionEffect()  // coherent blur behind bottom toolbar
```

## 3. Best practice patterns

### Simple state-driven animation

```swift
struct LikeButton: View {
    @State private var liked = false

    var body: some View {
        Image(systemName: liked ? "heart.fill" : "heart")
            .foregroundStyle(liked ? .red : .secondary)
            .scaleEffect(liked ? 1.2 : 1)
            .animation(.snappy, value: liked)
            .onTapGesture { liked.toggle() }
    }
}
```

### Animate after async data arrives

```swift
func refresh() async {
    let newPosts = try? await api.fetchPosts()
    if let newPosts {
        withAnimation(.smooth) {
            posts = newPosts  // animation wraps the STATE CHANGE, not the fetch
        }
    }
}
```

### Multi-step pulse with PhaseAnimator

```swift
.phaseAnimator([1.0, 1.15, 1.0]) { content, scale in
    content.scaleEffect(scale)
} animation: { _ in .smooth(duration: 0.4) }
```

### Hero transition with matchedGeometryEffect

```swift
@Namespace private var heroNS

if expanded {
    ExpandedCard(post: post)
        .matchedGeometryEffect(id: post.id, in: heroNS)
} else {
    CompactCard(post: post)
        .matchedGeometryEffect(id: post.id, in: heroNS)
}
```

**Ordering matters:** put `matchedGeometryEffect` BEFORE `.frame()`, not after. If `.frame()` comes
first, it overrides the matched size.

### Animation completion handler (iOS 17+)

```swift
withAnimation(.smooth) {
    showConfirmation = true
} completion: {
    // Runs after animation finishes — no arbitrary delays
    showConfirmation = false
}
```

## 4. Anti-patterns that cause jank

### Wrapping async call in withAnimation

```swift
// WRONG — animation transaction is gone by the time posts updates
Button("Refresh") {
    withAnimation {
        Task { posts = try await api.fetchPosts() }
    }
}

// CORRECT — animate when the value lands
Button("Refresh") {
    Task {
        let new = try await api.fetchPosts()
        withAnimation(.smooth) { posts = new }
    }
}
```

### Implicit animation with no value (deprecated)

```swift
// WRONG — animates EVERYTHING, deprecated
SomeView().animation(.default)

// CORRECT — tied to a specific value
SomeView().animation(.default, value: isExpanded)
```

### Animating layout properties inside scroll views

Animating `frame`, `padding`, or other layout-affecting properties inside a `List`/`LazyVStack`
causes cascading body re-evaluations. Use transforms instead:

```swift
// WRONG — layout animation inside list
PostRow(post: post)
    .frame(height: isSelected ? 200 : 80)
    .animation(.spring, value: isSelected)

// CORRECT — transform-based, GPU-cheap
PostRow(post: post)
    .scaleEffect(isSelected ? 1.05 : 1)
    .animation(.spring, value: isSelected)
```

### Triggering animations from non-Equatable state

If your state type doesn't conform to `Equatable`, `.animation(_:value:)` fires on every
observation cycle. Make sure animated values are `Equatable`.

### Huge view subtrees in withAnimation

Only animate the smallest possible subview. Don't wrap 500 lines of view code in `withAnimation`.

## 5. Performance rules

- **GPU-cheap:** transforms (`scaleEffect`, `rotationEffect`, `offset`) and `opacity`
- **GPU-expensive:** layout changes that cause Core Animation commits (re-rasterization)
- **Profile with Instruments** → SwiftUI template. Watch View Body, View Properties, Core Animation
  Commits lanes. If body re-evaluates every frame during animation, state coupling is too broad.
- Use `drawingGroup()` to flatten a complex view subtree into a single Core Animation layer when
  it animates as a unit.
- Use animation completion handlers instead of dispatching with arbitrary delays.
