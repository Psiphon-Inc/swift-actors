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

public final class PriorityDispatch {

    let defaultPriorityDispatch: DispatchQueue
    let highPriorityDispatch: DispatchQueue

    init(label: String, qos: DispatchQoS.QoSClass) {
        highPriorityDispatch = DispatchQueue(label: "\(label)$high",
            target: DispatchQueue.global(qos: qos))
        defaultPriorityDispatch = DispatchQueue(label: label, target: highPriorityDispatch)
    }

    /// Executes `work` synchronously with default priority.
    /// - Note: Calling this function and targeting the current queue results in a deadlock.
    func sync<T>(execute work: () -> T) -> T {
        return defaultPriorityDispatch.sync(execute: work)
    }

    /// Pauses default priority queue, and synchronously executes `work` on high priority queue
    /// before resuming default priority queue.
    /// - Note: Calling this function and targeting the current queue results in a deadlock.
    func syncHighPriority<T>(execute work: () -> T) -> T {
        defaultPriorityDispatch.suspend()
        return highPriorityDispatch.sync {
            let result = work()
            self.defaultPriorityDispatch.resume()
            return result
        }
    }

    /// Executes `work` asynchronously with default priority.
    func async(_ work: @escaping () -> Void) {
        defaultPriorityDispatch.async(execute: work)
    }

    /// Pauses default priority queue, and asynchronously executes `work` on high priority queue
    /// before resuming default priority queue.
    func asyncHighPriority(_ work: @escaping () -> Void) {
        defaultPriorityDispatch.suspend()
        highPriorityDispatch.async {
            work()
            self.defaultPriorityDispatch.resume()
        }
    }

}

