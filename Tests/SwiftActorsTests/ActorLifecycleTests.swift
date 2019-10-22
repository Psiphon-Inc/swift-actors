///*
// * Copyright (c) 2019, Psiphon Inc.
// * All rights reserved.
// *
// * This program is free software: you can redistribute it and/or modify
// * it under the terms of the GNU General Public License as published by
// * the Free Software Foundation, either version 3 of the License, or
// * (at your option) any later version.
// *
// * This program is distributed in the hope that it will be useful,
// * but WITHOUT ANY WARRANTY; without even the implied warranty of
// * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// * GNU General Public License for more details.
// *
// * You should have received a copy of the GNU General Public License
// * along with this program.  If not, see <http:www.gnu.org/licenses/>.
// *
// */
//
//import XCTest
//@testable import SwiftActors
//
//func makeExpectations(t: XCTestCase, count: Int, description: String = "expectation") -> [XCTestExpectation] {
//    var e = [XCTestExpectation]()
//    for i in 1...count {
//        e.append(t.expectation(description: "\(description)_\(i)"))
//    }
//    return e
//}
//
//class ActorLifecycleTests: XCTestCase {
//    var system: ActorSystem!
//
//    override func setUp() {
//        system = ActorSystem(name: "system")
//    }
//
//    override func tearDown() {
//        system.stop()
//        system = nil
//    }
//
//    /// Tests starting an actor after sending it a messages
//    func testActorStartAfterSendingMessages() {
//
//        // Arrange
//        class DelayedStart: Actor {
//            typealias ParamType = [XCTestExpectation]
//
//            var context: ActorContext!
//            var expectations: [XCTestExpectation]
//
//            lazy var receive = behavior { [unowned self] msg -> ActionResult in
//
//                if let i = msg as? Int {
//                    self.expectations[i].fulfill()
//                }
//                return .same
//            }
//
//            required init(_ param: ParamType) {
//                self.expectations = param
//            }
//        }
//
//        let expectations = makeExpectations(t: self, count: 10, description: "delayedStart")
//        let delayedStart = DelayedStart(expectations)
//
//        // Act
//        let context = LocalActorContext(name: "delayedStart",
//                                        system: system,
//                                        actor: delayedStart,
//                                        parent: nil)
//        delayedStart.bind(context: context)
//
//        for i in 0..<10 {
//            delayedStart ! i
//        }
//        context.start()
//
//        // Assert
//        wait(for: expectations, timeout: 1, enforceOrder: true)
//    }
//
//    /// Tests actor that has not started. This actor should not process any messages
//    func testActorNeverStarted() {
//        // Arrange
//        class TestActor: Actor {
//            typealias ParamType = XCTestExpectation
//
//            var context: ActorContext!
//            let expect: XCTestExpectation
//
//            lazy var receive = behavior { [unowned self] msg -> ActionResult in
//                self.expect.fulfill()
//                return .same
//            }
//
//            required init(_ param: XCTestExpectation) {
//                self.expect = param
//            }
//        }
//
//        let expect = expectation(description: "neverStarted")
//        expect.isInverted = true
//        let testActor = TestActor(expect)
//
//        // Act
//        let context = LocalActorContext(name: "testActorNeverStarted",
//                                        system: system,
//                                        actor: testActor,
//                                        parent: nil)
//        testActor.bind(context: context)
//        testActor ! "someMessage"  // Message should not be processed.
//
//        // Assert
//        wait(for: [expect], timeout: 1)
//    }
//
//    /// Tests actor `preStart` lifecycle callback getting called before it starts processing messages.
//    func testPreStartCallback() {
//        // Arrange
//        class ActorWithPreStart: Actor {
//            typealias ParamType = XCTestExpectation
//
//            var context: ActorContext!
//            var preStartValue: String = "notStarted"
//            let expect: XCTestExpectation
//
//            lazy var receive = behavior { [unowned self] msg -> ActionResult in
//                return .same
//            }
//
//            func preStart() {
//                preStartValue = "started"
//                expect.fulfill()
//            }
//
//            required init(_ param: XCTestExpectation) {
//                self.expect = param
//            }
//        }
//
//        let preStartExpect = expectation(description: "preStart")
//
//        // `preStart` should not be called until after actor is started.
//        let actor = ActorWithPreStart(preStartExpect)
//        let context = LocalActorContext(name: "actor", system: system, actor: actor, parent: nil)
//
//        // Act & Assert
//        actor.bind(context: context)
//        XCTAssert(context.state == .spawned)
//        XCTAssert(actor.preStartValue == "notStarted")
//        context.start()
//
//        // Assert
//        wait(for: [preStartExpect], timeout: 1)
//
//        // preStart should have been called
//        XCTAssert(context.state == .started)
//        XCTAssert(actor.preStartValue == "started")
//    }
//
//    /// Tests actor `postStop` lifecycle callback.
//    func postStopCallbackTest(callStart: Bool, waitForStart: Bool, numStops: Int = 1) {
//        // Arrange
//        /// Fulfills expectation when `postStop` callback is called.
//        class ActorWithPostStop: Actor {
//            typealias ParamType = [XCTestExpectation?]
//
//            var context: ActorContext!
//
//            let postStopExpect: XCTestExpectation
//            let preStartExpect: XCTestExpectation?
//
//            required init(_ param: [XCTestExpectation?]) {
//                postStopExpect = param[0]!
//                preStartExpect = param[1]
//            }
//
//            lazy var receive = behavior { [unowned self] msg -> ActionResult in
//                return .same
//            }
//
//            func preStart() {
//                preStartExpect?.fulfill()
//            }
//
//            func postStop() {
//                postStopExpect.fulfill()
//            }
//
//        }
//
//        let preStartExpect = waitForStart ? expectation(description: "preStart") : nil
//        let postStopExpect = expectation(description: "postStop")
//        let actor = ActorWithPostStop([postStopExpect, preStartExpect])
//        let context = LocalActorContext(name: "postStopActor", system: system, actor: actor, parent: nil)
//
//        // Act
//        actor.bind(context: context)
//        if callStart {
//            context.start()
//        }
//
//        if waitForStart {
//            wait(for: [preStartExpect!], timeout: 1)
//        }
//
//        for _ in 1...numStops {
//            actor.stop()
//        }
//
//        // Assert
//        wait(for: [postStopExpect], timeout: 1)
//    }
//
//    func testPostStopCallback() {
//        postStopCallbackTest(callStart: true, waitForStart: true, numStops: 1)
//    }
//
//    func testPostStopCallbackWithoutStarting() {
//        postStopCallbackTest(callStart: false, waitForStart: false, numStops: 1)
//    }
//
//    func testPostStopCallbackWithoutWaitingForStart() {
//        postStopCallbackTest(callStart: true, waitForStart: false, numStops: 1)
//    }
//
//    func testPostStopCallbackStopMultipleTimes() {
//        postStopCallbackTest(callStart: true, waitForStart: false, numStops: 10)
//    }
//
//    func testStopProcessingMessagesWhenStopped() {
//        // Arrange
//        enum Action: AnyMessage {
//            case increment
//            case shouldNotProcess
//            case stop
//            case contextStop
//        }
//
//        class TestActor: Actor {
//            typealias ParamType = Void
//
//            var context: ActorContext!
//            var counter: Int = 0
//
//            lazy var receive = behavior { [unowned self] msg -> ActionResult in
//                XCTAssert((self.context as! LocalActorContext<TestActor>).state == .started)
//
//                guard let msg = msg as? Action else {
//                    XCTFail()
//                    return .same
//                }
//
//                switch msg {
//                case .increment:
//                    self.counter += 1
//                case .shouldNotProcess:
//                    XCTFail()
//                case .stop:
//                    self.context.stop()
//                    return .same
//                case .contextStop:
//                    self.stop()
//                }
//                return .same
//            }
//
//            required init(_ param: Void) {}
//        }
//
//        // Goes through different ways of stopping.
//        for testNum in 1...3 {
//
//            // Act
//            let actor = system.spawn(Props(TestActor.self, param: ()),
//                                     name: "testActor\(testNum)")
//            actor ! Action.increment
//
//            switch testNum {
//            case 1:
//                actor ! Action.stop
//            case 2:
//                actor ! Action.contextStop
//            case 3:
//                actor ! SystemMessage.poisonPill
//            default:
//                XCTFail()
//            }
//
//            // These messages should not be processed
//            for _ in 1...1000 {
//                actor ! Action.shouldNotProcess
//            }
//
//            // wait (TODO: once actor watcher is implemented, this needs to be removed)
//
//            let actorContext = (actor as! TestActor).context as! LocalActorContext<TestActor>
//            repeat {
//                Thread.sleep(forTimeInterval: 0.1)
//            } while actorContext.state != .stopped
//
//            // Assert
//            XCTAssert(actorContext.state == .stopped)
//            XCTAssert(actorContext.mailbox.stopped == true)
//
//            // Test specific assertions.
//            switch testNum {
//            case 1, 2:
//                XCTAssert(actorContext.mailbox.stopped == true)
//                XCTAssert((actor as! TestActor).counter == 1, "actor counter is \((actor as! TestActor).counter) - test \(testNum)")
//            default: break
//            }
//        }
//    }
//
//}
//
