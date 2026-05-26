# Networking Reference — Actor-based APIClient

## Table of Contents
1. APIClient actor
2. Endpoint pattern
3. Auth token management
4. Error handling
5. Caching strategies
6. Rules

---

## 1. APIClient actor

```swift
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

actor APIClient: HTTPClient {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let authManager: AuthManager

    init(
        baseURL: URL,
        authManager: AuthManager,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authManager = authManager
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.status(http.statusCode)
        }
        return (data, http)
    }

    func send<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async throws -> R {
        var request = URLRequest(url: baseURL.appending(path: endpoint.path))
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Attach auth token
        if let token = await authManager.validToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await data(for: request)

        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
```

## 2. Endpoint pattern

```swift
struct Endpoint<Response: Decodable & Sendable>: Sendable {
    let path: String
    let method: String
    let body: Data?

    static func get(_ path: String) -> Endpoint<Response> {
        Endpoint(path: path, method: "GET", body: nil)
    }

    static func post(_ path: String, body: some Encodable) throws -> Endpoint<Response> {
        Endpoint(path: path, method: "POST", body: try JSONEncoder().encode(body))
    }

    static func put(_ path: String, body: some Encodable) throws -> Endpoint<Response> {
        Endpoint(path: path, method: "PUT", body: try JSONEncoder().encode(body))
    }

    static func delete(_ path: String) -> Endpoint<Response> {
        Endpoint(path: path, method: "DELETE", body: nil)
    }
}

// Usage
let posts: [Post] = try await api.send(.get("/posts"))
let newPost: Post = try await api.send(.post("/posts", body: CreatePostRequest(body: "Hello")))
```

## 3. Auth token management

The critical pattern: a single in-flight refresh task prevents multiple concurrent requests from
each triggering their own token refresh.

```swift
actor AuthManager {
    private var tokens: Tokens?
    private var refreshTask: Task<String, Error>?

    struct Tokens: Sendable {
        let access: String
        let refresh: String
        let expiresAt: Date
    }

    /// Returns a valid access token, refreshing if needed
    func validToken() async -> String? {
        guard let tokens else { return nil }

        // Token still valid — return it
        if tokens.expiresAt > .now.addingTimeInterval(60) {
            return tokens.access
        }

        // Already refreshing — wait for that result
        if let refreshTask {
            return try? await refreshTask.value
        }

        // Start a refresh
        let task = Task<String, Error> {
            defer { refreshTask = nil }
            let newTokens = try await performRefresh(refreshToken: tokens.refresh)
            self.tokens = newTokens
            return newTokens.access
        }
        refreshTask = task
        return try? await task.value
    }

    func setTokens(_ tokens: Tokens) {
        self.tokens = tokens
        // Also persist to Keychain
    }

    func clearTokens() {
        self.tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        // Also clear Keychain
    }

    private func performRefresh(refreshToken: String) async throws -> Tokens {
        // Call your backend's token refresh endpoint
        // This is the ONLY place refresh happens
        fatalError("Implement with your backend's refresh endpoint")
    }
}
```

## 4. Error handling

```swift
enum APIError: Error, Sendable, LocalizedError {
    case invalidResponse
    case status(Int)
    case decoding(any Error)
    case offline
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .status(let code): "Server error (\(code))"
        case .decoding: "Failed to read server response"
        case .offline: "No internet connection"
        case .unauthorized: "Please sign in again"
        }
    }
}
```

Surface in the VM using `ViewState<T>`:

```swift
state = .failed(error as? APIError ?? .invalidResponse)
```

## 5. Caching strategies

### HTTP cache

For read-heavy endpoints, configure `URLCache`:

```swift
let config = URLSessionConfiguration.default
config.urlCache = URLCache(
    memoryCapacity: 10_000_000,   // 10 MB
    diskCapacity: 50_000_000      // 50 MB
)
config.requestCachePolicy = .useProtocolCachePolicy
let session = URLSession(configuration: config)
```

### Offline-first with SwiftData

```swift
// Pattern: read local -> show -> fetch remote -> update local
func load() async {
    // 1. Show cached data immediately
    let cached = fetchFromSwiftData()
    if !cached.isEmpty {
        state = .loaded(cached)
    } else {
        state = .loading
    }

    // 2. Fetch fresh data
    do {
        let remote = try await api.fetchPosts()
        saveToSwiftData(remote)
        withAnimation(.smooth) { state = .loaded(remote) }
    } catch {
        if case .loaded = state { return }  // keep showing cached
        state = .failed(error as? APIError ?? .invalidResponse)
    }
}
```

### Image cache

For production social feeds, use Nuke or Kingfisher with disk LRU. `AsyncImage` is fine for
prototypes but lacks disk caching and fine-grained control.

### In-memory micro-cache

```swift
actor SimpleCache<Key: Hashable & Sendable, Value: Sendable> {
    private var store: [Key: (value: Value, expiry: Date)] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 300) { self.ttl = ttl }

    func get(_ key: Key) -> Value? {
        guard let entry = store[key], entry.expiry > .now else {
            store[key] = nil
            return nil
        }
        return entry.value
    }

    func set(_ key: Key, value: Value) {
        store[key] = (value, .now.addingTimeInterval(ttl))
    }
}
```

## 6. Rules

- Use the configured `APIClient` actor for all calls to your own backend
- Use raw `URLSession` (not `APIClient`) for third-party URLs (S3 presigned URLs, external upload
  endpoints) — the auth interceptor adds `Authorization` headers that third-party services reject
- Every DTO must be `Sendable` and `Codable`
- Never `try!` network calls
- Never force-unwrap `URL(string:)`
- Never use `Data(contentsOf:)` on a URL — blocks the calling thread
- Never hand-roll Combine pipelines for sequential requests — use `async/await`
- Never use `.shared` URLSession with no configurability — kills testability
