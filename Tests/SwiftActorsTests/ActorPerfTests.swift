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
@testable import SwiftActors

class ActorPerfTests: XCTestCase {

    var system: ActorSystem!

    override func setUp() {
        system = ActorSystem(name: "system")
    }

    override func tearDown() {
        system.stop()
        system = nil
    }

    // Trying to estimate overhead of waiting on fulfilled expectations.
    // Validity of subtracting the result of this test from `testMessageSendPerf` is TBD.
    func testFullfillTime() {
        let testExpectations = makeExpectations(t: self, count: 10)
        var i = 0
        self.measure {
            testExpectations[i].fulfill()
            wait(for: [testExpectations[i]], timeout: 1)
            i += 1
        }
    }

    func testMessageSendPerf() {
        // Arrange
        class MultipleMsg: Actor {
            typealias ParamType = [XCTestExpectation]

            let expects: [XCTestExpectation]
            var context: ActorContext!

            lazy var receive = behavior { [unowned self] msg -> Receive in
                guard let msg = msg as? Int else {
                    XCTFail()
                    return .same
                }
                self.expects[msg].fulfill()
                return .same
            }

            required init(_ param: [XCTestExpectation]) {
                self.expects = param
            }
        }

        let expects = [ expectation(description: "0"),
                        expectation(description: "1"),
                        expectation(description: "2"),
                        expectation(description: "3"),
                        expectation(description: "4"),
                        expectation(description: "5"),
                        expectation(description: "6"),
                        expectation(description: "7"),
                        expectation(description: "8"),
                        expectation(description: "9") ]

        // Act
        let actor = system.spawn(Props(MultipleMsg.self, param: expects), name: "multiple")
        var i = 0

        self.measure {
            actor.tell(message: i)
            wait(for: [expects[i]], timeout: 1)  // Assert
            i += 1
        }
    }

    func testMessageSendPerf2() {
        // Arrange
        enum Action: AnyMessage {
            case reset
            case increment
            case done(XCTestExpectation)
        }
        class MultipleMsg: Actor {
            typealias ParamType = Void

            var context: ActorContext!
            var count = 0

            lazy var receive = behavior { [unowned self] msg -> Receive in
                switch msg as! Action {
                case .reset:
                    self.count = 0
                case .increment:
                    self.count += 1
                case .done(let expect):
                    expect.fulfill()
                }
                return .same
            }

            required init(_ param: Void) {}
        }

        // Act
        let actor = system.spawn(Props(MultipleMsg.self, param:(), qos: .userInteractive), name: "multiple")

        self.measure {
            let count = 10_000

            actor ! Action.reset
            for _ in 1...count {
                actor ! Action.increment
            }

            let doneExpectation = expectation(description: "done")
            actor ! Action.done(doneExpectation)
            wait(for: [doneExpectation], timeout: 10)
            XCTAssert((actor as! MultipleMsg).count == count, "received \((actor as! MultipleMsg).count)")
        }
        print("done")
    }

}

