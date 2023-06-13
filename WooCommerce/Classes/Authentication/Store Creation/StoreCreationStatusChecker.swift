import Combine
import Foundation
import Yosemite

/// Checks the ready status of store creation once the store has been created.
final class StoreCreationStatusChecker {
    private let stores: StoresManager
    private let jetpackCheckRetryInterval: TimeInterval
    private let storeName: String

    convenience init(isFreeTrialCreation: Bool,
                     storeName: String,
                     stores: StoresManager = ServiceLocator.stores) {
        self.init(jetpackCheckRetryInterval: isFreeTrialCreation ? 10 : 5, storeName: storeName, stores: stores)
    }

    init(jetpackCheckRetryInterval: TimeInterval, storeName: String, stores: StoresManager) {
        self.jetpackCheckRetryInterval = jetpackCheckRetryInterval
        self.storeName = storeName
        self.stores = stores
    }

    /// Waits for the site to have both Jetpack and WooCommerce plugins active, and the loads the latest site afterward.
    /// - Parameter siteID: WPCOM ID of the created site.
    /// - Returns: An observable value of either the created site when it's ready or an error.
    @MainActor
    func waitForSiteToBeReady(siteID: Int64) -> AnyPublisher<Site, Error> {
        Just(siteID)
            .tryAsyncMap { [weak self] siteID -> Site? in
                guard let self else {
                    return nil
                }
                // Waits some seconds before syncing sites every time.
                try await Task.sleep(nanoseconds: UInt64(self.jetpackCheckRetryInterval * 1_000_000_000))
                return try await self.syncSite(siteID: siteID)
            }
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

private extension StoreCreationStatusChecker {
    @MainActor
    func syncSite(siteID: Int64) async throws -> Site {
        let site = try await loadSite(siteID: siteID)
        guard site.isJetpackConnected && site.isJetpackThePluginInstalled else {
            DDLogInfo("🔵 Retrying: Site available but is not a jetpack site yet for siteID \(siteID)...")
            throw StoreCreationError.newSiteIsNotJetpackSite
        }
        guard site.isWordPressComStore && site.isWooCommerceActive && site.name == storeName else {
            DDLogInfo("🔵 Retrying: Site available but properties are not yet in sync...")
            throw StoreCreationError.newSiteIsNotFullySynced
        }
        return site
    }
}

private extension StoreCreationStatusChecker {
    @MainActor
    func loadSite(siteID: Int64) async throws -> Site {
        try await withCheckedThrowingContinuation { continuation in
            stores.dispatch(SiteAction.syncSite(siteID: siteID) { result in
                continuation.resume(with: result)
            })
        }
    }
}
