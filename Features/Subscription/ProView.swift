import SwiftUI
import StoreKit

// MARK: - StoreKit 2 Subscription Manager

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    // Decibel X standard subscription identifiers
    static let monthlyID = "com.soundmeter.pro.monthly"
    static let annualID = "com.soundmeter.pro.annual"
    static let lifetimeID = "com.soundmeter.pro.lifetime"

    private let productIdentifiers: Set<String> = [
        monthlyID,
        annualID,
        lifetimeID
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published var purchaseErrorMessage: String?

    var isProUser: Bool {
        !purchasedProductIDs.isEmpty
    }

    private var transactionListener: Task<Void, Error>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updateCustomerProductStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Load products from the App Store
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedProducts = try await Product.products(for: productIdentifiers)
            // Sort by price ascending
            self.products = loadedProducts.sorted(by: { $0.price < $1.price })
        } catch {
            print("StoreKit: Failed to load products: \(error.localizedDescription)")
        }
    }

    /// Purchase a product
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        purchaseErrorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateCustomerProductStatus()
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                purchaseErrorMessage = "Purchase is pending authorization (e.g. Ask to Buy)."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseErrorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Restore completed transactions / entitlements
    func restorePurchases() async {
        isLoading = true
        purchaseErrorMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateCustomerProductStatus()
        } catch {
            purchaseErrorMessage = "Failed to restore purchases: \(error.localizedDescription)"
        }
    }

    /// Background listener for external / renewal transactions
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateCustomerProductStatus()
                    await transaction.finish()
                } catch {
                    print("StoreKit: Transaction verification failed: \(error)")
                }
            }
        }
    }

    /// Refresh current entitlements
    func updateCustomerProductStatus() async {
        var purchased = Set<String>()
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            } catch {
                print("StoreKit: Entitlement check failed: \(error)")
            }
        }
        self.purchasedProductIDs = purchased
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Pro Subscription View (S09)

struct ProView: View {
    @StateObject private var store = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID: String = StoreKitManager.annualID
    @State private var showingConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                headerView

                featuresList

