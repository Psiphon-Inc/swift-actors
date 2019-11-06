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

public protocol ActorRefFactory {

    @discardableResult
    func spawn<T>(_ props: Props<T>, name: String) -> ActorRef where T: Actor

}

public protocol ActorRef: class {

    var name: String { get }

    var path: String { get }

    var system: ActorSystem { get }

    func tell(message: SystemMessage)

    func tell(message: AnyMessage)
}

public protocol Actor: ActorRef, ActorRefFactory {
    associatedtype ParamType

    init(_ param: ParamType)

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
        return context.name
    }

    var path: String {
        return context.path
    }

    var system: ActorSystem {
        return context.system
    }

    func parent() -> ActorRef? {
        return context.parent
    }

    func stop() {
        context.stop()
    }

    func tell(message: SystemMessage) {
        context.tell(message: message)
    }

    func tell(message: AnyMessage) {
        context.tell(message: message)
    }

    @discardableResult
    func spawn<T>(_ props: Props<T>, name: String) -> ActorRef where T: Actor {
        return context.spawn(props, name: name)
    }
}

infix operator ! : AssignmentPrecedence

public func ! (lhs: ActorRef, rhs: AnyMessage) {
    lhs.tell(message: rhs)
}

public func ! (lhs: ActorRef, rhs: SystemMessage) {
    lhs.tell(message: rhs)
}
