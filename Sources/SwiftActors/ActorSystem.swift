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
    
    var receive: Behavior = { msg throws -> Receive in
        // Do nothing for now.
        return Receive.same
    }
    
}

public class ActorSystem {
    
    let name: String
    private let root: Actor!
    private let dispatch: DispatchQueue
    private var uid = UInt32(0)
    
    public init(name: String, root: Actor) {
        dispatch = DispatchQueue(label: "\(name)$dispatch", target: DispatchQueue.global())
        self.name = name
        self.root = root
        self.root.bind(context: LocalActorContext(name: name, system: self, actor: root))
        self.root.context.start()
    }
    
    /// A reverse-DNS naming style (e.g. "com.example") is recommended. All actors within this
    /// actor system will be prefixed with this label.
    public convenience init(name: String) {
        self.init(name: name, root: RootActor())
    }
    
    @discardableResult
    public func spawn<T: Actor>(name: String, actor: T) -> T {
        return root.context.spawn(name: name, actor: actor)
    }
    
    public func stop() {
        root.stop()
    }
    
    public func newActorUID() -> UInt32 {
        return dispatch.sync { () -> UInt32 in
            (uid, _) = uid.addingReportingOverflow(1)
            return uid
        }
    }
}
