//
// Copyright (c) 2016 Commercetools. All rights reserved.
//

import ObjectMapper

public struct DiscountedLineItemPrice: Mappable {

    // MARK: - Properties

    public var value: Money?
    public var includedDiscounts: [DiscountedLineItemPortion]?

    public init?(map: Map) {}

    // MARK: - Mappable

    mutating public func mapping(map: Map) {
        value             <- map["value"]
        includedDiscounts <- map["includedDiscounts"]
    }

}
