import Foundation

/// Authenticated Requests Credentials
///
public enum Credentials: Codable, Equatable {

    // Keys
    private static let wpcomType = "AuthenticationType.wpcom"
    private static let wporgType = "AuthenticationType.wporg"
    private static let appPasswordType = "AuthenticationType.applicationPassword"

    /// For WordPress.com credentials
    ///
    case wpcom(username: String, authToken: String, siteAddress: String)

    /// For .org site credentials
    ///
    case wporg(username: String, password: String, siteAddress: String)

    /// For users that authorized application password through WP-admin
    ///
    case applicationPassword(username: String, password: String, siteAddress: String)

    /// For WPCOM credentials with placeholder site address
    ///
    public init(username: String, authToken: String) {
        self = .wpcom(username: username, authToken: authToken, siteAddress: Constants.placeholderSiteAddress)
    }

    /// Convenience initializer for wpcom credentials. Assigns a UUID as a placeholder for the username.
    ///
    public init(authToken: String) {
        self = .wpcom(username: UUID().uuidString, authToken: authToken, siteAddress: Constants.placeholderSiteAddress)
    }

    /// Failable initializer from raw types.
    ///
    public init?(rawType: String, username: String, secret: String, siteAddress: String) {
        switch rawType {
        case Self.wpcomType:
            self = .wpcom(username: username, authToken: secret, siteAddress: siteAddress)
        case Self.wporgType:
            self = .wporg(username: username, password: secret, siteAddress: siteAddress)
        case Self.appPasswordType:
            self = .applicationPassword(username: username, password: secret, siteAddress: siteAddress)
        default:
            return nil
        }
    }

    /// Returns true if the username is a UUID placeholder.
    ///
    public func hasPlaceholderUsername() -> Bool {
        // Only WPCOM credentials will have placeholder `username`
        guard case let .wpcom(username, _, _) = self else {
            return false
        }
        return UUID(uuidString: username) != nil
    }
}

private extension Credentials {
    struct Constants {
        static let placeholderSiteAddress = "https://wordpress.com"
    }
}

// MARK: - Helpers to read `Credentials`
//
public extension Credentials {
    var rawType: String {
        switch self {
        case .wpcom:
            return Self.wpcomType
        case .wporg:
            return Self.wporgType
        case .applicationPassword:
            return Self.appPasswordType
        }
    }

    var username: String {
        switch self {
        case .wpcom(let username, _, _):
            return username
        case .wporg(let username, _, _):
            return username
        case .applicationPassword(let username, _, _):
            return username
        }
    }

    var siteAddress: String {
        switch self {
        case .wpcom(_, _, let siteAddress):
            return siteAddress
        case .wporg(_, _, let siteAddress):
            return siteAddress
        case .applicationPassword(_, _, let siteAddress):
            return siteAddress
        }
    }

    var secret: String {
        switch self {
        case .wpcom(_, let authToken, _):
            return authToken
        case .wporg(_, let password, _):
            return password
        case .applicationPassword(_, let password, _):
            return password
        }
    }
}
