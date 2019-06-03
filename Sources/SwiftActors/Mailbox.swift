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

public protocol MailboxOwner: class {
    func newMessage()
}

public final class Mailbox<T> {
    
    weak var owner: MailboxOwner?
    let mailboxDispatch: DispatchQueue
    var queue: Queue<T>
    var stopped: Bool
    
    init(name: String) {
        mailboxDispatch = DispatchQueue(label: "\(name)$mailbox", target: DispatchQueue.global())
        queue = Queue(capacity: 5)
        stopped = false
    }
    
    func setOwner(_ owner: MailboxOwner) {
        mailboxDispatch.async {
            self.owner = owner
            self.notifyOwner()
        }
    }
    
    private func notifyOwner() {
        mailboxDispatch.async {
            if let owner = self.owner {
                for _ in 0...self.queue.count {
                    owner.newMessage()
                }
            }
        }
    }
    
    /// - Note: Messages are dropped after the mailbox is stopped.
    func enqueue(_ item: T) {
        mailboxDispatch.async {
            
            if self.stopped {
                // TODO: maybe send the message somewhere else.
                return
            }
            
            self.queue.enqueue(item)
            self.notifyOwner()
        }
    }
    
    /// - Returns: nil when mailbox is stopped.
    func dequeue() -> T? {
        return mailboxDispatch.sync(execute: { () -> T? in
            
            if self.stopped {
                return nil
            }
            
            return queue.dequeue()
        })
    }
    
    /// Returns number of messages in the mailbox at this point in time.
    func count() -> Int {
        return mailboxDispatch.sync(execute: { () -> Int in
            return queue.count
        })
    }
    
    /// Async function that terminates the mailbox.
    /// Any messages sent after this call will not be queued.
    func stop() {
        mailboxDispatch.async {
            self.stopped = true
        }
    }
    
}
