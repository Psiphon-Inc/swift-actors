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
import Promises

/// Base message type.
/// For any type that conforms to this protocol, it should provide an implementation of the `promise` property
/// such  that it returns (possibly nil) reference to the embedded promise object.
public protocol Message {
    var promise: Promise<Any>? { get }
}

/// A message type that messages that do not contain `Promsie` objects.
/// This protocol provides a default implementation of `promise` that always returns `nil`.
public protocol AnyMessage: Message {}

extension AnyMessage {

    public var promise: Promise<Any>? {
        return nil
    }

}

public extension Message {
    static func handler(_ action: @escaping (Self) -> ActionResult) -> ActionHandler {
        { (msg: Message) -> ActionResult in
            guard let msg = msg as? Self else {
                return .unhandled
            }
            return action(msg)
        }
    }
}

public enum SystemMessage: Message {
    /// Poison Pill message is like a regular message, but stops the actor immediately when it is processed.
    /// If a promise object is passed in, it is fulfilled after actor is stopped (but not necessarily after all of its
    /// children have stopped).
    case poisonPill(Promise<()>?)

    public var promise: Promise<Any>? {
        switch self {
        case let .poisonPill(promise):
            return promise?.eraseToAny()
        }
    }
}

public enum NotificationMessage: AnyMessage {

    /// Message sent to parent actor when one of its children gets terminated.
    case terminated(actor: ActorRef)

}

// Supported message types

extension String: AnyMessage {}

extension Int: AnyMessage {}
