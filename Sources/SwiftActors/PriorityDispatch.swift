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
    
    init(label: String) {
        highPriorityDispatch = DispatchQueue(label: "\(label)$high", target: DispatchQueue.global())
        defaultPriorityDispatch = DispatchQueue(label: label, target: highPriorityDispatch)
    }
    
    /// Executes `work` with default priority.
    func async(_ work: @escaping () -> Void) {
        defaultPriorityDispatch.async(execute: work)
    }
    
    /// Pauses default priority queue, and executes high priority queue before resuming default priority queue.
    func asyncHighPriority(_ work: @escaping () -> Void) {
        defaultPriorityDispatch.suspend()
        highPriorityDispatch.async {
            work()
            self.defaultPriorityDispatch.resume()
        }
    }
    
}
