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

infix operator |

extension XCTestExpectation: AnyMessage {}

class NoOpActor: Actor {
    typealias ParamType = Void

    var context: ActorContext!

    lazy var receive = behavior { [unowned self] msg -> Receive in
        guard let msg = msg as? XCTestExpectation else {
            XCTFail()
            return .same
        }

        msg.fulfill()
        return .same
    }

    required init(_ param: ParamType) {}
}

let noopActorProps = Props(NoOpActor.self, param: ())

final class ActorBasicTests: XCTestCase {

    var system: ActorSystem!

    override func setUp() {
        system = ActorSystem(name: "system")
    }

    override func tearDown() {
        system.stop()
        system = nil
    }

    func testOneMessageSend() {
        // Arrange
        let expect = expectation(description: "receive message")

        // Act
        let ref = system.spawn(noopActorProps, name: "testOneMessageSend")
        ref.tell(message: expect)

        // Assert
        wait(for: [expect], timeout: 1)
    }

    func testMultipleMessageSend() {
        // Arrange
        var expectations = [XCTestExpectation]()

        // Act
        let ref = system.spawn(noopActorProps, name: "testActor")
        for _ in 1...10 {
            let expect = expectation(description: "receive message")
            expectations.append(expect)
            ref.tell(message: expect)
        }

        // Assert
        wait(for: expectations, timeout: 1, enforceOrder: true)
    }

    func testMessageSendActorToActor() {
        // Arrange
        enum Forwarding: AnyMessage {
            case forward(to: ActorRef)
        }

        class ForwardingActor: Actor {
            typealias ParamType = [XCTestExpectation]

            let forwardExpect: XCTestExpectation
            let noopExpect: XCTestExpectation

            var context: ActorContext!

            lazy var receive = behavior { [unowned self] msg -> Receive in
                switch msg as! Forwarding {
                case .forward(to: let noopActor):
                    self.forwardExpect.fulfill()
                    noopActor.tell(message: self.noopExpect)
                }
                return .same
            }

            required init(_ param: ParamType) {
                self.forwardExpect = param[0]
                self.noopExpect = param[1]
            }

        }

        let expectations = [expectation(description: "forwarding"),
                            expectation(description: "noop")]

        let props = Props(ForwardingActor.self, param: expectations)

        // Act
        let forwardingActor = system.spawn(props, name: "forwarding")

        let noopActor = system.spawn(noopActorProps, name: "noop")

        // Sends first message to forwarding actor
        forwardingActor.tell(message: Forwarding.forward(to: noopActor))

        // Assert
        wait(for: props.param, timeout: 1, enforceOrder: true)
    }

