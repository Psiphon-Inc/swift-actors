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
import XCTest
@testable import SwiftActors

class EchoActor: Actor {
    
    enum Action: AnyMessage {
        case respondWithDelay(interval: TimeInterval, value: Int)
    }
    
    var context: ActorContext!
    
    lazy var receive = behavior { [unowned self] msg -> Receive in
        switch msg {
        case let msg as String:
            self.context.sender()!.tell(message: msg)
        case let msg as Int:
            self.context.sender()!.tell(message: msg + 1)
        case let action as Action:
            switch action {
            case .respondWithDelay(let delay, let value):
                Thread.sleep(forTimeInterval: delay)
                self.context.sender()!.tell(message: value + 1)
            }
            
        default:
            self.context.sender()!.tell(message: msg)
        }
        
        return .same
    }
    
}

// Subclasses ActorSystem to fulfill expectation on fatalError instead of panicking.
class TestActorSystem: ActorSystem {
    let expectation: XCTestExpectation
    let expectationTest: (ActorError) -> Bool

    init(name: String,
         expectation: XCTestExpectation,
         expectationTest: @escaping (ActorError) -> Bool) {

        self.expectation = expectation
        self.expectationTest = expectationTest
        super.init(name: name)
    }

    override func fatalError(_ error: ActorError) {
        if expectationTest(error) {
            expectation.fulfill()
        }
    }
}
