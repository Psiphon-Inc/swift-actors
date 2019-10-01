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
import Promises

let echoActorProps = Props(EchoActor.self, param: ())

class EchoActor: Actor {
    typealias ParamType = Void

    enum Action: AnyMessage {
        case respondWithDelay(interval: TimeInterval, value: Int, fulfill: Promise<Int>)
        case string(String, Promise<String>)
        case int(Int, Promise<Int>)
    }

    var context: ActorContext!

    lazy var receive = behavior { [unowned self] in

        guard let msg = $0 as? Action else {
            return .unhandled($0)
        }

        switch msg {

        case .respondWithDelay(let interval, let value, let promise):
            Thread.sleep(forTimeInterval: interval)
            promise.fulfill(value + 1)

        case .string(let value, let promise):
            promise.fulfill(value)

        case .int(let value, let promise):
            promise.fulfill(value + 1)
        }

        return .same
    }

    required init(_ param: Void) {}

}