    func testReceiveNewBehavior() {
        // Arrange
        let expectations = [ expectation(description: "A1"),
                             expectation(description: "A2"),
                             expectation(description: "B3"),
                             expectation(description: "A4"),
                             expectation(description: "B5")]

        enum SwitchAction: AnyMessage {
            case behaviorA(Int)
            case behaviorB(Int)
        }

        class Switcher: Actor {
            typealias ParamType = Void

            var context: ActorContext!

            /// TODO: probably a compiler bug.
            ///       have to explicitly set `behaviorA`'s type to `Behavior`, otherwise will get the message
            ///       "Value of type 'Switcher' has no member 'behaviorA'"
            lazy var behaviorA: Behavior = behavior { [unowned self] msg -> Receive in

                guard let sender = self.context.sender() else {
                    XCTFail()
                    return .same
                }

                guard let msg = msg as? SwitchAction else {
                    XCTFail()
                    return .same
                }

                switch msg {
                case .behaviorA(let num):
                    sender.tell(message: "A\(num)", from: self)
                    return .same
                case .behaviorB(let num):
                    sender.tell(message: "A\(num)", from: self)
                    return .new(self.behaviorB)
                }
            }

            lazy var behaviorB = behavior { [unowned self] msg -> Receive in

                guard let sender = self.context.sender() else {
                    XCTFail()
                    return .same
                }

                guard let msg = msg as? SwitchAction else {
                    XCTFail()
                    return .same
                }

                switch msg {
                case .behaviorA(let num):
                    sender.tell(message: "B\(num)", from: self)
                    return .new(self.behaviorA)
                case .behaviorB(let num):
                    sender.tell(message: "B\(num)", from: self)
                    return .same
                }
            }

            lazy var receive = self.behaviorA

            required init(_ param: Void) {}
        }

        class TestActor: Actor {

            struct Params {
                let expectations: [XCTestExpectation]
                let switcher: ActorRef
            }

            typealias ParamType = Params
            var context: ActorContext!

            let switcher: ActorRef
            let expectations: [XCTestExpectation]

            lazy var receive = behavior { [unowned self] in
                guard let msg = $0 as? String else {
                    XCTFail()
                    return .same
                }

                if msg == "A1" {
                    self.expectations[0].fulfill()
                }
                if msg == "A2" {
                    self.expectations[1].fulfill()
                }
                if msg == "B3" {
                    self.expectations[2].fulfill()
                }
                if msg == "A4" {
                    self.expectations[3].fulfill()
                }
                if msg == "B5" {
                    self.expectations[4].fulfill()
                }

                return .same
            }

            required init(_ param: Params) {
                self.switcher = param.switcher
                self.expectations = param.expectations
            }

            func preStart() {
                // starting behavior for switch is  is `behaviorA`
                switcher.tell(message: SwitchAction.behaviorA(1)) // should respond A1
                switcher.tell(message: SwitchAction.behaviorB(2)) // should respond A2
                switcher.tell(message: SwitchAction.behaviorA(3)) // should respond B3
                switcher.tell(message: SwitchAction.behaviorB(4)) // should respond A4
                switcher.tell(message: SwitchAction.behaviorB(5)) // should respond B5
            }
        }

        // Act
        let switcher = system.spawn(Props(Switcher.self, param: ()), name: "switcher")

        let testActorProps = Props(TestActor.self,
                                   param: TestActor.Params(expectations: expectations,
                                                            switcher: switcher))

        system.spawn(testActorProps, name: "testActor")

        wait(for: expectations, timeout: 1, enforceOrder: true)
    }

    func testReceiveUnhandledBehavior() {

        // Arrange
        let fatalErrorExpectation = expectation(description: "fatalErrorExpectation")

        // Subclasses ActorSystem to fulfill expectation on fatalError instead of panicking.
        class TestActorSystem: ActorSystem {
            var expectation: XCTestExpectation

            init(name: String, expectation: XCTestExpectation) {
                self.expectation = expectation
                super.init(name: name, contextType: LocalActorContext.self)
            }

            override func fatalError(_ message: String) {
                expectation.fulfill()
            }
        }

        let testSystem = TestActorSystem(name: "ReceiveUnhandledBehaviorSystem", expectation: fatalErrorExpectation)

        class TestActor: Actor {
            typealias ParamType = Void

            var context: ActorContext!

            var receive = behavior {
                return .unhandled($0)
            }

            required init(_ param: Void) {}
        }

        let testActor = testSystem.spawn(Props(TestActor.self, param: ()) ,name: "actor")

        // Act
        testActor.tell(message: "msg1")

        // Assert
        wait(for: [fatalErrorExpectation], timeout: 1)

        // Cleanup
        testSystem.stop()
    }

    func testBangOperator() {
        // Arrange
        let expect = expectation(description: "receive message")

        // Act
        let ref = system.spawn(noopActorProps, name: "testActor")
        ref ! expect

        // Assert
        wait(for: [expect], timeout: 1)
    }

    func testBangOperatorWithSender() {
        // Arrange
        let expect = expectation(description: "message received")
        let noop = system.spawn(noopActorProps, name: "noop")
        let echo = system.spawn(echoActorProps, name: "echo")

        // Act
        // Sends `expect` message to `echo`, setting `noop` as the sender.
        echo ! (expect, noop)

        // Assert
        wait(for: [expect], timeout: 1)
    }

