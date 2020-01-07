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

            lazy var set10: ActionHandler = { [unowned self] msg -> ActionResult in
                switch msg {
                case let msg as String:

                    if msg == "set10" {
                        self.counter = 10
                        return .behavior(self.increment <|> self.decrement)
                    } else {
                        return .same
                    }

                default:
                    XCTFail()
                }
                return .unhandled
            }

            lazy var increment: ActionHandler = { [unowned self] msg -> ActionResult in
                switch msg {
                case let msg as String:

                    if msg == "increment" {
                        self.counter += 1

                        if self.counter == 11 {
                            return .action(self.done)
                        } else {
                            return .behavior(self.increment <|> self.decrement)
                        }
                    } else {
                        return .same
                    }

                default:
                    XCTFail()
                }
                return .unhandled
            }

            lazy var decrement: ActionHandler = { [unowned self] msg -> ActionResult in
                switch msg {
                case let msg as String:

                    if msg == "decrement" {
                        self.counter -= 1
                        return .action(self.increment)
                    } else {
                        return .unhandled
                    }

                default:
                    XCTFail()
                }
                return .unhandled
            }

            lazy var done: ActionHandler = { [unowned self] msg -> ActionResult in
                let msg = msg as! String
                if msg == "done" {
                    self.doneExpectation.fulfill()
                    return .same
                } else {
                    XCTFail()
                    return .unhandled
                }
            }

            lazy var receive = self.set10 <|> self.decrement

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

    // MARK: Associativity

    /// Tests right associativity of behavior composition.
    func testAssociativityComposePlus() {

        // Arrange
        class AssocActor: Actor {
            var context: ActorContext!
            var result = [ABCAction]()
            let expect: XCTestExpectation

            // Appends to messages if A, otherwise drops the message.
            lazy var actionA = ABCAction.handler { [unowned self] _ in
                self.result.append(.A)
                return .same
            }

            // Appends to messages if B, otherwise drops the message.
            lazy var actionB = ABCAction.handler { [unowned self] _ in
                self.result.append(.B)
                return .unhandled
            }

            // Appends to messages if C, otherwise drops the message.
            lazy var actionC = ABCAction.handler { [unowned self] _ in
                self.result.append(.C)
                return .unhandled
            }

            lazy var receive = self.actionA <> self.actionB <> self.actionC

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
        actor ! .poisonPill(nil)
        wait(for: [expect], timeout: 1)

        let result = (actor as! AssocActor).result

        // If composition was left associative, we would expevect behaviorA to get called first (which returns `.same`)
        // So the result would have been `[.A]`.
        XCTAssert(result == [.C, .B, .A], "got '\(result)'")
    }

    /// Tests right associativity of behavior composition.
    func testAssociativityComposeAlternative() {

        // Arrange
        class AssocActor: Actor {
            var context: ActorContext!
            var result = [ABCAction]()
            let expect: XCTestExpectation

            // Appends to messages if A, otherwise drops the message.
            lazy var actionA = ABCAction.handler { [unowned self] _ in
                self.result.append(.A)
                return .same
            }

            // Appends to messages if B, otherwise drops the message.
            lazy var actionB = ABCAction.handler { [unowned self] _ in
                self.result.append(.B)
                return .unhandled
            }

            // Appends to messages if C, otherwise drops the message.
            lazy var actionC = ABCAction.handler { [unowned self] _ in
                self.result.append(.C)
                return .unhandled
            }

            lazy var receive = self.actionA <|> self.actionB <|> self.actionC

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
        actor ! .poisonPill(nil)
        wait(for: [expect], timeout: 1)

        let result = (actor as! AssocActor).result

        // If composition was left associative, we would expevect behaviorA to get called first (which returns `.same`)
        // So the result would have been `[.A]`.
        XCTAssert(result == [.C, .B, .A], "got '\(result)'")
    }

    // MARK: MiddleBehaviorSwitching

    /// Tests the condition when a behavior - that is situated in the middle of behavior composition - returns a new behavior after handling a message,
    /// that was not processed by the behavior above it.
    func testMiddleBehaviorSwitchingComposePlus() {

        // Arrange

        /// Initially the actors behavior is `behaviorA <> behaviorB <> behaviorC`
        /// After receiving message `.B`, the next behavior should be `behaviorA <> newBehaviorB <> behaviorC`
        class AssocActor: Actor {
            var context: ActorContext!
            var result = [ABCAction]()
            let expect: XCTestExpectation

            // Appends to messages if A, otherwise drops the message.
            lazy var actionA = ABCAction.handler { [unowned self] _ in
                self.result.append(.A)
                return .same
            }

            // Appends to messages if B, otherwise drops the message.
            lazy var actionB = ABCAction.handler { [unowned self] in
                self.result.append(.B)
                switch $0 {
                case .A, .C:
                    return .unhandled
                case .B:
                    let newActionB = ABCAction.handler { [unowned self] in
                        switch $0 {
                        case .B:
                            self.result += [.B, .B, .B]
                            return .same
                        case .A, .C:
                            return .unhandled
                        }
                    }

                    return .action(newActionB)
                }
            }

            // Appends to messages if C, otherwise drops the message.
            lazy var behaviorC = ABCAction.handler { [unowned self] _ in
                self.result.append(.C)
                return .unhandled
            }

            lazy var receive = self.actionA <> self.actionB <> self.behaviorC

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
        actor ! .poisonPill(nil)
        wait(for: [expect], timeout: 1)

        let result = (actor as! AssocActor).result

        XCTAssert(result == [.C, .B, .C, .B, .B, .B, .C, .A], "got '\(result)'")
    }

    /// Tests the condition when a behavior - that is situated in the middle of behavior composition - returns a new behavior after handling a message,
    /// that was not processed by the behavior above it.
    func testMiddleBehaviorSwitchingComposeAlternative() {
        // Arrange

        /// Initially the actors behavior is `actionA <|> actionB <|> actionC`
        /// After receiving message `.B`, the next behavior should be `newActionB `
        class AssocActor: Actor {
            var context: ActorContext!
            var result = [ABCAction]()
            let expect: XCTestExpectation

            // Appends to messages if A, otherwise drops the message.
            lazy var actionA = ABCAction.handler { [unowned self] _ in
                XCTFail()
                return .unhandled
            }

            // Appends to messages if B, otherwise drops the message.
            lazy var actionB = ABCAction.handler { [unowned self] in
                self.result.append(.B)
                switch $0 {
                case .A, .C:
                    return .unhandled
                case .B:
                    let newActionB = ABCAction.handler { [unowned self] in
                        switch $0 {
                        case .B:
                            self.result += [.B, .B, .B]
                            return .same
                        case .A, .C:
                            return .same
                        }
                    }

                    return .action(newActionB)
                }
            }

            // Appends to messages if C, otherwise drops the message.
            lazy var actionC = ABCAction.handler { [unowned self] _ in
                self.result.append(.C)
                return .unhandled
            }

            lazy var def = self.actionA <|> self.actionB <|> self.actionC
            lazy var receive = self.def

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
        actor ! ABCAction.B  // result should be ^ + [.B, .B, .B]
        actor ! ABCAction.A  // result should be ^ + []

        // Assert
        actor ! .poisonPill(nil)
        wait(for: [expect], timeout: 1)

        let result = (actor as! AssocActor).result

        // result is if <> composition is used [.C, .B, .C, .B, .B, .B, .C]

        XCTAssert(result == [.C, .B, .B, .B, .B], "got '\(result)'")

    }

}
