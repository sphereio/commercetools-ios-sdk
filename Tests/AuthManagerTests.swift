//
//  Copyright © 2016 Commercetools. All rights reserved.
//

import XCTest
@testable import Commercetools

class AuthManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    
        cleanPersistedTokens()
    }
    
    override func tearDown() {
        cleanPersistedTokens()
        
        super.tearDown()
    }

    func testUserLogin() {
        setupTestConfiguration()

        let loginExpectation = expectationWithDescription("login expectation")
        let tokenExpectation = expectationWithDescription("token expectation")

        let username = "swift.sdk.test.user@commercetools.com"
        let password = "password"
        let authManager = AuthManager.sharedInstance

        var oldToken: String?
        authManager.token { token, error in oldToken = token }

        authManager.loginUser(username, password: password, completionHandler: { error in
            if error == nil {
                loginExpectation.fulfill()
            }
        })

        authManager.token { token, error in
            if let token = token, oldToken = oldToken where !token.isEmpty && token != oldToken &&
                    error == nil && authManager.state == .CustomerToken {
                tokenExpectation.fulfill()
            }
        }

        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testUserLogout() {
        setupTestConfiguration()

        let tokenExpectation = expectationWithDescription("token expectation")

        let username = "swift.sdk.test.user@commercetools.com"
        let password = "password"
        let authManager = AuthManager.sharedInstance

        authManager.loginUser(username, password: password, completionHandler: { error in
            if error == nil {
                // Get the access token after login
                authManager.token { oldToken, error in
                    if let oldToken = oldToken where authManager.state == .CustomerToken {
                        // Then logout user
                        authManager.logoutUser()
                        // Get the access token after logout
                        authManager.token { newToken, error in
                            if let newToken = newToken where newToken != oldToken && authManager.state == .AnonymousToken {
                                tokenExpectation.fulfill()
                            }
                        }
                    }
                }
            }
        })

        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testIncorrectLogin() {
        setupTestConfiguration()

        let loginExpectation = expectationWithDescription("login expectation")
        let tokenExpectation = expectationWithDescription("token expectation")

        let username = "incorrect.sdk.test.user@commercetools.com"
        let password = "password"
        let authManager = AuthManager.sharedInstance

        var oldToken: String?
        authManager.token { token, error in oldToken = token }

        authManager.loginUser(username, password: password, completionHandler: { error in
            if let error = error, errorReason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
                errorDesc = error.userInfo[NSLocalizedDescriptionKey] as? String
                where errorReason == "invalid_customer_account_credentials" &&
                        errorDesc == "Customer account with the given credentials not found." {
                loginExpectation.fulfill()
            }
        })

        authManager.token { token, error in
            if let token = token, oldToken = oldToken where !token.isEmpty && token != oldToken &&
                    error == nil && authManager.state == .AnonymousToken {
                tokenExpectation.fulfill()
            }
        }

        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testAnonymousToken() {
        setupTestConfiguration()

        let tokenExpectation = expectationWithDescription("token expectation")

        let authManager = AuthManager.sharedInstance
        authManager.obtainAnonymousToken(usingSession: false, completionHandler: { _ in
            authManager.token { token, error in
                if let token = token where !token.isEmpty && error == nil && authManager.state == .PlainToken {
                    tokenExpectation.fulfill()
                }
            }
        })

        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testRefreshToken() {
        setupTestConfiguration()

        let tokenExpectation = expectationWithDescription("token expectation")

        let authManager = AuthManager.sharedInstance
        let tokenStore = authManager.tokenStore

        let username = "swift.sdk.test.user@commercetools.com"
        let password = "password"

        authManager.loginUser(username, password: password, completionHandler: { error in
            if error == nil {

                var oldToken: String?
                authManager.token { token, error in
                    oldToken = token
                    // Remove the access token valid date after login, in order to test the refresh token flow
                    tokenStore.tokenValidDate = nil
                    XCTAssert(!tokenStore.refreshToken!.isEmpty)
                    XCTAssert(oldToken != nil)
                }

                authManager.token { token, error in
                    if let token = token, oldToken = oldToken where error == nil && oldToken != token &&
                            authManager.state == .CustomerToken {
                        tokenExpectation.fulfill()
                    }
                }
            }
        })

        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testAssigningAnonymousId() {
        setupTestConfiguration()
        let anonymousIdExpectation = expectationWithDescription("anonymous id expectation")
        let anonymousId = NSUUID().UUIDString
        let authManager = AuthManager.sharedInstance

        authManager.obtainAnonymousToken(usingSession: true, anonymousId: anonymousId, completionHandler: { error in
            if error == nil && authManager.state == .AnonymousToken {
                Cart.create(["currency": "EUR"], result: { result in
                    if let response = result.response, cartAnonymousId = response["anonymousId"] as? String
                    where result.isSuccess && cartAnonymousId == anonymousId {
                        anonymousIdExpectation.fulfill()
                    }
                })
            }

        })

        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testAnonymousSessionDuplicateId() {
        setupTestConfiguration()

        let anonymousSessionExpectation = expectationWithDescription("anonymous session expectation")
        let authManager = AuthManager.sharedInstance

        // Retrieve token with the anonymousId for the first time
        authManager.obtainAnonymousToken(usingSession: true, anonymousId: "test", completionHandler: { error in

            // Try creating anonymous session with the same anonymousId again
            authManager.obtainAnonymousToken(usingSession: true, anonymousId: "test", completionHandler: { error in
                if let error = error, errorReason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
                        errorDesc = error.userInfo[NSLocalizedDescriptionKey] as? String
                        where errorReason == "invalid_request" &&
                        errorDesc == "The anonymousId is already in use." {
                    anonymousSessionExpectation.fulfill()
                }
            })
        })

        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testPlistUsingAnonymousSessionConfig() {
        setupTestConfiguration()

        let anonymousSessionExpectation = expectationWithDescription("anonymous session expectation")
        let authManager = AuthManager.sharedInstance

        // Configuration in plist has anonymousSession usage set to true, so we should get anonymous session token
        authManager.token { token, error in
            if let _ = token where error == nil && authManager.state == .AnonymousToken {
                anonymousSessionExpectation.fulfill()
            }
        }

        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testOverrideAnonymousSessionConfig() {
        setupTestConfiguration()

        let authManager = AuthManager.sharedInstance
        let anonymousSessionExpectation = expectationWithDescription("anonymous session expectation")

        authManager.obtainAnonymousToken(usingSession: false, completionHandler: { error in
            if error == nil && authManager.state == .PlainToken {
                anonymousSessionExpectation.fulfill()
            }
        })

        waitForExpectationsWithTimeout(10, handler: nil)
    }
    
}