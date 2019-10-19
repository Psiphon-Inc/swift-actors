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

precedencegroup BehaviorCompositionPrecedence {
    associativity: right
    higherThan: AssignmentPrecedence
}

infix operator <| : BehaviorCompositionPrecedence

public enum Receive {
    case unhandled(AnyMessage, Behavior?)
    case handled(AnyMessage, Behavior)
    
    static func from(_ a: ActionResult, forMessage msg: AnyMessage, givenBehavior: @escaping Behavior) -> Self {
        switch a {
        case .unhandled:
            return .unhandled(msg, givenBehavior)
        case .same:
            return .handled(msg, givenBehavior)
        case .new(let behavior):
            return .handled(msg, behavior)
        }
    }
}

public enum ActionResult {
    case unhandled
    case same
    case new(Behavior)
}

public typealias Behavior = (Receive) throws -> Receive

public func behavior(_ action: @escaping (AnyMessage) throws -> ActionResult) -> Behavior {
    return { r -> Receive in
        switch r {
        case .unhandled(let msg, let b):
            let actionResult = try action(msg)
            let r2 = Receive.from(actionResult,
                                  forMessage: msg,
                                  givenBehavior: behavior(action))
            return r2 <| b

        case .handled(let msg, let b):
            return .handled(msg, behavior(action) <| b)
        }
    }
}

/// Pipeline operator for composing `Behavior`s.
/// - Note: `<|` is right associative.
public func <| (lhs: @escaping Behavior, rhs: @escaping Behavior) -> Behavior {
    return { try lhs(try rhs($0)) }
}

fileprivate func <| (lhs: Receive, rhs: Behavior?) -> Receive {
    guard let rhs = rhs else {
        return lhs
    }

    switch lhs {
    case .unhandled(let msg, let lb):
        return .unhandled(msg, lb! <| rhs)
    case .handled(let msg, let lb):
        return .handled(msg, lb <| rhs)
    }
}
