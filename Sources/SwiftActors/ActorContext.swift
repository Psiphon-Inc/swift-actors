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

enum ActorState: Int, Ordinal {
    case spawned = 1
    case started
    case stopping
    case stopped
}

public enum MessageKind: Message {
    case system(SystemMessage)
    case message(Message)
    case anyMessage(AnyMessage)

    public var promise: Promise<Any>? {
        switch self {
        case let .system(message):
            return message.promise
        case let .message(message):
            return message.promise
        case .anyMessage(_):
            return nil
        }
    }
}

public protocol ActorContext: ActorRefFactory {

    var path: String { get }

    var name: String { get }

    var children: [String: ActorRef] { get }

    var system: ActorSystem { get }

    func stop()

    func tell(message: MessageKind)

    @discardableResult
    func spawn<T>(_ props: Props<T>, name: String) -> ActorRef where T: Actor

    func unhandled() throws

    func watch(_ child: ActorRef)

    func stash()

    func unstashAll()
}

public protocol ActorLifecycleContext: ActorContext {

    var actorRef: ActorRef? { get }

    func start()

    func stop(child: ActorRef)

    func childStopped(_ child: ActorRef)
}

public protocol ActorTypedContext: ActorLifecycleContext {

    associatedtype ActorType: Actor

    init(name: String, system: ActorSystem, actor: ActorType, parent: ActorLifecycleContext?,
         qos: DispatchQoS.QoSClass)

}

public final class LocalActorContext<ActorType: Actor> {

    /// Wraps a message sent to an actor with its context.
    struct MessageContext: Message {
        let message: MessageKind
        var stashed: Bool = false

        var promise: Promise<Any>? {
            return message.promise
        }
    }

    public let path: String
    public let name: String
    public unowned var system: ActorSystem

    public var actorRef: ActorRef? {
        return actor
    }

    public var children: [String: ActorRef] {
        return childrenContexts.mapValues {
            return $0.actorRef!
        }
    }

    // TODO: make dispatch, state and mailbox private or fileprivate.
    internal let dispatch: PriorityDispatch
    internal var state: ActorState
    internal let mailbox: Mailbox<MessageContext>

    private var childCount = 0
    private var actor: ActorType?
    private let waitGroup: DispatchGroup
    private var currentMessage: MessageContext?
    private var behavior: Behavior!
    private var watchGroup: [ActorRef] = []

    private var childrenContexts = [String: ActorLifecycleContext]()

    // Used internally only.
    private var parentContext: ActorLifecycleContext?

    // Stash
    lazy var stashQueue = Queue<MessageContext>()

    public required init(name: String, system: ActorSystem, actor: ActorType,
                         parent: ActorLifecycleContext?, qos: DispatchQoS.QoSClass = .default) {

        self.name = name
        if let parent = parent {
            path = "\(parent.path).\(name)"
        } else {
            path = name
        }
        self.system = system
        self.parentContext = parent
        self.actor = actor
        self.dispatch = PriorityDispatch(label: self.path, qos: qos)
        waitGroup = DispatchGroup()
        currentMessage = nil
        behavior = actor.receive
        state = .spawned

        /// Mailbox has the same QoS as the actor.
        mailbox = Mailbox(label: name, qos: qos)
    }

    private func stop(_ promise: Promise<()>?) {
        dispatch.asyncHighPriority {

            // Returns if already stopping.
            guard self.state < .stopping else {
                return
            }

            self.state = .stopping

            // Stop the mailbox
            self.mailbox.stop()

            self.childrenContexts.forEach { _, child in
                self.waitGroup.enter()
                child.stop()
            }

            self.waitGroup.notify(queue: self.dispatch.highPriorityDispatch) {
                guard self.childrenContexts.count == 0 else {
                    preconditionFailure()
                }
                self.actor!.postStop()
                self.parentContext?.childStopped(self.actor!)
                self.actor = .none

                self.state = .stopped
                promise?.fulfill(())
            }
        }
    }
}

extension LocalActorContext: ActorTypedContext {

    public func start() {
        dispatch.asyncHighPriority {
            precondition(self.state != .started, "actor '\(self.name)' already started")
            guard self.state == .spawned else {
                return
            }
            self.actor!.preStart()
            self.state = .started

            self.mailbox.setOwner(self)
        }
    }

