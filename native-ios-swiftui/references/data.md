# Data Persistence Reference — SwiftData

## Table of Contents
1. Model definition
2. Container setup
3. Querying data
4. Relationships
5. Schema migration
6. Offline-first sync pattern
7. When to use Core Data instead

---

## 1. Model definition

```swift
import SwiftData

@Model
final class Post {
    @Attribute(.unique) var id: UUID
    var body: String
    var createdAt: Date
    var authorName: String
    var likeCount: Int

    @Relationship(deleteRule: .cascade)
    var comments: [Comment] = []

    init(id: UUID = .init(), body: String, authorName: String, createdAt: Date = .now) {
        self.id = id
        self.body = body
        self.authorName = authorName
        self.createdAt = createdAt
        self.likeCount = 0
    }
}

@Model
final class Comment {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date

    var post: Post?

    init(id: UUID = .init(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}
```

Key points:
- `@Attribute(.unique)` enforces uniqueness — upserts on conflict
- `@Relationship(deleteRule: .cascade)` deletes children when parent is deleted
- All stored properties must have default values or be set in `init`
- Inverse relationships are inferred automatically (Comment.post <-> Post.comments)

## 2. Container setup

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Post.self, Comment.self])
    }
}
```

For custom configuration (e.g., in-memory for previews):

```swift
// Production
let container = try ModelContainer(
    for: Post.self, Comment.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: false)
)

// Previews / Tests
let previewContainer = try ModelContainer(
    for: Post.self, Comment.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
)
```

## 3. Querying data

### In views with @Query

```swift
struct FeedView: View {
    @Query(sort: \Post.createdAt, order: .reverse)
    private var posts: [Post]

    var body: some View {
        List(posts) { post in
            PostRow(post: post)
        }
    }
}

// With predicate
struct SearchView: View {
    @Query(filter: #Predicate<Post> { $0.likeCount > 10 },
           sort: \Post.createdAt, order: .reverse)
    private var popularPosts: [Post]
}
```

### In view models with ModelContext

```swift
@MainActor
@Observable
final class FeedViewModel {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchPosts() -> [Post] {
        let descriptor = FetchDescriptor<Post>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func createPost(body: String, author: String) {
        let post = Post(body: body, authorName: author)
        modelContext.insert(post)
        try? modelContext.save()
    }

    func deletePost(_ post: Post) {
        modelContext.delete(post)
        try? modelContext.save()
    }
}
```

### In background with @ModelActor

For heavy operations that shouldn't block the main thread:

```swift
@ModelActor
actor DataSyncer {
    func syncPosts(_ remotePosts: [PostDTO]) throws {
        for dto in remotePosts {
            let descriptor = FetchDescriptor<Post>(
                predicate: #Predicate { $0.id == dto.id }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.body = dto.body
                existing.likeCount = dto.likeCount
            } else {
                let post = Post(id: dto.id, body: dto.body, authorName: dto.authorName)
                post.likeCount = dto.likeCount
                modelContext.insert(post)
            }
        }
        try modelContext.save()
    }
}
```

## 4. Relationships

```swift
// One-to-many
@Model final class User {
    @Relationship(deleteRule: .cascade) var posts: [Post] = []
}

@Model final class Post {
    var author: User?  // inverse inferred automatically
}

// Many-to-many
@Model final class Post {
    @Relationship var tags: [Tag] = []
}

@Model final class Tag {
    @Attribute(.unique) var name: String
    @Relationship var posts: [Post] = []

    init(name: String) { self.name = name }
}
```

Delete rules:
- `.cascade` — delete children when parent is deleted
- `.nullify` (default) — set relationship to nil
- `.deny` — prevent deletion if children exist

## 5. Schema migration

SwiftData handles lightweight migrations automatically (adding properties with defaults, renaming).
For complex migrations, use `VersionedSchema` and `SchemaMigrationPlan`:

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Post.self] }

    @Model final class Post {
        var id: UUID
        var body: String
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Post.self] }

    @Model final class Post {
        var id: UUID
        var body: String
        var likeCount: Int = 0  // new field
    }
}

enum PostMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
```

## 6. Offline-first sync pattern

```swift
@MainActor
@Observable
final class FeedViewModel {
    private(set) var posts: [Post] = []
    private let modelContext: ModelContext
    private let api: any FeedServicing

    func load() async {
        // 1. Show local data immediately
        let descriptor = FetchDescriptor<Post>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        posts = (try? modelContext.fetch(descriptor)) ?? []

        // 2. Fetch remote and sync
        do {
            let remotePosts = try await api.fetchPosts()
            let syncer = DataSyncer(modelContainer: modelContext.container)
            try await syncer.syncPosts(remotePosts)

            // 3. Re-fetch to show updated data
            withAnimation(.smooth) {
                posts = (try? modelContext.fetch(descriptor)) ?? []
            }
        } catch {
            // If we have local data, keep showing it
            // If not, show error
            if posts.isEmpty {
                // Show error state
            }
        }
    }
}
```

## 7. When to use Core Data instead

Choose Core Data + CloudKit Sharing over SwiftData when:
- You need **shared/public CloudKit records** (social features, shared documents)
- You need **complex multi-step migrations** beyond lightweight
- You have **multi-process access** requirements
- You have an **existing Core Data investment** that's working

SwiftData and Core Data can coexist in the same app, but architecting two persistence layers
adds complexity. Choose one for new projects and stick with it unless you hit a hard wall.
