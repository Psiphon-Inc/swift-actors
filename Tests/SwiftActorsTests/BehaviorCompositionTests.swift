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

enum ABCAction: AnyMessage  {
    case A, B, C
}

class BehaviorCompositionTests: XCTestCase {

    var system: ActorSystem!

    override func setUp() {
        system = ActorSystem(name: "system")
    }

    override func tearDown() {
        system.stop()
        system = nil
    }

    func testComposingTwoBehaviors() {

        // Arrange
        class TestActor: Actor {
            var context: ActorContext!
            let doneExpectation: XCTestExpectation
            var counter = 0

            lazy var set10: Behavior = behavior { [unowned self] msg -> ActionResult in
                switch msg {
                case let msg as String:

                    if msg == "set10" {
                        self.counter = 10
                        return .new(self.increment <| self.decrement)
                    } else {
                        return .same
                    }

                default:
                    XCTFail()
                }
                return .unhandled
            }

            lazy var increment: Behavior = behavior { [unowned self] msg -> ActionResult in
                switch msg {
                case let msg as String:

                    if msg == "increment" {
                        self.counter += 1

                        if self.counter == 11 {
                            return .new(self.done)
                        } else {
                            return .new(self.increment <| self.decrement)
                        }
                    } else {
                        return .same
                    }

                default:
                    XCTFail()
                }
                return .unhandled
            }

            lazy var decrement = behavior { [unowned self] msg -> ActionResult in
                switch msg {
                case let msg as String:

                    if msg == "decrement" {
                        self.counter -= 1
                        return .new(self.increment)
                    } else {
                        return .unhandled
                    }

                default:
                    XCTFail()
                }
                return .unhandled
            }

            lazy var done = behavior { [unowned self] msg -> ActionResult in
                let msg = msg as! String
                if msg == "done" {
                    self.doneExpectation.fulfill()
                    return .same
                } else {
                    XCTFail()
                    return .unhandled
                }
            }

            lazy var receive = self.set10 <| self.decrement

            required init(_ param: XCTestExpectation) {
                self.doneExpectation = param
            }
        }

        let expect = expectation(description: "doneExpectation")
        let testActor = system.spawn(Props(TestActor.self, param: expect),
                                     name: "testBehaviorComposition")

        // Act
        testActor ! "set10"      // counter is 10 (accepts next message: "increment", "decrement")
        testActor ! "decrement"  // counter is 9  (accepts next message: "increment")
        testActor ! "decrement"  // counter is 9  (message dropped)
        testActor ! "set10"      // counter is 9  (message dropped)
        testActor ! "increment"  // counter is 10 (accepts next message: "increment", "decrement")
        testActor ! "decrement"  // counter is 9  (accepts next message: "increment")
        testActor ! "decrement"  // counter is 9  (message dropped)
        testActor ! "increment"  // counter is 10 (accepts next message: "increment", "decrement")
        testActor ! "increment"  // counter is 11 (accepts next message only: "done")
        testActor ! "done"       // counter is 11

        // Assert
        wait(for: [expect], timeout: 1)
        XCTAssert((testActor as! TestActor).counter == 11)
    }

    /// Tests right associativity of behavior composition.
    func testAssociativity() {

        // Arrange
        class AssocActor: Actor {
            var context: ActorContext!
            var result = [ABCAction]()
            let expect: XCTestExpectation

            // Appends to messages if A, otherwise drops the message.
            lazy var behaviorA = ABCAction.be { [unowned self] _ in
                self.result.append(.A)
                return .same
            }

            // Appends to messages if B, otherwise drops the message.
            lazy var behaviorB = ABCAction.be { [unowned self] _ in
                self.result.append(.B)
                return .unhandled
            }

            // Appends to messages if C, otherwise drops the message.
            lazy var behaviorC = ABCAction.be { [unowned self] _ in
                self.result.append(.C)
                return .unhandled
            }

            lazy var receive = self.behaviorA <| self.behaviorB <| self.behaviorC

            required init(_ param: XCTestExpectation) {
                self.expect = param
            }

            func postStop() {
                expect.fulfill()
            }
        }

        let expect = expectation(description: "poisoned")
        let props = Props(AssocActor.self, param: expect)
        let actor = system.spawn(props, name: "\(#function)Actor")

        // Act
        actor ! ABCAction.A

        // Assert
        actor ! .poisonPill
        wait(for: [expect], timeout: 1)

        let result = (actor as! AssocActor).result

        // If composition was left associative, we would expevect behaviorA to get called first (which returns `.same`)
        // So the result would have been `[.A]`.
        XCTAssert(result == [.C, .B, .A], "got '\(result)'")
    }


    /// Tests the condition when a behavior - that is situated in the middle of behavior composition - returns a new behavior after handling a message,
    /// that was not processed by the behavior above it.
    func testMiddleBehaviorSwitching() {

        // Arrange

        /// Initially the actors behavior is `behaviorA <| behaviorB <| behaviorC`
        /// After receiving message `.B`, the next behavior should be `behaviorA <| newBehaviorB <| behaviorC`
        class AssocActor: Actor {
            var context: ActorContext!
            var result = [ABCAction]()
            let expect: XCTestExpectation

            // Appends to messages if A, otherwise drops the message.
            lazy var behaviorA = ABCAction.be { [unowned self] _ in
                self.result.append(.A)
                return .same
            }

            // Appends to messages if B, otherwise drops the message.
            lazy var behaviorB = ABCAction.be { [unowned self] in
                self.result.append(.B)
                switch $0 {
                case .A, .C: return .unhandled
                case .B:
                    let newBehaviorB = ABCAction.be { [unowned self] in
                        switch $0 {
                        case .B:
                            self.result += [.B, .B, .B]
                            return .same
                        case .A, .C:
                            return .unhandled
                        }
                    }

                    return .new(newBehaviorB)
                }
            }

            // Appends to messages if C, otherwise drops the message.
            lazy var behaviorC = ABCAction.be { [unowned self] _ in
                self.result.append(.C)
                return .unhandled
            }

            lazy var receive = self.behaviorA <| self.behaviorB <| self.behaviorC

            required init(_ param: XCTestExpectation) {
                self.expect = param
            }

            func postStop() {
                expect.fulfill()
            }
        }

        let expect = expectation(description: "poisoned")
        let props = Props(AssocActor.self, param: expect)
        let actor = system.spawn(props, name: "\(#function)Actor")

        // Act
        actor ! ABCAction.B  // result should be [.C, .B]
        actor ! ABCAction.B  // result should be ^ + [.C, .B, .B, .B]
        actor ! ABCAction.A  // result should be ^ + [.C, .A]

        // Assert
        actor ! .poisonPill
        wait(for: [expect], timeout: 1)

        let result = (actor as! AssocActor).result

        XCTAssert(result == [.C, .B, .C, .B, .B, .B, .C, .A], "got '\(result)'")
    }

}
