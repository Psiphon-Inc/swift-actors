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

class NoOpActor: Actor {
    typealias ParamType = Void

    var context: ActorContext!

    lazy var receive = behavior { [unowned self] msg -> ActionResult in
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

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
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
            case behaviorA(Int, sender: ActorRef)
            case behaviorB(Int, sender: ActorRef)
        }

        class Switcher: Actor {
            typealias ParamType = Void

            var context: ActorContext!

            /// TODO: probably a compiler bug.
            ///       have to explicitly set `behaviorA`'s type to `Behavior`, otherwise will get the message
            ///       "Value of type 'Switcher' has no member 'behaviorA'"
            lazy var actionA: ActionHandler = { [unowned self] msg -> ActionResult in
                guard let msg = msg as? SwitchAction else {
                    XCTFail()
                    return .same
                }

                switch msg {
                case .behaviorA(let num, let sender):
                    sender.tell(message: "A\(num)")
                    return .same
                case .behaviorB(let num, let sender):
                    sender.tell(message: "A\(num)")
                    return .action(self.actionB)
                }
            }

            lazy var actionB : ActionHandler = { [unowned self] msg -> ActionResult in

                guard let msg = msg as? SwitchAction else {
                    XCTFail()
                    return .same
                }

                switch msg {
                case .behaviorA(let num, let sender):
                    sender.tell(message: "B\(num)")
                    return .action(self.actionA)
                case .behaviorB(let num, let sender):
                    sender.tell(message: "B\(num)")
                    return .same
                }
            }

            lazy var receive = behavior(self.actionA)

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
                switcher.tell(message: SwitchAction.behaviorA(1, sender: self)) // should respond A1
                switcher.tell(message: SwitchAction.behaviorB(2, sender: self)) // should respond A2
                switcher.tell(message: SwitchAction.behaviorA(3, sender: self)) // should respond B3
                switcher.tell(message: SwitchAction.behaviorB(4, sender: self)) // should respond A4
                switcher.tell(message: SwitchAction.behaviorB(5, sender: self)) // should respond B5
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

            var receive = behavior { _ in
                return .unhandled
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
        echo ! EchoActor.Ping(value: expect, sender: noop)

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

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
                guard let msg = msg as? String else {
                    XCTFail()
                    return .same
                }

                if msg == "echoChild" {
                    self.child! ! EchoActor.Ping(value: "messageToChild", sender: self)
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

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
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

    func testStash() {
        // Arrange
        class StashActor: Actor {
            typealias ParamType = XCTestExpectation

            var context: ActorContext!
            let done: XCTestExpectation
            var counter = 0

            var round1 = [String]()
            var round2 = [String]()

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
                guard let msg = msg as? String else {
                    return .unhandled
                }

                switch (self.counter, msg) {
                case (0...4, _):
                    self.context.stash()
                    self.round1.append(msg)

                case (5, "sentinel"):
                    self.context.unstashAll()

                case (6...10, _):
                    self.round2.append(msg)

                default: break
                }

                if self.counter == 10 {
                    XCTAssertEqual(self.round1, self.round2)
                    self.done.fulfill()
                }

                self.counter += 1

                return .same
            }

            required init(_ param: ParamType) {
                self.done = param
            }
        }

        // Act
        let doneExpectation = expectation(description: "done")
        let actor = system.spawn(Props(StashActor.self, param: doneExpectation), name: #function)

        actor ! "1"
        actor ! "2"
        actor ! "3"
        actor ! "4"
        actor ! "5"
        actor ! "sentinel"

        // Assert
        wait(for: [doneExpectation], timeout: 1)
    }

}

