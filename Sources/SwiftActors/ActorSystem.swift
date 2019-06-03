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

public class ActorSystem {
    
    let name: String
    private let root: RootActor!
    private let dispatch: DispatchQueue
    private var uid = UInt32(0)
    
    public init(name: String) {
        self.name = name
        dispatch = DispatchQueue(label: "\(name).dispatch", target: DispatchQueue.global())
        root = RootActor()
        root.bind(context: ActorContext(name: "root", actor: root))
        root.start()
    }
    
    @discardableResult
    public func spawn<T: Actor>(name: String, actor: T) -> T {
        return root.spawn(name: name, actor: actor)
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
