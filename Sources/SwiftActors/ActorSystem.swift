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

class RootActor: Actor {
    var context: ActorContext!
    
    var stopGroup: DispatchGroup?
    
    lazy var receive: Behavior = { [unowned self] msg -> Receive in
        return .same
    }
    
    func stop(inGroup: DispatchGroup) {
        stopGroup = inGroup
        stopGroup?.enter()
        stop()
    }
    
    func postStop() {
        stopGroup?.leave()
    }
    
}

/// ActorSystem
public class ActorSystem {
    
    let name: String
    private var root: RootActor!
    private let dispatch: DispatchQueue
    private var uid = UInt32(0)
    
    /// A reverse-DNS naming style (e.g. "com.example") is recommended. All actors within this
    /// actor system will be prefixed with this label.
    public init(name: String) {
        dispatch = DispatchQueue(label: "\(name)$dispatch", target: DispatchQueue.global())
        self.name = name
        self.root = RootActor()
        self.root.bind(context: LocalActorContext(name: name, parentPath: "", system: self, actor: root))
        self.root.context.start()
    }
    
    @discardableResult
    public func spawn<T: Actor>(name: String, actor: T) -> T {
        return root.context.spawn(name: name, actor: actor)
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
    
}
