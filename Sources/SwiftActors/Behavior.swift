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

precedencegroup BehaviorAdditionPrecedence {
    associativity: right
    higherThan: AssignmentPrecedence
}

precedencegroup BehaviorAlternativePrecedence {
    associativity: right
    higherThan: BehaviorAdditionPrecedence
}

infix operator <> : BehaviorAdditionPrecedence
infix operator <|> : BehaviorAlternativePrecedence

public enum Receive {
    case handled(AnyMessage, Behavior)
    case unhandled(AnyMessage, Behavior?)
}

public enum ActionResult {
    case unhandled
    case same
    case action(ActionHandler)
    case behavior(Behavior)
}

public typealias Behavior = (Receive) throws -> Receive
public typealias ActionHandler = (AnyMessage) throws -> ActionResult
fileprivate typealias Composition = (@escaping ActionHandler, Receive) throws -> Receive

public func behavior(_ action: @escaping ActionHandler) -> Behavior {
    return lift(action, applyAlternative)
}

fileprivate func lift(_ action: @escaping ActionHandler, _ compose: @escaping Composition) -> Behavior {
    return { r -> Receive in
        return try compose(action, r)
    }
}

public func <|> (lhs: @escaping Behavior, rhs: Behavior? = .none) -> Behavior {
    return { r -> Receive in
        if let rhs = rhs {
            return try lhs(try rhs(r))
        } else {
            return try lhs(r)
        }
    }
}

// MARK: <> "append"

fileprivate func applyAppend(action: @escaping ActionHandler, to partialResult: Receive) rethrows -> Receive {
    switch partialResult {
    case .unhandled(let msg, let b):

        switch try action(msg) {
        case .unhandled:
            return .unhandled(msg, action <> b)
        case .same:
            return .handled(msg, action <> b)
        case .action(let newAction):
            return .handled(msg, newAction <> b)
        case .behavior(let newBehavior):
            return .handled(msg, newBehavior <|> b!)
        }

    case .handled(let msg, let b):
        return .handled(msg, action <> b)
    }
}

public func <> (lhs: @escaping ActionHandler, rhs: @escaping ActionHandler) -> Behavior {
    return lhs <> lift(rhs, applyAppend)
}

public func <> (lhs: @escaping ActionHandler, rhs: Behavior? = .none) -> Behavior {
    return lift(lhs, applyAppend) <|> rhs
}

// MARK: <|> "alternative"

fileprivate func applyAlternative(action: @escaping ActionHandler, to partialResult: Receive)
    rethrows -> Receive {

        switch partialResult {
        case .unhandled(let msg, let b):

            switch try action(msg) {
            case .unhandled:
                return .unhandled(msg, action <|> b)
            case .same:
                return .handled(msg, action <|> b)
            case .action(let newAction):
                return .handled(msg, newAction <|> .none)
            case .behavior(let newBehavior):
                return .handled(msg, newBehavior)
            }

        case .handled(let msg, let b):
            return .handled(msg, action <|> b)
        }
}

public func <|> (lhs: @escaping ActionHandler, rhs: @escaping ActionHandler) -> Behavior {
    return lhs <|> lift(rhs, applyAlternative)
}

public func <|> (lhs: @escaping ActionHandler, rhs: Behavior? = .none) -> Behavior {
    return lift(lhs, applyAlternative) <|> rhs
}
