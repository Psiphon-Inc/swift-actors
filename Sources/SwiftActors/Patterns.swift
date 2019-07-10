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
import Promises

fileprivate enum Ask: AnyMessage {
    case timeout
}

infix operator ?!

public func ?! (lhs: Actor, rhs: AnyMessage) -> Promise<Any> {
    return ask(actor: lhs, message: rhs)
}

public func ?! (lhs: Actor, rhs: (message: AnyMessage, timeoutMillis: Int)) -> Promise<Any> {
    return ask(actor: lhs, message: rhs.message, timeoutMillis: rhs.timeoutMillis)
}

public func ask(actor: Actor, message: AnyMessage, timeoutMillis: Int = 5000) -> Promise<Any> {
    let uid = actor.context.system.newActorUID()
    let promise = Promise<Any>.pending()
    let timer = DispatchSource.makeTimerSource()
    timer.schedule(deadline: .now() + DispatchTimeInterval.milliseconds(timeoutMillis))
    
    _ = actor.context.system.spawn(name: "ask.\(actor.name).\(uid)",
        actor: BehaviorActor(behavior: { msg, ctx throws -> Receive in
            
            defer {
                timer.cancel()
                ctx.stop()
            }
            
            // On timeout rejects promise, otherwise the promise is fulfilled.
            if let msg = msg as? Ask {
                switch msg {
                case .timeout:
                    promise.reject(ActorErrors.timeout(message:
                        "ask timed out waiting on '\(actor.name)' for message '\(String.init(describing: message))'"))
                }
            } else {
                promise.fulfill(msg)
            }
            
            return .stop
        }, preStart: { ctx in
            // TODO This is fired on some background queue. For less resource waste we can fire this on mailbox dispatch queue.
            timer.setEventHandler { [unowned ctx] in
                ctx.tell(message: Ask.timeout, from: ctx)
            }
            timer.resume()
            
            // Sends message after activating the timer to ensure that timer doesn't get cancelled
            // before getting activated. Although this is highly unlikely.
            actor.tell(message: message, from: ctx)
        }))
    
    return promise
}
