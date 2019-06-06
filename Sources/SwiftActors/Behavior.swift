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

public enum Receive {
    case new(Behavior)
    case same
    case stop
}

public typealias Behavior = (AnyMessage) throws -> Receive
public typealias ContextBehavior = (AnyMessage, Actor) throws -> Receive

public class BehaviorActor: Actor {
    public var context: ActorContext!
    public lazy var receive: Behavior = { [unowned self] msg throws -> Receive in
        return try self.contextBehavior(msg, self)
    }
    
    private let contextBehavior: (AnyMessage, Actor) throws -> Receive
    private let preStartClosure: ((Actor) -> Void)?
    private let postStopClosure: ((Actor) -> Void)?
    
    public init(behavior: @escaping ContextBehavior,
                preStart: ((Actor) -> Void)? = nil,
                postStop: ((Actor) -> Void)? = nil) {
        
        self.contextBehavior = behavior
        self.preStartClosure = preStart
        self.postStopClosure = postStop
    }
    
    public func preStart() {
        if let callable = preStartClosure {
            callable(self)
        }
    }
    
    public func postStop() {
        if let callable = postStopClosure {
            callable(self)
        }
    }
    
}
