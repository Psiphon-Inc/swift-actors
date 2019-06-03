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

enum ActorErrors: Error {
    
    /// Unhandled message error.
    case unhandled(message: String)
    
    /// Actor response timeout error.
    case timeout(message: String)
}

public enum Receive<T> {
    case new((T) throws -> Receive)
    case same
    case stop
}

enum MessageKind {
    case system(message: SystemMessage)
    case user(message: AnyMessage)
}

/// Wraps a message sent to an actor with its context.
internal struct MessageContext {
    
    let message: MessageKind
    
    /// This field is not an optional since only actors can send messages to other actors.
    let sender: ActorRef?
}

enum ActorState: Int, Ordinal {
    case spawned = 1
    case started
    case stopping
    case stopped
}

public class ActorContext<MessageType> where MessageType: AnyMessage {
    
    public let name: String
    
    unowned var parent: ActorRef?
    
    internal let mailbox: Mailbox<MessageContext>
    internal let dispatch: PriorityDispatch
    
    internal let waitGroup: DispatchGroup
    
    internal var currentMessageContext: MessageContext?
    
    internal var children: [String: ActorRef]
    
    internal var behavior: ((MessageType) throws -> Receive<MessageType>)?
    
    internal var state: ActorState
    
    unowned var actorRef: ActorRef
    
    public init<T>(name: String, actor: T, parent: ActorRef? = nil) where T: Actor, T.MessageType == MessageType {
        self.name = name
        self.parent = parent
        actorRef = actor
        mailbox = Mailbox(name: name)
        dispatch = PriorityDispatch(name: name)
        waitGroup = DispatchGroup()
        currentMessageContext = nil
        children = [String: ActorRef]()
        behavior = actor.behavior
        state = .spawned
    }
    
}

class RootActor: Actor {
    
    typealias MessageType = MT
    
    enum MT: AnyMessage {
    }
    
    var context: ActorContext<MT>!
    
    var behavior = { (msg: MT) throws -> Receive<MT> in
        // Do nothing for now.
        return Receive.same
    }
    
}

public protocol ActorRef: class {
    
    var name: String { get }
    
    func stop()
    
    func stop(_ child: ActorRef)
    
}

internal extension ActorRef {
    
    func onChildStopped(child: ActorRef) {}
    
}

public protocol Actor: ActorRef, MailboxOwner, Hashable {
    
    associatedtype MessageType: AnyMessage
    
    typealias Behavior = (MessageType) throws -> Receive<MessageType>
    
    var context: ActorContext<MessageType>! { get set }
    
    var behavior: Behavior { get }
    
    /// Lifecycle method called before actor starts processing messages.
    func preStart()
    
    /// Lifecycle method called after an actor has been stopped.
    func postStop()
    
}

public extension Actor {
    
    func preStart() {}
    
    func postStop() {}
    
}

// ActorRef
public extension Actor {
    
    var name: String {
        get { return context.name }
    }
    
    func stop() {
        context.dispatch.asyncHighPriority {
            
            // Returns if already stopping.
            guard self.context.state < .stopping else {
                return
            }
            
            self.context.state = .stopping
            
            self.context.children.forEach { (key: String, child: ActorRef) in
                self.context.waitGroup.enter()
                child.stop()
            }
            
            self.context.waitGroup.notify(queue: self.context.dispatch.highPriorityDispatch) {
                precondition(self.context.children.isEmpty, "actor children set is not empty")
                self.postStop()
                self.context.state = .stopped
                self.context.parent?.onChildStopped(child: self)
            }
        }
    }
    
    func stop(_ child: ActorRef) {
        context.dispatch.asyncHighPriority {
            guard self.context.children.keys.contains(child.name) else {
                preconditionFailure("actor '\(child.name)' cannot be stopped since it is not direct descendent of this actor")
            }
            
            child.stop()
        }
    }
    
    
    internal func onChildStopped(child: ActorRef) {
        context.dispatch.asyncHighPriority {
            self.context.children.removeValue(forKey: child.name)
            if self.context.state == .stopped {
                self.context.waitGroup.leave()
            }
        }
    }
    
}

public extension Actor {
    
    func tell(message: MessageType) {
        enqueueMessage(message: .user(message: message), from: nil)
    }
    
    func tell(message: SystemMessage) {
        enqueueMessage(message: .system(message: message), from: nil)
    }
    
}

public extension Actor {
    
    func spawn<T>(name: String, actor childActor: T) -> T where T: Actor {
        let childCtx = ActorContext(name: name, actor: childActor, parent: self)
        childActor.bind(context: childCtx)
        
        context.dispatch.async {
            // An actor can only spawn children if not already stopping.
            // This satisfies the invariant that the children of a stopped actor should all be stopped.
            guard self.context.state < .stopping else {
                return
            }
            
            // Checks if a child actor with the same name already exists before adding it.
            let childName = childActor.context.name
            if self.context.children.keys.contains(childName) {
                preconditionFailure("child actor \(childName) is not unique")
            }
            self.context.children[childName] = childActor
            childActor.start()
        }
        return childActor
    }
    
}

// MailboxOwner
public extension Actor {
    
    func newMessage() {
        context.dispatch.async {
            
            guard self.context.state == .started else {
                return
            }
            
            guard let behavior = self.context.behavior else {
                preconditionFailure("context behavior is not set")
            }
            
            guard let msgContext = self.context.mailbox.dequeue() else {
                // Mailbox is empty.
                return
            }
            
            self.context.currentMessageContext = msgContext  // Set the new context
            defer {
                self.context.currentMessageContext = nil
            }
            
            switch msgContext.message {
            case .system(let sysMessage):
                
                switch sysMessage {
                case .poisonPill:
                    self.stop()
                }
                
            case .user(let message):
                do {
                    switch try behavior(message as! MessageType) {
                    case .new(let newBehavior):
                        self.context.behavior = newBehavior
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

/// Hashable
public extension Actor {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.context.name == rhs.context.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(context.name.hashValue)
    }
    
}

// Non-customizable functions
extension Actor {
    
    internal func bind(context: ActorContext<MessageType>) {
        guard self.context == nil else {
            preconditionFailure("actor '\(self.context.name)' already bound to a context")
        }
        self.context = context
    }
    
    internal func start() {
        context.dispatch.asyncHighPriority {
            guard self.context.state == .spawned else {
                preconditionFailure("context state '\(self.context.state)' is not 'spawned'")
            }
            self.preStart()
            self.context.state = .started
            
            self.context.mailbox.setOwner(self)
        }
    }
    
    /// Sends a message to actor referenced by self, setting sender to from actor.
    public func tell(message: MessageType, from actor: ActorRef) {
        enqueueMessage(message: .user(message: message), from: actor)
    }
    
    internal func enqueueMessage(message: MessageKind, from actor: ActorRef?) {
        let msgContext = MessageContext(message: message, sender: actor)
        context.mailbox.enqueue(msgContext)
    }
}
