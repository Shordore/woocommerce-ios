import Combine
import Foundation

public protocol SessionManagerProtocol {

    /// Ephemeral: Default Account.
    ///
    var defaultAccount: Account? { get set}

    /// Default AccountID: Returns the last known Account's User ID.
    ///
    var defaultAccountID: Int64? { get }

    /// Default Store Site
    ///
    var defaultSite: Site? { get set }

    /// Publishes default site on change.
    ///
    var defaultSitePublisher: AnyPublisher<Site?, Never> { get }

    /// Default StoreID.
    /// This is in fact the WPCom `siteID`.
    ///
    var defaultStoreID: Int64? { get set }

    /// Unique WooCommerce Store UUID.
    /// Do not conduse with `defaultStoreID` which is in fact the WPCom `siteID`.
    ///
    var defaultStoreUUID: String? { get set }

    /// Roles for the default Store Site.
    ///
    var defaultRoles: [User.Role] { get set }

    /// Publishes default store ID on change.
    ///
    var defaultStoreIDPublisher: AnyPublisher<Int64?, Never> { get }

    /// Anonymous UserID.
    ///
    var anonymousUserID: String? { get }

    /// Default Credentials.
    ///
    var defaultCredentials: Credentials? { get set}

    /// Nukes all of the known Session's properties.
    ///
    func reset()

    /// Deletes application password
    ///
    func deleteApplicationPassword()
}
