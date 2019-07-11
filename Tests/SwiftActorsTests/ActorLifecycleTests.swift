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

func makeExpectations(t: XCTestCase, count: Int, description: String = "expectation") -> [XCTestExpectation] {
    var e = [XCTestExpectation]()
    for i in 1...count {
        e.append(t.expectation(description: "\(description)_\(i)"))
    }
    return e
}

class ActorLifecycleTests: XCTestCase {
    var system: ActorSystem!
    
    override func setUp() {
        system = ActorSystem(name: "system")
    }
    
    override func tearDown() {
        system.stop()
        system = nil
    }
    
    /// Tests starting an actor after sending it a messages
    func testActorStartAfterSendingMessages() {
        // Arrange
        class DelayedStart: Actor {
            var context: ActorContext!
            var expectations: [XCTestExpectation]
            
            lazy var receive = behavior { [unowned self] msg -> Receive in

                if let i = msg as? Int {
                    self.expectations[i].fulfill()
                }
                return .same
            }
            
            init(_ e: [XCTestExpectation]) {
                expectations = e
            }
        }
        
        let expectations = makeExpectations(t: self, count: 10, description: "delayedStart")
        let delayedStart = DelayedStart(expectations)
        
        // Act
        delayedStart.bind(context: LocalActorContext(name: "delayedStart", system: system, actor: delayedStart))
        for i in 0..<10 {
            delayedStart ! i
        }
        delayedStart.context.start()
        
        // Assert
        wait(for: expectations, timeout: 1, enforceOrder: true)
    }
    
    /// Tests actor that has not started. This actor should not process any messages
    func testActorNeverStarted() {
        // Arrange
        class TestActor: Actor {
            var context: ActorContext!
            let expect: XCTestExpectation
            
            lazy var receive = behavior { [unowned self] msg -> Receive in
                self.expect.fulfill()
                return .same
            }
            
            init(_ e: XCTestExpectation) {
                expect = e
            }
        }
        
        let expect = expectation(description: "neverStarted")
        expect.isInverted = true
        let testActor = TestActor(expect)
        
        // Act
        testActor.bind(context: LocalActorContext(name: "testActor", system: system, actor: testActor))
        testActor ! "someMessage"  // Message should not be processed.
        
        // Assert
        wait(for: [expect], timeout: 1)
    }
    
    /// Tests actor `preStart` lifecycle callback getting called before it starts processing messages.
    func testPreStartCallback() {
        // Arrange
        class ActorWithPreStart: Actor {
            var context: ActorContext!
            var preStartValue: String = "notStarted"
            let expect: XCTestExpectation
            
            lazy var receive = behavior { [unowned self] msg -> Receive in
                return .same
            }
            
            func preStart() {
                preStartValue = "started"
                expect.fulfill()
            }
            
            init(_ e: XCTestExpectation) {
                expect = e
            }
        }
        
        let preStartExpect = expectation(description: "preStart")
        
        // `preStart` should not be called until after actor is started.
        let actor = ActorWithPreStart(preStartExpect)
        let context = LocalActorContext(name: "actor", system: system, actor: actor)
        
        // Act & Assert
        actor.bind(context: context)
        XCTAssert(context.state == .spawned)
        XCTAssert(actor.preStartValue == "notStarted")
        context.start()
        
        // Assert
        wait(for: [preStartExpect], timeout: 1)
        
        // preStart should have been called
        XCTAssert(context.state == .started)
        XCTAssert(actor.preStartValue == "started")
    }
    
    /// Tests actor `postStop` lifecycle callback.
    func postStopCallbackTest(callStart: Bool, waitForStart: Bool, numStops: Int = 1) {
        // Arrange
        /// Fulfills expectation when `postStop` callback is called.
        class ActorWithPostStop: Actor {
            var context: ActorContext!
            
            let postStopExpect: XCTestExpectation
            let preStartExpect: XCTestExpectation?
            
            init(postStop: XCTestExpectation, preStart: XCTestExpectation?) {
                postStopExpect = postStop
                preStartExpect = preStart
            }
            
            lazy var receive = behavior { [unowned self] msg -> Receive in
                return .same
            }
            
            func preStart() {
                preStartExpect?.fulfill()
            }
            
            func postStop() {
                postStopExpect.fulfill()
            }
            
        }
        
        let preStartExpect = waitForStart ? expectation(description: "preStart") : nil
        let postStopExpect = expectation(description: "postStop")
        let actor = ActorWithPostStop(postStop: postStopExpect, preStart: preStartExpect)
        let context = LocalActorContext(name: "postStopActor", system: system, actor: actor)
        
        // Act
        actor.bind(context: context)
        if callStart {
            context.start()
        }
        
        if waitForStart {
            wait(for: [preStartExpect!], timeout: 1)
        }
        
        for _ in 1...numStops {
            actor.stop()
        }
        
        // Assert
        wait(for: [postStopExpect], timeout: 1)
    }
    
    func testPostStopCallback() {
        postStopCallbackTest(callStart: true, waitForStart: true, numStops: 1)
    }
    
    func testPostStopCallbackWithoutStarting() {
        postStopCallbackTest(callStart: false, waitForStart: false, numStops: 1)
    }
    
    func testPostStopCallbackWithoutWaitingForStart() {
        postStopCallbackTest(callStart: true, waitForStart: false, numStops: 1)
    }
    
    func testPostStopCallbackStopMultipleTimes() {
        postStopCallbackTest(callStart: true, waitForStart: false, numStops: 10)
    }
    
    func testStopProcessingMessagesWhenStopped() {
        // Arrange
        enum Action: AnyMessage {
            case increment
            case shouldNotProcess
            case stop
            case contextStop
        }
        
        class TestActor: Actor {
            var context: ActorContext!
            var counter: Int = 0
            
            lazy var receive = behavior { [unowned self] msg -> Receive in
                
                XCTAssert((self.context as! LocalActorContext).state == .started)
                
                guard let msg = msg as? Action else {
                    XCTFail()
                    return .same
                }
                
                switch msg {
                case .increment:
                    self.counter += 1
                case .shouldNotProcess:
                    XCTFail()
                case .stop:
                    return .stop
                case .contextStop:
                    self.stop()
                }
                return .same
            }
        }
        
        // Goes through different ways of stopping.
        for testNum in 1...3 {
            
            // Act
            let actor = system.spawn(name: "testActor\(testNum)", actor: TestActor())
            actor ! Action.increment
            
            switch testNum {
            case 1:
                actor ! Action.stop
            case 2:
                actor ! Action.contextStop
            case 3:
                actor.stop()
            default:
                XCTFail()
            }
            
            // These messages should not be processed
            for _ in 1...1000 {
                actor ! Action.shouldNotProcess
            }

            // wait (TODO: once actor watcher is implemented, this needs to be removed)

            let actorContext = actor.context as! LocalActorContext
            repeat {
                Thread.sleep(forTimeInterval: 0.1)
            } while actorContext.state != .stopped
            
            // Assert
            XCTAssert(actorContext.state == .stopped)
            XCTAssert(actorContext.mailbox.stopped.value == true)
            
            // Test specific assertions.
            switch testNum {
            case 1, 2:
                XCTAssert(actorContext.mailbox.stopped.value == true)
                XCTAssert(actor.counter == 1, "actor counter is \(actor.counter) - test \(testNum)")
            default: break
            }
        }
    }
    
}
