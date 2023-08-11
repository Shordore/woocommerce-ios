import Foundation
import Yosemite

/// View model for `StoreNameSetupView`.
///
final class StoreNameSetupViewModel {
    private let siteID: Int64
    private let stores: StoresManager

    init(siteID: Int64,
         stores: StoresManager = ServiceLocator.stores) {
        self.siteID = siteID
        self.stores = stores
    }
}
