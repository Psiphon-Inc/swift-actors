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
import SwiftActors

extension XCTestExpectation: AnyMessage {}

class NoOpActor: Actor {
    var context: ActorContext!
    
    lazy var receive: Behavior = { [unowned self] msg -> Receive in
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
            
            lazy var receive: Behavior = { [unowned self] msg -> Receive in
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

    func testSwitchBehavior() {
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
            
            lazy var behaviorA: Behavior = { [unowned self] msg -> Receive in

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
            
            lazy var behaviorB: Behavior = { [unowned self] msg -> Receive in
                
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
            
            lazy var receive: Behavior = behaviorA
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
            
            lazy var receive: Behavior = { [unowned self] msg -> Receive in
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
            
            lazy var receive: Behavior = { [unowned self] msg -> Receive in
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
    
}
