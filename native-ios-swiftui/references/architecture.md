# Architecture Reference — MVVM + @Observable + Actors

## Table of Contents
1. The pattern
2. ViewState enum
3. View model template
4. View template
5. Dependency injection
6. Project structure
7. When to break the pattern

---

## 1. The pattern

```
View (@State var vm) --> ViewModel (@MainActor @Observable) --> Service (actor) --> Network/DB
```

- **Views** are thin and declarative. They own a view model via `@State`.
- **View models** are `@MainActor @Observable` classes. They hold screen state and call services.
- **Services** are `actor`s behind protocols. They own async work (networking, persistence, caching).
- **Models** are `@Model` (SwiftData) for persistence or `Sendable` structs for DTOs.

## 2. ViewState enum

Every screen that loads data uses this pattern:

```swift
enum ViewState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(APIError)
}
```

Use it in views:

```swift
var body: some View {
    Group {
        switch vm.state {
        case .idle, .loading:
            ProgressView()
        case .loaded(let items):
            ContentView(items: items)
        case .failed(let error):
            ErrorView(error: error, retry: { Task { await vm.load() } })
        }
    }
}
```

## 3. View model template

```swift
@MainActor
@Observable
final class FeedViewModel {
    private(set) var state: ViewState<[Post]> = .idle
    private let api: any FeedServicing

    init(api: any FeedServicing) {
        self.api = api
    }

    func load() async {
        guard case .idle = state else { return }  // prevent duplicate loads
        state = .loading
        do {
            let posts = try await api.fetchPosts()
            state = .loaded(posts)
        } catch {
            state = .failed(error as? APIError ?? .invalidResponse)
        }
    }

    func refresh() async {
        // Allow refresh even when loaded
        do {
            let posts = try await api.fetchPosts()
            withAnimation(.smooth) { state = .loaded(posts) }
        } catch {
            // Keep existing data on refresh failure, show transient error
            state = .failed(error as? APIError ?? .invalidResponse)
        }
    }
}
```

Key points:
- `@MainActor` — all property access is on main thread, safe for SwiftUI
- `@Observable` — SwiftUI tracks per-property reads, only re-renders when read properties change
- `private(set)` — views read state, only the VM mutates it
- Protocol-based service injection — testable with mocks

## 4. View template

```swift
struct FeedView: View {
    @State private var vm: FeedViewModel

    init(api: any FeedServicing) {
        _vm = State(wrappedValue: FeedViewModel(api: api))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                ProgressView()
            case .loaded(let posts):
                List(posts) { post in
                    PostRow(post: post)
                }
                .refreshable { await vm.refresh() }
            case .failed(let error):
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") { Task { await vm.load() } }
                }
            }
        }
        .navigationTitle("Feed")
        .task { await vm.load() }  // auto-cancels on disappear
    }
}
```

Key points:
- `@State` owns the `@Observable` view model (replaces `@StateObject`)
- `.task { }` instead of `.onAppear { Task { } }` — auto-cancellation
- `.refreshable` for pull-to-refresh — built-in loading indicator
- `ContentUnavailableView` for empty/error states — native component

## 5. Dependency injection

### Screen-local: initializer injection

```swift
// The view creates its own VM with injected service
struct ProfileView: View {
    @State private var vm: ProfileViewModel

    init(userService: any UserServicing) {
        _vm = State(wrappedValue: ProfileViewModel(userService: userService))
    }
}
```

### Cross-cutting: @Environment

For services needed everywhere (auth, analytics, current user):

```swift
// Define the environment key
private struct AuthManagerKey: EnvironmentKey {
    static let defaultValue: AuthManager = AuthManager()
}

extension EnvironmentValues {
    var authManager: AuthManager {
        get { self[AuthManagerKey.self] }
        set { self[AuthManagerKey.self] = newValue }
    }
}

// Inject at the app level
@main
struct MyApp: App {
    let authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.authManager, authManager)
        }
    }
}

// Use anywhere
struct SettingsView: View {
    @Environment(\.authManager) private var auth

    var body: some View {
        Button("Sign Out") { Task { await auth.signOut() } }
    }
}
```

### Service protocol pattern

```swift
protocol FeedServicing: Sendable {
    func fetchPosts() async throws -> [Post]
    func createPost(_ body: String) async throws -> Post
}

// Production implementation
extension APIClient: FeedServicing {
    func fetchPosts() async throws -> [Post] {
        try await send(Endpoint(path: "/posts", method: "GET", body: nil))
    }

    func createPost(_ body: String) async throws -> Post {
        let data = try JSONEncoder().encode(["body": body])
        return try await send(Endpoint(path: "/posts", method: "POST", body: data))
    }
}

// Test mock
final class MockFeedService: FeedServicing {
    var postsToReturn: [Post] = []
    func fetchPosts() async throws -> [Post] { postsToReturn }
    func createPost(_ body: String) async throws -> Post {
        Post(id: .init(), body: body)
    }
}
```

## 6. Project structure

```
MyApp/
├── App.swift                    // @main, modelContainer, environment injection
├── Models/
│   ├── Post.swift               // @Model for SwiftData
│   ├── User.swift
│   └── DTOs/
│       ├── PostDTO.swift        // Sendable Codable structs for API responses
│       └── UserDTO.swift
├── Services/
│   ├── APIClient.swift          // actor, generic endpoint sending
│   ├── AuthManager.swift        // actor, token storage + refresh
│   └── Protocols/
│       ├── FeedServicing.swift
│       └── UserServicing.swift
├── ViewModels/
│   ├── FeedViewModel.swift
│   ├── ProfileViewModel.swift
│   └── OnboardingViewModel.swift
├── Views/
│   ├── Feed/
│   │   ├── FeedView.swift
│   │   └── PostRow.swift
│   ├── Profile/
│   │   └── ProfileView.swift
│   ├── Auth/
│   │   └── SignInView.swift
│   ├── Onboarding/
│   │   └── OnboardingView.swift
│   └── Components/
│       ├── ErrorView.swift
│       └── LoadingView.swift
└── Resources/
    ├── Assets.xcassets
    └── Products.storekit
```

## 7. When to break the pattern

- **Simple static screens** (About, Settings with just toggles): skip the view model, use `@State`
  and `@AppStorage` directly in the view.
- **One-shot actions** (share sheet, mailto): no VM needed, handle in the view.
- **Deep feature composition with shared state**: evaluate TCA, but only if the team has TCA
  experience and >5 features sharing state.

The default is always: one VM per screen, actors for services, protocols for testability.
