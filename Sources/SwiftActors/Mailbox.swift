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
import SwiftAtomics

protocol MailboxOwner: class {
    var dispatch: PriorityDispatch { get }
    func newMessage()
}

final class Mailbox<T> {
    
    // TODO! this has to be turned atomic
    weak var owner: MailboxOwner?
    let queue: MPSCLockFreeQueue<T>
    var stopped = AtomicBool()
    
    var suspendCount = AtomicInt(0)
    
    init(label: String) {
        queue = MPSCLockFreeQueue()
        stopped.initialize(false)
    }
    
    func setOwner(_ owner: MailboxOwner) {
        precondition(self.owner == nil, "mailbox already has an owner")
//        mailboxDispatch.async {
        self.owner = owner
        suspendCount.store(0)
        
        self.owner?.newMessage()
    }
    
    /// - Note: Messages are dropped after the mailbox is stopped.
    func enqueue(_ item: T) {
//        precondition(self.suspendCount == 0 || self.suspendCount == 1, "suspend count is \(self.suspendCount)")
        
        if stopped.value == true {
            // TODO: maybe send the message somewhere else.
            return
        }
        
        self.queue.enqueue(item)
        
        // If the queue count is exactly 1, then resumes the dispatch queue.
        if self.queue.count == 1 && suspendCount.value == 1 {
            self.owner?.dispatch.defaultPriorityDispatch.resume()
            suspendCount.decrement()
//            self.suspendCount -= 1
        }
    }
    
    /// - Returns: nil when mailbox is stopped.
    func dequeue() -> T? {
//        return mailboxDispatch.syncHighPriority(execute: { () -> T? in
//            precondition(self.suspendCount == 0, "suspend count is \(self.suspendCount)")
        
            if stopped.value == true {
                return nil
            }
            
            let message = queue.dequeue()
            
            if queue.count == 0 && suspendCount.value == 0 {
                self.owner?.dispatch.defaultPriorityDispatch.suspend()
                self.suspendCount.increment()
            }
            
            // Unconditionally sends notify message.
            self.owner?.newMessage()
            
            return message
//        })
    }
    
    /// Returns number of messages in the mailbox at this point in time.
    func count() -> Int {
        return queue.count
    }
    
    /// Async function that terminates the mailbox.
    /// Any messages sent after this call will not be queued.
    func stop() {
        stopped.store(true)
    }
    
}
