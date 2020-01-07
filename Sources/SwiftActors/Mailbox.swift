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

struct MailBoxStopped: Error {}

protocol MailboxOwner: class {
    var dispatch: PriorityDispatch { get }
    func newMessage()
}

final class Mailbox<T: Message> {
    private weak var owner: MailboxOwner?
    private let mailboxDispatch: PriorityDispatch
    private var queue: Queue<T>
    internal var stopped: Bool // TODO: make access control private
    private var suspendCount = 0

    init(label: String, qos: DispatchQoS.QoSClass) {
        mailboxDispatch = PriorityDispatch(label: "\(label)$mailbox", qos: qos)
        queue = Queue()
        stopped = false
    }

    func setOwner(_ owner: MailboxOwner) {
        precondition(self.owner == nil, "mailbox already has an owner")
        mailboxDispatch.async {
            self.owner = owner
            self.suspendCount = 0
            self.owner?.newMessage()
        }
    }

    /// - Note: Messages are dropped after the mailbox is stopped.
    /// - Important: Message promises are rejected.
    func enqueue(_ message: T) {
        mailboxDispatch.async {
            precondition(self.suspendCount == 0 || self.suspendCount == 1,
                         "suspend count is \(self.suspendCount)")

            // Rejects message promise if mailbox is stopped.
            guard !self.stopped else {
                message.promise?.reject(MailBoxStopped())
                return
            }

            self.queue.enqueue(message)

            // If the queue count is exactly 1, then resumes the dispatch queue.
            if self.queue.count == 1 && self.suspendCount == 1 {
                self.owner?.dispatch.defaultPriorityDispatch.resume()
                self.suspendCount -= 1
            }
        }
    }

    func dequeue() -> T? {
        return mailboxDispatch.syncHighPriority(execute: { () -> T? in
            precondition(self.suspendCount == 0, "suspend count is \(self.suspendCount)")

            if self.stopped {
                return nil
            }

            let message = queue.dequeue()

            if self.queue.count == 0 && self.suspendCount == 0 {
                self.owner?.dispatch.defaultPriorityDispatch.suspend()
                self.suspendCount += 1

            }

            // Unconditionally sends notify message.
            self.owner?.newMessage()

            return message
        })
    }

    /// Returns number of messages in the mailbox at this point in time.
    func count() -> Int {
        return mailboxDispatch.syncHighPriority(execute: { () -> Int in
            return queue.count
        })
    }

    /// Async function that terminates the mailbox.
    /// Any messages sent after this call will not be queued.
    func stop() {
        mailboxDispatch.async {
            self.stopped = true

            // Rejects all messages with promises.
            while let message = self.queue.dequeue() {
                message.promise?.reject(MailBoxStopped())
            }

        }
    }

}

