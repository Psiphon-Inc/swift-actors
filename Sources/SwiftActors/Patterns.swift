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

public func ?! (lhs: ActorRef, rhs: AnyMessage) -> Promise<Any> {
    return ask(actor: lhs, message: rhs)
}

public func ?! (lhs: ActorRef, rhs: (message: AnyMessage, timeoutMillis: Int)) -> Promise<Any> {
    return ask(actor: lhs, message: rhs.message, timeoutMillis: rhs.timeoutMillis)
}

struct AskActorParam {
    let promise: Promise<Any>
    let timer: DispatchSourceTimer
    let message: AnyMessage
    let receiver: ActorRef
}

final class AskActor: Actor {
    typealias ParamType = AskActorParam

    var context: ActorContext!
    private let params: AskActorParam

    lazy var receive = behavior { [unowned self] in
        defer {
            self.params.timer.cancel()
        }

        // On timeout rejects promise, otherwise the promise is fulfilled.
        if let msg = $0 as? Ask {
            switch msg {
            case .timeout:
                self.params.promise.reject(ActorErrors.timeout(message:
                    "ask timed out waiting on '\(self.params.receiver.name)' for "
                        + "message '\(String.init(describing: self.params.message))'"))
            }
        } else {
            self.params.promise.fulfill($0)
        }

        return .stop
    }

    required init(_ param: AskActorParam) {
        self.params = param
    }

    func preStart() {
        // TODO This is fired on some background queue. For less resource waste we can fire this on mailbox dispatch queue.
        params.timer.setEventHandler { [unowned self] in
            self ! Ask.timeout
        }
        params.timer.resume()

        // Sends message after activating the timer to ensure that timer doesn't get cancelled
        // before getting activated. Although this is highly unlikely.
        params.receiver ! (params.message, self)
    }
}

public func ask(actor: ActorRef, message: AnyMessage, timeoutMillis: Int = 5000) -> Promise<Any> {
    let uid = actor.system.newActorUID()
    let promise = Promise<Any>.pending()
    let timer = DispatchSource.makeTimerSource()
    timer.schedule(deadline: .now() + DispatchTimeInterval.milliseconds(timeoutMillis))


    let props = Props(AskActor.self,
                      param: AskActorParam(promise: promise, timer: timer,
                                            message: message, receiver: actor))

    actor.system.spawn(props, name: "ask.\(actor.name).\(uid)")

    return promise
}

