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
    let sender: Actor?
}

enum ActorState: Int, Ordinal {
    case spawned = 1
    case started
    case stopping
    case stopped
}

public protocol ActorContext: class {
    
    var name: String { get }
    
    var parent: Actor? { get }
    
    var children: [String: Actor] { get }
    
    var system: ActorSystem { get }
    
    func sender() -> Actor?
    
    func start()
    
    func stop()
    
    func stop(child: Actor)
    
    @discardableResult func spawn<T>(name: String, actor childActor: T) -> T where T: Actor
    
    func unhandled() throws
    
    /// TODO: functions below are internal. Maybe create a separate internal context protocol.
    
    func onChildStopped(child: Actor)
    
    func enqueueMessage(message: MessageKind, from actor: Actor?)
    
}

public class LocalActorContext: ActorContext {
    
    public let name: String
    public var parent: Actor?
    public var children: [String: Actor]
    public unowned var system: ActorSystem
    
    internal let mailbox: Mailbox<MessageContext>
    internal let dispatch: PriorityDispatch
    internal let waitGroup: DispatchGroup
    internal var currentMessage: MessageContext?
    internal var behavior: Behavior?
    internal var state: ActorState
    
    var actor: Actor
    
    init(name: String, system: ActorSystem, actor: Actor, parent: Actor? = nil) {
        self.name = name
        self.system = system
        self.parent = parent
        self.actor = actor
        dispatch = PriorityDispatch(name: name)
        waitGroup = DispatchGroup()
        currentMessage = nil
        children = [String: Actor]()
        behavior = actor.receive
        state = .spawned
        mailbox = Mailbox(name: name)
    }
    
    public func sender() -> Actor? {
        return currentMessage?.sender
    }
    
    public func start() {
        dispatch.asyncHighPriority {
            guard self.state == .spawned else {
                print("context state '\(self.state)' is not 'spawned'")
                return
            }
            self.actor.preStart()
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
            
            self.children.forEach { (key: String, child: Actor) in
                self.waitGroup.enter()
                child.stop()
            }
            
            self.waitGroup.notify(queue: self.dispatch.highPriorityDispatch) {
                self.actor.postStop()
                self.state = .stopped
                self.parent?.context.onChildStopped(child: self.actor)
            }
        }
    }
    
    public func stop(child: Actor) {
        dispatch.asyncHighPriority {
            guard self.children.keys.contains(child.name) else {
                preconditionFailure("actor '\(child.name)' cannot be stopped since it is not direct descendent of this actor")
            }
            
            child.stop()
        }
    }
    
    public func spawn<T>(name: String, actor childActor: T) -> T where T: Actor {
        let childCtx = LocalActorContext(name: "\(self.name).\(name)", system: self.system, actor: childActor, parent: self.actor)
        childActor.bind(context: childCtx)
        
        dispatch.asyncHighPriority {
            // An actor can only spawn children if not already stopping.
            // This satisfies the invariant that the children of a stopped actor should all be stopped.
            guard self.state < .stopping else {
                return
            }
            
            // Checks if a child actor with the same name already exists before adding it.
            if self.children.keys.contains(name) {
                preconditionFailure("child actor \(childCtx.name) is not unique")
            }
            self.children[name] = childActor
            childActor.context.start()
        }
        return childActor
    }
    
    /// Can be called by actor's behavior when the message type that it received is not handled.
    public func unhandled() throws {
        throw ActorErrors.unhandled(message:
            "message '\(String(describing: currentMessage!.message))' is not handled by '\(name)'")
    }
    
    public func enqueueMessage(message: MessageKind, from actor: Actor?) {
        let msgContext = MessageContext(message: message, sender: actor)
        mailbox.enqueue(msgContext)
    }
    
    public func onChildStopped(child: Actor) {
        dispatch.asyncHighPriority {
            self.children.removeValue(forKey: child.name)
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
                    switch try behavior(message) {
                    case .new(let newBehavior):
                        self.behavior = newBehavior
                    case .same:
                        break
                    case .stop:
                        self.stop()
                    }
                } catch ActorErrors.unhandled(let message){
                    // TODO Log these with a logger from root actor.
                    print("unhandled! \(message)")
                } catch {
                    // TODO escalate the error to the parent. Let their strategy guide you.
                }
            }
        }
    }    
}
