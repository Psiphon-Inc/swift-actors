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

public struct ActorError: Error {

    enum ErrorType {
        /// Actor invariant over state failed to hold.
        case failedInvariant

        /// Unhandled message error.
        case unhandled

        /// Actor response timeout error.
        case timeout
    }

    let path: String
    let message: AnyMessage
    let errorMessage: String
    let errorType: ErrorType

    init(_ origin: Actor, _ message: AnyMessage, _ errorMessage: String, _ type: ErrorType) {
        self.path = origin.name
        self.message = message
        self.errorMessage = errorMessage
        self.errorType = type
    }
}

public struct InvariantError: Error {
    let message: String

    public init (_ message: String) {
        self.message = message
    }
}

public protocol Actor: class {
    
    var context: ActorContext! { get set }
    
    var receive: Behavior { get }

    /// Invariant test for the actor class.
    /// - Note: Invariant is tested after each message that is processed.
    /// - Parameters:
    ///     - message: Processed message.
    ///     - result: Result of processing the current message.
    /// - Returns: Optionally returns an invariant if there was one, otherwise nil.
    func invariant(message: AnyMessage, result: Receive) -> InvariantError?

    /// Lifecycle method called before actor starts processing messages.
    func preStart()
    
    /// Lifecycle method called after an actor has been stopped.
    func postStop()
    
}

/// Default implementations
public extension Actor {

    func invariant(message: AnyMessage, result: Receive) -> InvariantError? {
        return nil
    }

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

infix operator ! : AssignmentPrecedence

public func ! (lhs: Actor, rhs: AnyMessage) {
    lhs.tell(message: rhs)
}

public func ! (lhs: Actor, rhs: (message: AnyMessage, sender: Actor)) {
    lhs.tell(message: rhs.message, from: rhs.sender)
}
