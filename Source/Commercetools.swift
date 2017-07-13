//
// Copyright (c) 2016 Commercetools. All rights reserved.
//

import Foundation
import Alamofire
import ObjectMapper

// MARK: - Configuration

/**
    Provides access to the current `Config` instance.
*/
public var config: Config? {
    get {
        return Config.currentConfig
    }
    set (newConfig) {
        Config.currentConfig = newConfig
        // After setting the new configuration, we try to obtain the access token, and cache new project settings
        AuthManager.sharedInstance.token { token, error in
            if let error = error as? CTError {
                Log.error("Could not obtain auth token "
                        + (error.errorDescription ?? ""))
            } else {
                Project.settings { result in
                    Project.cached = result.model
                }
            }
        }
    }
}

#if os(watchOS)
public extension Notification.Name {
    /// Used as a namespace for all notifications related to watch token synchronization.
    public struct WatchSynchronization {
        /// Posted when proper access tokens have been received from the iOS app.
        public static let DidReceiveTokens = Notification.Name(rawValue: "com.commercetools.notification.watchSynchronization.didReceiveTokens")
    }
}
#endif

// MARK: - Authorization management

/// The current state handled by authentication manager.
public var authState: AuthManager.TokenState {
    return AuthManager.sharedInstance.state
}

// MARK: - Project settings

public struct Project: Endpoint, ImmutableMappable {
    public typealias ResponseType = Project
    public static let path = ""

    public static var cached: Project?

    /**
        Retrieves project settings.

        - parameter result:                   The code to be executed after processing the response.
    */
    public static func settings(result: @escaping (Result<ResponseType>) -> Void) {
        requestWithTokenAndPath(result, { token, path in
            Alamofire.request(path, headers: self.headers(token))
            .responseJSON(queue: DispatchQueue.global(), completionHandler: { response in
                handleResponse(response, result: result)
            })
        })
    }

    // MARK: - Properties

    public let key: String
    public let name: String
    public let countries: [String]
    public let currencies: [String]
    public let languages: [String]
    public let createdAt: Date
    public let trialUntil: Date?
    public let messagesEnabled: Bool

    // MARK: - Mappable

    public init(map: Map) throws {
        key                       = try map.value("key")
        name                      = try map.value("name")
        countries                 = try map.value("countries")
        currencies                = try map.value("currencies")
        languages                 = try map.value("languages")
        createdAt                 = try map.value("createdAt", using: ISO8601DateTransform())
        trialUntil                = try? map.value("trialUntil", using: ISO8601DateTransform())
        messagesEnabled           = try map.value("messages.enabled")
    }
}

/**
    This method should be used for customer login. After successful login the new auth token is used for all
    further requests with Commercetools services.
    In case this method is called before previously logging customer out, it will automatically logout (i.e remove
    previously stored tokens).

    - parameter username:               The user's username.
    - parameter password:               The user's password.
    - parameter activeCartSignInMode:   Optional sign in mode, specifying whether the cart line items should be merged.
    - parameter completionHandler:      The code to be executed once the token fetching completes.
*/
public func loginCustomer(username: String, password: String, activeCartSignInMode: AnonymousCartSignInMode? = nil,
                          result: @escaping (Result<CustomerSignInResult>) -> Void) {
    if authState == .customerToken {
        logoutCustomer()
    }

    // If the user is logging after an anonymous session, `/me/login` endpoint is triggered before obtaining
    // access and refresh tokens, so that carts and orders can be migrated
    Customer.login(username: username, password: password, activeCartSignInMode: activeCartSignInMode) { loginResult in
        if loginResult.isFailure {
            result(loginResult)
        } else {
            AuthManager.sharedInstance.loginCustomer(username: username, password: password) { error in
                if let error = error {
                    result(.failure(nil, [error]))
                } else {
                    result(loginResult)
                }
            }
        }
    }
}

/**
    Creates new customer with specified profile.

    - parameter profile:                  Draft of the customer profile to be created.
    - parameter result:                   The code to be executed after processing the response.
*/
public func signUpCustomer(_ profile: CustomerDraft, result: @escaping (Result<CustomerSignInResult>) -> Void) {
    signUpCustomer(Mapper<CustomerDraft>().toJSON(profile), result: result)
}

/**
    Creates new customer with specified profile.

    - parameter profile:                  Dictionary representation of the draft customer profile to be created.
    - parameter result:                   The code to be executed after processing the response.
*/
public func signUpCustomer(_ profile: [String: Any], result: @escaping (Result<CustomerSignInResult>) -> Void) {
    Customer.signUp(profile, result: { signUpResult in
        if signUpResult.isFailure {
            result(signUpResult)
        } else if let username = signUpResult.model?.customer.email, let password = profile["password"] as? String {
            AuthManager.sharedInstance.loginCustomer(username: username, password: password) { error in
                if let error = error {
                    result(.failure(nil, [error]))
                } else {
                    result(signUpResult)
                }
            }
        }
    })
}

/**
    This method will clear all tokens both from memory and persistent storage.
    Most common use case for this method is customer logout.
*/
public func logoutCustomer() {
    AuthManager.sharedInstance.logoutCustomer()
}

/**
    This method should be used to override `anonymousSession` Bool parameter from the configuration and get new tokens.
    Once this method is invoked, any previously logged in user will be logged out. In case there was an anonymous
    session active, the refresh token will be removed, and the session will not be recoverable any more.
    Most common use case for this method is user logout.

    - parameter usingSession:       Bool parameter indicating whether anonymous session should be used.
    - parameter anonymousId:        Optional argument to assign custom value for `anonymous_id`.
    - parameter completionHandler:  The code to be executed once the token fetching completes.
*/
public func obtainAnonymousToken(usingSession: Bool, anonymousId: String? = nil, completionHandler: @escaping (Error?) -> Void) {
    AuthManager.sharedInstance.obtainAnonymousToken(usingSession: usingSession, anonymousId: anonymousId, completionHandler: completionHandler)
}

public class ISO8601DateTransform: DateFormatterTransform {
    public init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"

        super.init(dateFormatter: formatter)
    }
}