                if store.isProUser {
                    activeSubscriberBadge
                } else {
                    productsPricingSection

                    legalAndRestoreFooter
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Go Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .font(.title3)
                }
            }
        }
        .alert("Subscription", isPresented: Binding(
            get: { store.purchaseErrorMessage != nil },
            set: { if !$0 { store.purchaseErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.purchaseErrorMessage = nil }
        } message: {
            Text(store.purchaseErrorMessage ?? "")
        }
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.accent.opacity(0.35), AppTheme.accent.opacity(0.0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 65
                        )
                    )
                    .frame(width: 110, height: 110)

                Image(systemName: "crown.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.yellow, AppTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: AppTheme.accent.opacity(0.4), radius: 10, y: 3)
            }

            Text("SoundMeter Pro")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Certified-grade acoustic tools, real-time IEC 61672-1 filters, and polished client reports.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.top, 10)
    }

    // MARK: - Features
    private var featuresList: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 14) {
                ProFeatureRow(
                    icon: "waveform.path.ecg",
                    title: "IEC 61672-1 Digital Weighting",
                    subtitle: "Full dBA (human hearing) & dBC (low-frequency / motor) biquad filters."
                )

                Divider().opacity(0.4)

                ProFeatureRow(
                    icon: "doc.richtext.fill",
                    title: "Executive PDF Acoustic Reports",
                    subtitle: "Vector decibel time-history graphs, Leq, L10/L50/L90 percentiles & share sheets."
                )

                Divider().opacity(0.4)

                ProFeatureRow(
                    icon: "chart.bar.xaxis",
                    title: "High-Resolution FFT Analyzer",
                    subtitle: "Real-time vDSP frequency spectrum and dominant frequency tracking."
                )

                Divider().opacity(0.4)

                ProFeatureRow(
                    icon: "camera.viewfinder",
                    title: "Media Burn-in Camera Overlays",
                    subtitle: "Photo & video timestamp watermarking with frame-by-frame decibel sync."
                )

                Divider().opacity(0.4)

                ProFeatureRow(
                    icon: "infinity",
                    title: "Unlimited Session Archives & CSV",
                    subtitle: "Full raw PCM export and unbounded local SQLite / SwiftData storage."
                )
            }
        }
    }

    // MARK: - Active Subscriber Badge
    private var activeSubscriberBadge: some View {
        PremiumCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title)
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SoundMeter Pro Active")
                            .font(.headline.bold())
                        Text("You have full access to all professional features.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    Text("Refresh Subscription Status")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Pricing Plans Section
    private var productsPricingSection: some View {
        VStack(spacing: 14) {
            // Check if StoreKit products loaded; if not, show standard Decibel X fallback cards
            if store.products.isEmpty {
                fallbackPlanCards
            } else {
                ForEach(store.products) { product in
                    planCard(
                        id: product.id,
                        title: product.displayName,
                        priceText: product.displayPrice,
                        periodText: periodDescription(for: product),
                        badgeText: product.id == StoreKitManager.annualID ? "BEST VALUE • SAVE 50%" : nil,
                        isSelected: selectedPlanID == product.id
                    ) {
                        selectedPlanID = product.id
                    }
                }
            }

            // Purchase Button
            Button {
                handlePurchase()
            } label: {
                HStack(spacing: 8) {
                    if store.isPurchasing {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Continue")
                            .font(.headline.bold())
                        Image(systemName: "arrow.right")
                            .font(.subheadline.bold())
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [AppTheme.accent, Color(red: 0.10, green: 0.90, blue: 0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, y: 3)
            }
            .disabled(store.isPurchasing || store.isLoading)
        }
    }

    private var fallbackPlanCards: some View {
        VStack(spacing: 12) {
            planCard(
                id: StoreKitManager.annualID,
                title: "Annual Pro Plan",
                priceText: "$29.99 / year",
                periodText: "Only $2.50 / month (billed annually)",
                badgeText: "BEST VALUE • SAVE 50%",
                isSelected: selectedPlanID == StoreKitManager.annualID
            ) {
                selectedPlanID = StoreKitManager.annualID
            }

            planCard(
                id: StoreKitManager.monthlyID,
                title: "Monthly Pro Plan",
                priceText: "$4.99 / month",
                periodText: "Billed monthly, cancel anytime",
                badgeText: nil,
                isSelected: selectedPlanID == StoreKitManager.monthlyID
            ) {
                selectedPlanID = StoreKitManager.monthlyID
            }

            planCard(
                id: StoreKitManager.lifetimeID,
                title: "Lifetime License",
                priceText: "$69.99 once",
                periodText: "One-time purchase • All future updates",
                badgeText: "LIFETIME",
                isSelected: selectedPlanID == StoreKitManager.lifetimeID
            ) {
                selectedPlanID = StoreKitManager.lifetimeID
            }
        }
    }

    private func planCard(
        id: String,
        title: String,
        priceText: String,
        periodText: String,
        badgeText: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary.opacity(0.5))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(periodText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(priceText)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isSelected ? AppTheme.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                        )
                )

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent, in: Capsule())
                        .offset(x: -12, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func periodDescription(for product: Product) -> String {
        if let sub = product.subscription {
            let unit = sub.subscriptionPeriod.unit
            let count = sub.subscriptionPeriod.value
            switch unit {
            case .month: return count == 1 ? "Billed monthly" : "Billed every \(count) months"
            case .year: return count == 1 ? "Billed annually" : "Billed every \(count) years"
            case .week: return count == 1 ? "Billed weekly" : "Billed every \(count) weeks"
            case .day: return "Billed daily"
            @unknown default: return ""
            }
        } else {
            return "One-time purchase"
        }
    }

    // MARK: - Purchase Handling
    private func handlePurchase() {
        if let product = store.products.first(where: { $0.id == selectedPlanID }) {
            Task {
                let success = await store.purchase(product)
                if success {
                    dismiss()
                }
            }
        } else {
            // When in simulator without an active StoreKit Configuration file, simulate unlock or note
            store.purchaseErrorMessage = "To test StoreKit 2 purchases with live products, add a StoreKit Configuration file or test on device."
        }
    }

    // MARK: - Legal & Restore Footer
    private var legalAndRestoreFooter: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button("Restore Purchases") {
                    Task { await store.restorePurchases() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text("•").foregroundStyle(.secondary)

                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("•").foregroundStyle(.secondary)

                Link("Privacy Policy", destination: URL(string: "https://developer.apple.com")!)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Subscriptions automatically renew unless auto-renew is turned off at least 24 hours before the end of the current billing period. Manage subscriptions in Account Settings.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }
}

// MARK: - Feature Row
private struct ProFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 26, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