    public func stop() {
        stop(nil)
    }

    public func stop(child: ActorRef) {
        dispatch.asyncHighPriority {
            guard let childCtx = self.childrenContexts[child.name] else {
                preconditionFailure("actor '\(child.name)' cannot be stopped since it is not direct descendent of this actor")
            }

            childCtx.stop()
        }
    }

    public func spawn<T>(_ props: Props<T>, name: String) -> ActorRef where T : Actor {
        let childId = "\(name)_\(self.childCount)"
        let child = props.cls.init(props.param)
        let childCtx = LocalActorContext<T>(name: childId, system: self.system,
                                            actor: child, parent: self, qos: props.qos)
        child.bind(context: childCtx)

        dispatch.asyncHighPriority {
            // An actor can only spawn children if not already stopping.
            // This satisfies the invariant that the children of a stopped actor should all be stopped.
            guard self.state < .stopping else {
                return
            }

            self.childCount += 1

            // Checks if a child actor with the same name already exists before adding it.
            if self.children.keys.contains(name) {
                preconditionFailure("child actor \(name) is not unique")
            }
            self.childrenContexts[childId] = childCtx

            childCtx.start()
        }
        return child
    }

    /// Can be called by actor's behavior when the message type that it received is not handled.
    public func unhandled() throws {
        throw ActorErrors.unhandled(message:
            "message '\(String(describing: currentMessage!.message))' is not handled by '\(name)'")
    }

    public func tell(message: MessageKind) {
        let msgContext = MessageContext(message: message)
        mailbox.enqueue(msgContext)
    }

    public func childStopped(_ child: ActorRef) {
        dispatch.asyncHighPriority {
            guard self.childrenContexts.removeValue(forKey: child.name) != nil else {
                preconditionFailure("child actor '\(child.name)' does not exist")
            }

            // If child is part of the watch group, send message to self.
            let watchedChildInd = self.watchGroup.firstIndex { $0 === child }

            if let index = watchedChildInd {
                self.watchGroup.remove(at: index)

                self.tell(message: .anyMessage(NotificationMessage.terminated(actor: child)))
            }

            if self.state == .stopping {
                self.waitGroup.leave()
            }
        }
    }

    public func watch(_ child: ActorRef) {
        dispatch.asyncHighPriority {
            guard self.childrenContexts.keys.contains(child.name) else {
                preconditionFailure("actor \(child.name) is not a a child of \(self.path)")
            }

            let alreadyWatched = self.watchGroup.contains { $0 === child }

            guard !alreadyWatched else {
                return
            }

            self.watchGroup.append(child)
        }
    }


    public func stash() {
        guard let msgCtx = currentMessage else {
            fatalError("current message context is not set")
        }

        guard msgCtx.stashed == false else {
            fatalError("message is already stashed")
        }

        stashQueue.enqueue(msgCtx)
        self.currentMessage!.stashed = true
    }

    public func unstashAll() {
        while let msgCtx = stashQueue.dequeue() {
            self.tell(message: msgCtx.message)
        }
    }

}

extension LocalActorContext: MailboxOwner {

    public func newMessage() {
        dispatch.async {
            guard self.state == .started else {
                return
            }

            guard let behavior = self.behavior else {
                preconditionFailure("context behavior is not set")
            }

            guard let msgContext = self.mailbox.dequeue() else {
                // Mailbox is empty.
                return
            }

            self.currentMessage = msgContext  // Set the new context

            switch msgContext.message {
            case .system(let sysMessage):

                switch sysMessage {
                case .poisonPill(let promise):
                    self.stop(promise)
                }

            case .message(let message), .anyMessage(let message as Message):
                do {
                    switch try behavior(.unhandled(message, .none)) {
                    case .unhandled(_, _):
                        try self.unhandled()
                    case .handled(_, let behavior):
                        self.behavior = behavior
                    }
                } catch ActorErrors.unhandled(let message){
                    // TODO Log these with a logger from root actor.
                    self.system.fatalError("Unhandled! \(message)")
                } catch {
                    // TODO escalate the error to the parent. Let their strategy guide you.
                    preconditionFailure("Unexpected error \(error)")
                }
            }
        }
    }

}

