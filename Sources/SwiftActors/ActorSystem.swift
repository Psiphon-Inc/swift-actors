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

public class RootActor: Actor {
    public typealias ParamType = Void
    
    public var context: ActorContext!
    
    var stopGroup: DispatchGroup?
    
    public required init(_ param: Void) {}
    
    public lazy var receive = behavior { [unowned self] msg -> Receive in
        return .same
    }
    
    func stop(inGroup: DispatchGroup) {
        stopGroup = inGroup
        stopGroup?.enter()
        stop()
    }
    
    public func postStop() {
        stopGroup?.leave()
    }
    
}

/// ActorSystem
public class ActorSystem: ActorRefFactory {
    
    let name: String
    private var root: RootActor!
    private let dispatch: DispatchQueue
    private var uid = UInt32(0)
    
    /// A reverse-DNS naming style (e.g. "com.example") is recommended. All actors within this
    /// actor system will be prefixed with this label.
    public init<T: ActorTypedContext>(name: String, contextType: T.Type) where T.ActorType == RootActor {
        dispatch = DispatchQueue(label: "\(name)$dispatch", target: DispatchQueue.global())
        self.name = name
        self.root = RootActor(())
        let rootContext = contextType.init(name: name, system: self, actor: root, parent: nil)
        self.root.bind(context: rootContext)
        
        rootContext.start()
    }
    
    public convenience init(name: String) {
        self.init(name: name, contextType: LocalActorContext.self)
    }
    
    @discardableResult
    public func spawn<T>(_ props: Props<T>, name: String) -> ActorRef where T: Actor {
        return root.spawn(props, name: name)
    }
    
    /// Stop blocks until all actors in the sytem have stopped.
    public func stop() {
        let stopGroup = DispatchGroup()
        root.stop(inGroup: stopGroup)
        stopGroup.wait()
    }
    
    public func newActorUID() -> UInt32 {
        return dispatch.sync { () -> UInt32 in
            (uid, _) = uid.addingReportingOverflow(1)
            return uid
        }
    }
    
    func fatalError(_ message: String) {
        preconditionFailure(message)
    }
    
}
