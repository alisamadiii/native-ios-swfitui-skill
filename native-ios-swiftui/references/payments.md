# Payments Reference — StoreKit 2

## Table of Contents
1. SubscriptionStoreView paywall
2. Product display (StoreView, ProductView)
3. Transaction listening
4. Entitlement checking
5. StoreKit configuration for testing
6. App Store Server Notifications V2
7. When to use RevenueCat/Glassfy

---

## 1. SubscriptionStoreView paywall

The fastest path to a production paywall. Handles products, prices, localization, restore,
and purchase in one native component.

```swift
import StoreKit

struct PaywallView: View {
    var body: some View {
        SubscriptionStoreView(groupID: "YOUR_GROUP_ID") {
            VStack(spacing: 16) {
                Image(systemName: "star.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.yellow)

                Text("Unlock Pro")
                    .font(.largeTitle.bold())

                Text("Get unlimited access to all features")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .subscriptionStoreControlStyle(.buttons)
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStorePickerItemBackground(.thinMaterial)
        .onInAppPurchaseCompletion { _, result in
            switch result {
            case .success(.success(let transaction)):
                // Purchase succeeded — entitlement granted
                await transaction.finish()
            case .success(.pending):
                // Waiting for approval (Ask to Buy, etc.)
                break
            case .success(.userCancelled):
                break
            case .failure:
                // Purchase failed
                break
            }
        }
    }
}
```

### iOS 26: SubscriptionOfferView

New in iOS 26 — merchandise upgrade/downgrade/crossgrade offers:

```swift
SubscriptionOfferView(groupID: "YOUR_GROUP_ID") {
    // Custom marketing content for the offer
}
```

## 2. Product display

### StoreView — grid of products

```swift
StoreView(ids: ["com.app.weekly", "com.app.monthly", "com.app.yearly"]) { product in
    // Custom product icon
    ProductIconView(product: product)
}
.productViewStyle(.regular)
.storeButton(.visible, for: .restorePurchases)
```

### ProductView — single product

```swift
ProductView(id: "com.app.premium.lifetime") {
    // Custom icon
    Image(systemName: "crown.fill")
        .font(.title)
}
.productViewStyle(.large)
```

## 3. Transaction listening

Listen for entitlement updates app-wide. This catches purchases, renewals, revocations,
and refunds in near real-time.

```swift
@main
struct MyApp: App {
    @State private var entitlementManager = EntitlementManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(entitlementManager)
                .task {
                    await entitlementManager.listenForTransactions()
                    await entitlementManager.checkEntitlements()
                }
        }
    }
}

@MainActor
@Observable
final class EntitlementManager {
    private(set) var isPro = false
    private var updateTask: Task<Void, Never>?

    func listenForTransactions() async {
        updateTask = Task(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await updateEntitlement(for: transaction)
                await transaction.finish()
            }
        }
    }

    func checkEntitlements() async {
        // Check current entitlements on launch
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productType == .autoRenewable &&
               transaction.revocationDate == nil {
                isPro = true
                return
            }
        }
        isPro = false
    }

    private func updateEntitlement(for transaction: Transaction) async {
        if transaction.revocationDate != nil {
            isPro = false
        } else if transaction.productType == .autoRenewable {
            isPro = true
        }
    }

    deinit {
        updateTask?.cancel()
    }
}
```

## 4. Entitlement checking in views

```swift
struct PremiumFeatureView: View {
    @Environment(EntitlementManager.self) private var entitlements

    var body: some View {
        if entitlements.isPro {
            ProContentView()
        } else {
            LockedContentView()
                .overlay {
                    Button("Upgrade to Pro") { showPaywall = true }
                        .buttonStyle(.glassProminent)
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
        }
    }
}

// React to subscription status changes in a view
struct StatusAwareView: View {
    var body: some View {
        ContentView()
            .subscriptionStatusTask(for: "YOUR_GROUP_ID") { taskState in
                // taskState.value contains [Product.SubscriptionInfo.Status]
                // React to status changes here
            }
    }
}
```

## 5. StoreKit configuration for testing

Create a `.storekit` configuration file for local testing without hitting App Store Connect.
This is the fastest iteration loop.

1. In Xcode: File > New > File > StoreKit Configuration File
2. Add your subscription group and products
3. Set the scheme to use your configuration: Edit Scheme > Run > Options > StoreKit Configuration

```
Products.storekit
├── Subscription Group: "Premium"
│   ├── com.app.premium.weekly    ($2.99/week)
│   ├── com.app.premium.monthly   ($9.99/month)
│   └── com.app.premium.yearly    ($79.99/year)
└── Non-Consumable
    └── com.app.premium.lifetime  ($149.99)
```

Testing scenarios you can simulate:
- Purchase, cancel, refund
- Subscription renewal (accelerated in sandbox)
- Ask to Buy approval/denial
- Offer codes
- Billing retry / grace period

## 6. App Store Server Notifications V2

Enable these in App Store Connect. Your server gets real-time webhook notifications for:
- Subscription renewals and expirations
- Refunds and revocations
- Billing issues and grace periods
- Offer redemptions
- Price increase consent

This is the most efficient way to keep entitlements up to date server-side.

Setup:
1. App Store Connect > your app > App Information > App Store Server Notifications
2. Set your server endpoint URL
3. Select Version 2
4. Handle `signedPayload` JWS — verify signature, decode notification

## 7. When to use RevenueCat / Glassfy

Consider a managed entitlement backend when:
- You don't want to build server-side receipt validation infrastructure
- You need cross-platform entitlements (iOS + Android + web)
- You want built-in analytics (MRR, churn, LTV)
- You're hitting StoreKit edge cases (billing retry, grace periods, win-back offers)

RevenueCat is the most popular choice. It wraps StoreKit 2, handles server-side validation,
and provides a dashboard. Trade-off: adds a dependency and a % of revenue at scale.

For simple apps with iOS-only subscriptions, native StoreKit 2 with `SubscriptionStoreView`
is sufficient and has zero dependencies.