    func testCreateChildActorAsProp() {
        // Arrange
        class TestActor: Actor {
            typealias ParamType = XCTestExpectation

            var context: ActorContext!

            lazy var child: ActorRef? = context.spawn(echoActorProps, name: "echo")

            let expect: XCTestExpectation

            required init(_ param: XCTestExpectation) {
                self.expect = param
            }

            lazy var receive = behavior { [unowned self] msg -> Receive in
                guard let msg = msg as? String else {
                    XCTFail()
                    return .same
                }

                if msg == "echoChild" {
                    self.child! ! "messageToChild"
                }
                if msg == "messageToChild" {
                    self.expect.fulfill()
                }
                return .same
            }

            func postStop() {
                child = nil
            }

        }

        let expect = expectation(description: "message back from child")

        // Act
        let actor = system.spawn(Props(TestActor.self, param: expect), name: "testActor")
        actor ! "echoChild"

        // Assert
        wait(for: [expect], timeout: 1)
    }

    func testUsingClassAndStructAsMessages() {
        // Arrange
        class SetTo10: AnyMessage {}
        struct Done: AnyMessage {}
        struct Multiply: AnyMessage {
            let a: Int
        }

        class Calculator: Actor {
            typealias ParamType = XCTestExpectation

            var context: ActorContext!
            var result: Int = 10

            let done: XCTestExpectation

            lazy var receive = behavior { [unowned self] msg -> Receive in
                switch msg {
                case is SetTo10:
                    self.result = 10
                case let msg as Multiply:
                    self.result *= msg.a
                case is Done:
                    self.done.fulfill()
                default:
                    XCTFail()
                }
                return .same
            }

            required init(_ param: ParamType) {
                self.done = param
            }
        }

        let doneExpectation = expectation(description: "done")
        let calc = system.spawn(Props(Calculator.self, param: doneExpectation), name: "calc")

        // Act
        calc ! SetTo10()
        calc ! Multiply(a: 2)
        calc ! Done()

        // Assert
        wait(for: [doneExpectation], timeout: 1)
        XCTAssert((calc as! Calculator).result == 20)
    }

    func testBehaviorComposition() {

        // Arrange
        class TestActor: Actor {
            typealias ParamType = XCTestExpectation

            var context: ActorContext!
            let doneExpectation: XCTestExpectation
            var counter: Int = 0

            lazy var set10: Behavior = behavior { [unowned self] msg -> Receive in
                switch msg {
                case let msg as String:

                    if msg == "set10" {
                        self.counter = 10
                        return .new(self.increment | self.decrement)
                    } else {
                        return .same
                    }

                default:
                    XCTFail()
                }
                return .unhandled(msg)
            }

            lazy var increment: Behavior = behavior { [unowned self] msg -> Receive in
                switch msg {
                case let msg as String:

                    if msg == "increment" {
                        self.counter += 1

                        if self.counter == 11 {
                            return .new(self.done)
                        } else {
                            return .new(self.increment | self.decrement)
                        }
                    } else {
                        return .same
                    }

                default:
                    XCTFail()
                }
                return .unhandled(msg)
            }

            lazy var decrement = behavior { [unowned self] msg -> Receive in
                switch msg {
                case let msg as String:

                    if msg == "decrement" {
                        self.counter -= 1
                        return .new(self.increment)
                    } else {
                        return .unhandled(msg)
                    }

                default:
                    XCTFail()
                }
                return .unhandled(msg)
            }

            lazy var done = behavior { [unowned self] msg -> Receive in
                let msg = msg as! String
                if msg == "done" {
                    self.doneExpectation.fulfill()
                    return .same
                } else {
                    XCTFail()
                    return .unhandled(msg)
                }
            }

            lazy var receive = self.set10 | self.decrement

            required init(_ param: ParamType) {
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

}

