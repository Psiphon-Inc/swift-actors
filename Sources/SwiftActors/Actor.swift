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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation

public enum ActorErrors: Error {
    
    /// Unhandled message error.
    case unhandled(message: String)
    
    /// Actor response timeout error.
    case timeout(message: String)
}

public protocol Actor: class {
    
    var context: ActorContext! { get set }
    
    var receive: Behavior { get }
    
    /// Lifecycle method called before actor starts processing messages.
    func preStart()
    
    /// Lifecycle method called after an actor has been stopped.
    func postStop()
    
}

/// Default implementations
public extension Actor {
    
    func preStart() {}
    
    func postStop() {}
    
}

/// Internal extension
internal extension Actor {
    
    func bind(context: ActorContext) {
        guard self.context == nil else {
            preconditionFailure("actor '\(self.context.name)' already bound to a context")
        }
        self.context = context
    }
    
}

public extension Actor {
    
    var name: String {
        get { return context.name }
    }
    
    func parent() -> Actor? {
        return context.parent
    }
    
    func stop() {
        context.stop()
    }
    
    func tell(message: SystemMessage) {
        context.enqueueMessage(message: .system(message: message), from: nil)
    }
    
    func tell(message: AnyMessage) {
        context.enqueueMessage(message: .user(message: message), from: nil)
    }
    
    /// Sends a message to actor referenced by self, setting sender to from actor.
    func tell(message: AnyMessage, from actor: Actor) {
        context.enqueueMessage(message: .user(message: message), from: actor)
    }
    
    @discardableResult
    func spawn<T>(name: String, actor childActor: T) -> T where T: Actor {
        return context.spawn(name: name, actor: childActor)
    }
}

infix operator !

public func ! (lhs: Actor, rhs: AnyMessage) {
    lhs.tell(message: rhs)
}

public func ! (lhs: Actor, rhs: (message: AnyMessage, sender: Actor)) {
    lhs.tell(message: rhs.message, from: rhs.sender)
}
