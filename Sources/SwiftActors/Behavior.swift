/*
 * Copyright (c) 2019, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http:www.gnu.org/licenses/>.
 *
 */

import Foundation

public enum Receive {
    case unhandled(AnyMessage)
    case new(Behavior)
    case same
    case stop
}

public typealias Behavior = (Receive) throws -> Receive

public func behavior(_ processor: @escaping (AnyMessage) throws -> Receive) -> Behavior {
    return { r -> Receive in
        if case let .unhandled(msg) = r {
            return try processor(msg)
        }
        return r
    }
}

infix operator <| :TernaryPrecedence

/// Pipeline operator for composing `Behavior`s.
/// - Note: `<|` is right associative.
public func <| (lhs: @escaping Behavior, rhs: @escaping Behavior) -> Behavior {
    return { try lhs(try rhs($0)) }
}

