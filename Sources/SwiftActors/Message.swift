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

public protocol AnyMessage {}

public extension AnyMessage {
    static func be(_ action: @escaping (Self) -> ActionResult) -> Behavior {
        behavior { (msg: AnyMessage) -> ActionResult in
            guard let msg = msg as? Self else {
                return .unhandled
            }
            return action(msg)
        }
    }
}

public enum SystemMessage: AnyMessage {

    /// Poison Pill message is like a regular message, but stops the actor immediately when it is processed.
    case poisonPill
}

public enum NotificationMessage: AnyMessage {

    /// Message sent to parent actor when one of its children gets terminated.
    case terminated(actor: ActorRef)

}

// Supported message types

extension String: AnyMessage {}

extension Int: AnyMessage {}
