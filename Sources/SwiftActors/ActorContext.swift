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

public enum MessageKind {
    case system(message: SystemMessage)
    case user(message: AnyMessage)
}

/// Wraps a message sent to an actor with its context.
struct MessageContext {
    let message: MessageKind
    let sender: ActorRef?
}

enum ActorState: Int, Ordinal {
    case spawned = 1
    case started
    case stopping
    case stopped
}

public protocol ActorContext: ActorRef, ActorRefFactory {
    
    var path: String { get }
    
    var name: String { get }
    
    var parent: ActorContext? { get }
    
    var children: [String: ActorContext] { get }
    
    var system: ActorSystem { get }
    
    func sender() -> ActorRef?
    
    func stop()
    
    func tell(message: MessageKind, from actor: ActorRef?)
    
    @discardableResult
    func spawn<T>(_ props: Props<T>, name: String) -> ActorRef where T: Actor
    
    func unhandled() throws
    
    /// Special messages:
    /// Should ideally be passed in as a high priority message of type `AnyMessage`.
    
    func onChildStopped(child: ActorContext)
    
}

extension ActorContext {
    
    public func tell(message: AnyMessage) {
        tell(message: .user(message: message), from: nil)
    }
    
    public func tell(message: SystemMessage) {
        tell(message: .system(message: message), from: nil)
    }
    
    public func tell(message: AnyMessage, from actor: ActorRef) {
        tell(message: .user(message: message), from: actor)
    }
    
}

public protocol ActorLifecycleContext: ActorContext {
    associatedtype ActorType: Actor
    
    init(name: String, system: ActorSystem, actor: ActorType, parent: ActorContext?)
    
    func start()
    
    func stop(child: ActorRef)
    
}

public class LocalActorContext<ActorType: Actor>: ActorLifecycleContext {
    public typealias ActorType = ActorType
    
    public let path: String
    public let name: String
    public var children: [String: ActorContext]
    public unowned var parent: ActorContext?
    public unowned var system: ActorSystem
    
    var actor: ActorType?
    
    let mailbox: Mailbox<MessageContext>
    let dispatch: PriorityDispatch
    let waitGroup: DispatchGroup
    var currentMessage: MessageContext?
    var behavior: Behavior!
    var state: ActorState
    
    public required init(name: String, system: ActorSystem, actor: ActorType,
                         parent: ActorContext?) {
        
        self.name = name
        if let parent = parent {
            path = "\(parent.path).\(name)"
        } else {
            path = name
        }
        self.system = system
        self.parent = parent
        self.actor = actor
        dispatch = PriorityDispatch(label: self.path)
        waitGroup = DispatchGroup()
        currentMessage = nil
        children = [String: ActorContext]()
        behavior = actor.receive
        state = .spawned
        mailbox = Mailbox(label: name)
    }
    
    public func sender() -> ActorRef? {
        return currentMessage?.sender
    }
    
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
        dispatch.asyncHighPriority {
            
            // Returns if already stopping.
            guard self.state < .stopping else {
                return
            }
            
            self.state = .stopping
            
            // Stop the mailbox
            self.mailbox.stop()
            
            self.children.forEach { _, child in
                self.waitGroup.enter()
                child.stop()
            }
            
            self.waitGroup.notify(queue: self.dispatch.highPriorityDispatch) {
                guard self.children.count == 0 else {
                    preconditionFailure()
                }
                self.actor!.postStop()
                self.actor = .none
                self.state = .stopped
                self.parent?.onChildStopped(child: self)
            }
        }
    }
    
    public func stop(child: ActorRef) {
        dispatch.asyncHighPriority {
            guard let childCtx = self.children[child.name] else {
                preconditionFailure("actor '\(child.name)' cannot be stopped since it is not direct descendent of this actor")
            }
            
            childCtx.stop()
        }
    }
    
    public func spawn<T>(_ props: Props<T>, name: String) -> ActorRef where T : Actor {
        let child = props.cls.init(props.param)
        let childCtx = LocalActorContext<T>(name: name, system: self.system,
                                            actor: child, parent: self)
        child.bind(context: childCtx)
        
        dispatch.asyncHighPriority {
            // An actor can only spawn children if not already stopping.
            // This satisfies the invariant that the children of a stopped actor should all be stopped.
            guard self.state < .stopping else {
                return
            }
            
            // Checks if a child actor with the same name already exists before adding it.
            if self.children.keys.contains(name) {
                preconditionFailure("child actor \(name) is not unique")
            }
            self.children[name] = childCtx
            
            childCtx.start()
        }
        return child
    }
    
    /// Can be called by actor's behavior when the message type that it received is not handled.
    public func unhandled() throws {
        throw ActorErrors.unhandled(message:
            "message '\(String(describing: currentMessage!.message))' is not handled by '\(name)'")
    }
    
    public func tell(message: MessageKind, from actor: ActorRef?) {
        let msgContext = MessageContext(message: message, sender: actor)
        mailbox.enqueue(msgContext)
    }
    
    
    public func onChildStopped(child: ActorContext) {
        dispatch.asyncHighPriority {
            guard self.children.removeValue(forKey: child.name) != nil else {
                preconditionFailure("child actor '\(child.name)' does not exist")
            }
            if self.state == .stopping {
                self.waitGroup.leave()
            }
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
            defer {
                self.currentMessage = nil
            }
            
            switch msgContext.message {
            case .system(let sysMessage):
                
                switch sysMessage {
                case .poisonPill:
                    self.stop()
                }
                
            case .user(let message):
                do {
                    switch try behavior(.unhandled(message)) {
                    case .new(let newBehavior):
                        self.behavior = newBehavior
                    case .same:
                        break
                    case .stop:
                        self.stop()
                    case .unhandled:
                        try self.unhandled()
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
