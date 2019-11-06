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

import XCTest
import Foundation
import SwiftActors

extension XCTestExpectation: AnyMessage {}

let echoActorProps = Props(EchoActor.self, param: ())

class EchoActor: Actor {
    typealias ParamType = Void

    enum Action: AnyMessage {
        case respondWithDelay(interval: TimeInterval, value: Int, sender: ActorRef)
    }

    struct Ping: AnyMessage {
        let value: AnyMessage
        let sender: ActorRef
    }

    var context: ActorContext!

    lazy var receive = behavior { [unowned self] msg -> ActionResult in
        switch msg {
        case let msg as Ping:
            let value = msg.value
            switch value {
            case let value as Int:
                msg.sender ! value + 1
            default:

                msg.sender ! value
            }

        case let action as Action:
            switch action {
            case .respondWithDelay(let delay, let value, let sender):
                Thread.sleep(forTimeInterval: delay)
                sender ! value + 1
            }

        default:
            return .unhandled
        }

        return .same
    }

    required init(_ param: Void) {}

}

