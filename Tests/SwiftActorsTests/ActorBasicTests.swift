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
infix operator <

extension XCTestExpectation: AnyMessage {}

class NoOpActor: Actor {
    var context: ActorContext!
    
    lazy var receive = behavior { [unowned self] msg -> Receive in
        guard let msg = msg as? XCTestExpectation else {
            XCTFail()
            return .same
        }
        
        msg.fulfill()
        return .same
    }
}

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
        let ref = system.spawn(name: "testActor", actor: NoOpActor())
        ref.tell(message: expect)
        
        // Assert
        wait(for: [expect], timeout: 1)
    }
    
    func testMultipleMessageSend() {
        // Arrange
        var expectations = [XCTestExpectation]()
        
        // Act
        let ref = system.spawn(name: "testActor", actor: NoOpActor())
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
            case forward(to: NoOpActor)
        }
        
        class ForwardingActor: Actor {
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
            
            init(forwardExpect: XCTestExpectation, noopExpect: XCTestExpectation) {
                self.forwardExpect = forwardExpect
                self.noopExpect = noopExpect
            }
        }
        
        let forwardExpect = expectation(description: "forwarding")
        let noopExpect = expectation(description: "noop")
        
        // Act
        let forwardingActor = system.spawn(name: "forwarding",
                                           actor: ForwardingActor(forwardExpect: forwardExpect, noopExpect: noopExpect))
        
        let noopActor = system.spawn(name: "noop", actor: NoOpActor())
        
        // Sends first message to forwarding actor
        forwardingActor.tell(message: Forwarding.forward(to: noopActor))
        
        // Assert
        wait(for: [forwardExpect, noopExpect], timeout: 1, enforceOrder: true)
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
        }
        
        var switcher: Switcher!
        let testActor = BehaviorActor(behavior: { msg, ctx throws -> Receive in
            
            guard let msg = msg as? String else {
                XCTFail()
                return .same
            }
            
            if msg == "A1" {
                expectations[0].fulfill()
            }
            if msg == "A2" {
                expectations[1].fulfill()
            }
            if msg == "B3" {
                expectations[2].fulfill()
            }
            if msg == "A4" {
                expectations[3].fulfill()
            }
            if msg == "B5" {
                expectations[4].fulfill()
            }
            
            return .same
        }, preStart: { ctx in
            // starting behavior is `behaviorA`
            switcher.tell(message: SwitchAction.behaviorA(1), from: ctx) // should respond A1
            switcher.tell(message: SwitchAction.behaviorB(2), from: ctx) // should respond A2
            switcher.tell(message: SwitchAction.behaviorA(3), from: ctx) // should respond B3
            switcher.tell(message: SwitchAction.behaviorB(4), from: ctx) // should respond A4
            switcher.tell(message: SwitchAction.behaviorB(5), from: ctx) // should respond B5
        })
        
        // Act
        switcher = system.spawn(name: "switcher", actor: Switcher())
        let _ = system.spawn(name: "testActor", actor: testActor)
        
        wait(for: expectations, timeout: 1, enforceOrder: true)
    }
    
    func testReceiveUnhandledBehavior() {
        
        // Arrange
        let fatalErrorExpectation = expectation(description: "fatalErrorExpectation")
        
        let testSystem = TestActorSystem(
            name: "ReceiveUnhandledBehaviorSystem",
            expectation: fatalErrorExpectation,
            expectationTest: {
                if case .unhandled = $0.errorType {
                    return true
                }
                XCTFail()
                return false
        })
        
        class TestActor: Actor {
            var context: ActorContext!
            var receive = behavior { msg -> Receive in
                return .unhandled(msg)
            }
        }
        
        let testActor = testSystem.spawn(name: "actor", actor: TestActor())
        
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
        let ref = system.spawn(name: "testActor", actor: NoOpActor())
        ref ! expect
        
        // Assert
        wait(for: [expect], timeout: 1)
    }
    
    func testBangOperatorWithSender() {
        // Arrange
        let expect = expectation(description: "message received")
        let noop = system.spawn(name: "noop", actor: NoOpActor())
        let echo = system.spawn(name: "echo", actor: EchoActor())
        
        // Act
        // Sends `expect` message to `echo`, setting `noop` as the sender.
        echo ! (expect, noop)
        
        // Assert
        wait(for: [expect], timeout: 1)
    }
    
    func testCreateChildActorAsProp() {
        // Arrange
        class TestActor: Actor {
            var context: ActorContext!
            lazy var child: EchoActor! = context.spawn(name: "echo", actor: EchoActor())
            
            let expect: XCTestExpectation
            
            init(_ e: XCTestExpectation) {
                expect = e
            }
            
            lazy var receive = behavior { [unowned self] msg -> Receive in
                guard let msg = msg as? String else {
                    XCTFail()
                    return .same
                }
                
                if msg == "echoChild" {
                    self.child ! ("messageToChild", self)
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
        let actor = system.spawn(name: "testActor", actor: TestActor(expect))
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
            var context: ActorContext!
            var result: Int = 10
            
            let done: XCTestExpectation
            
            init(_ e: XCTestExpectation) {
                done = e
            }
            
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
        }
        
        let doneExpectation = expectation(description: "done")
        let calc = system.spawn(name: "calc", actor: Calculator(doneExpectation))
        
        // Act
        calc ! SetTo10()
        calc ! Multiply(a: 2)
        calc ! Done()
        
        // Assert
        wait(for: [doneExpectation], timeout: 1)
        XCTAssert(calc.result == 20)
    }

    func testBehaviorComposition() {

        // Arrange
        class TestActor: Actor {
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

            init(_ expect: XCTestExpectation) {
                doneExpectation = expect
            }
        }

        let expect = expectation(description: "doneExpectation")
        let testActor = system.spawn(name: "testBehaviorComposition", actor: TestActor(expect))

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
        XCTAssert(testActor.counter == 11)
    }

    func testActorInvariant() {

        // Arrange
        class InvariantActor: Actor {
            var context: ActorContext!

            var counter: Int = 0

            lazy var receive = behavior { [unowned self] in
                guard let msg = $0 as? String else {
                    XCTFail()
                    return .same
                }

                if msg == "increment" {
                    self.counter += 1
                }

                return .same
            }

            func invariant(message: AnyMessage, result: Receive) -> InvariantError? {
                guard let msg = message as? String, msg == "increment" else {
                    XCTFail()
                    return InvariantError("msg != 'increment'")
                }
                guard case .same = result else {
                    XCTFail()
                    return InvariantError("result != .same")
                }
                guard counter < 2 else {
                    return InvariantError("counter >= 2")
                }
                return nil
            }
        }

        let invariantFail = expectation(description: "invariantFail")

        let testSystem = TestActorSystem(
            name: "InvariantTestSystem",
            expectation: invariantFail,
            expectationTest: {
                if case .failedInvariant = $0.errorType,
                    $0.errorMessage == "counter >= 2" {
                    return true
                }
                XCTFail()
                return false
        })

        let actor = testSystem.spawn(name: "actor", actor: InvariantActor())

        // Act
        actor ! "increment"  // Should add to counter
        actor ! "increment"  // Should add to counter and result in fatal error.

        // Assert
        wait(for: [invariantFail], timeout: 1)
        XCTAssert(actor.counter == 2)
    }

}
