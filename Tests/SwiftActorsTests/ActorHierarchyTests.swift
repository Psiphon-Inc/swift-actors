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

class ActorHierarchyTests: XCTestCase {

    var system: ActorSystem!
    var echo: ActorRef!

    override func setUp() {
        system = ActorSystem(name: "system")
        echo = system.spawn(echoActorProps, name: "echo")
    }

    override func tearDown() {
        system.stop()
        system = nil
        echo = nil
    }

    /// Tests adding one child to the EchoActor, and sending parent a message.
    func testAddChildBasic() {
        // Arrange
        let expects = [ expectation(description: "Ping"),
                        expectation(description: "parentPint") ]

        class ParentForwardActor: Actor {
            typealias ParamType = [XCTestExpectation]

            var context: ActorContext!

            let expects: [XCTestExpectation]

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
                if let msg = msg as? String {
                    if msg == "ping" {
                        self.expects[0].fulfill()
                    }
                    if msg == "pingParent" {
                        self.parent()! ! (1, self)
                    }
                }

                if let msg = msg as? Int {
                    if msg == 2 {
                        self.expects[1].fulfill()
                    }
                }

                return .same
            }

            required init(_ param: ParamType) {
                self.expects = param
            }
        }

        let props = Props(ParentForwardActor.self, param: expects)

        // Act
        let forwardActor = (echo as! EchoActor).spawn(props, name: "child")
        forwardActor ! "ping"
        forwardActor ! "pingParent"

        // Assert
        wait(for: expects, timeout: 1, enforceOrder: true)
    }

    func testAddChild() {
        // Arrange
        class PingerActor: Actor {
            typealias ParamType = XCTestExpectation

            var context: ActorContext!
            let expect: XCTestExpectation

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
                guard let msg = msg as? String else {
                    XCTFail()
                    return .same
                }

                if msg == "createChild" {
                    self.spawn(Props(PingActor.self, param: ()), name: "pingChild")
                }
                if msg == "pingChild" {
                    self.context.children["pingChild"]! ! ("ping", self)
                }
                if msg == "ping_back" {
                    // TODO
                    // XCTAssert(self.context.sender() === self.context.children["pingChild"])
                    self.expect.fulfill()
                }

                return .same
            }

            required init(_ param: ParamType) {
                self.expect = param
            }
        }

        class PingActor: Actor {
            typealias ParamType = Void

            var context: ActorContext!

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
                guard let sender = self.context.sender() else {
                    XCTFail()
                    return .same
                }
                guard let msg = msg as? String else {
                    XCTFail()
                    return .same
                }
                sender ! (msg + "_back", self)
                return .same
            }

            required init(_ param: Void) {}
        }

        let expect = expectation(description: "pingBack")
        let props = Props(PingerActor.self, param: expect)

        // Act
        let parent = (echo as! EchoActor).spawn(props, name: "parent")
        parent ! "createChild"
        parent ! "pingChild"

        // Assert
        wait(for: [expect], timeout: 1, enforceOrder: true)
    }

    /// Creates an actor hierarchy with a parent, child and subchild actors. Checks if the order of start lifecycle
    /// callbacks is correct.
    func testStartHierarchy() {
        // Arrange
        enum Message: AnyMessage {
            case addChild(name: String, props: Props<TestActor>)
            case passChild(name: String, props: Props<TestActor>)
        }

        class TestActor: Actor {
            typealias ParamType = XCTestExpectation

            var context: ActorContext!
            let startExpect: XCTestExpectation

            unowned var child: ActorRef!

            required init(_ param: ParamType) {
                self.startExpect = param
            }

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
                guard let msg = msg as? Message else {
                    XCTFail()
                    return .same
                }

                switch msg {
                case .addChild(let name, let props):
                    self.child = self.spawn(props, name: name)
                case .passChild(let name, let props):
                    self.child ! Message.addChild(name: name, props: props)

                }

                return .same
            }

            func preStart() {
                startExpect.fulfill()
            }
        }

        let parentExpect = expectation(description: "parentStart")
        let childExpect = expectation(description: "childStart")
        let subchildExpect = expectation(description: "subchildStart")

        let parentProps = Props(TestActor.self, param: parentExpect)
        let childProps = Props(TestActor.self, param: childExpect)
        let subchildProps = Props(TestActor.self, param: subchildExpect)

        // Act
        let parent = (echo as! EchoActor).spawn(parentProps, name: "parent")

        parent ! Message.addChild(name: "child", props: childProps)
        parent ! Message.passChild(name: "subchild", props: subchildProps)

        // Assert
        wait(for: [parentExpect, childExpect, subchildExpect], timeout: 1, enforceOrder: true)
    }

    /// Creates an actor hierarchy with a parent, child and subchild actors. Checks if the order of stop lifecycle
    /// callbacks is correct.
    func testStopHierarchy() {
        // Arrange
        enum Message: AnyMessage {
            case addChild(name: String, props: Props<TestActor>)
            case passChild(name: String, props: Props<TestActor>)
        }

        class TestActor: Actor {
            typealias ParamType = [XCTestExpectation]

            var context: ActorContext!
            let startExpect: XCTestExpectation
            let stopExpect: XCTestExpectation

            unowned var child: ActorRef!

            required init(_ param: ParamType) {
                self.startExpect = param[0]
                self.stopExpect = param[1]
            }

            lazy var receive = behavior { [unowned self] msg -> ActionResult in
                guard let msg = msg as? Message else {
                    XCTFail()
                    return .same
                }

                switch msg {
                case .addChild(let name, let props):
                    self.child = self.spawn(props, name: name)
                case .passChild(let name, let props):
                    self.child ! Message.addChild(name: name, props: props)
                }

                return .same
            }

            func preStart() {
                startExpect.fulfill()
            }

            func postStop() {
                stopExpect.fulfill()
            }
        }

        let parentProps = Props(TestActor.self,
                                param: [expectation(description: "parentStart"),
                                         expectation(description: "parentStop")])

        let childProps = Props(TestActor.self,
                               param: [expectation(description: "childStart"),
                                        expectation(description: "childStop")])

        let subchildProps = Props(TestActor.self,
                                  param: [expectation(description: "subchildStart"),
                                           expectation(description: "subchildStop")])

        let parent = (echo as! EchoActor).spawn(parentProps, name: "parent")
        parent ! Message.addChild(name: "child", props: childProps)
        parent ! Message.passChild(name: "subchild", props: subchildProps)

        wait(for: [parentProps.param[0], childProps.param[0], subchildProps.param[0]],
             timeout: 1, enforceOrder: true)

        // Act
        parent ! SystemMessage.poisonPill

        // Assert
        wait(for: [subchildProps.param[1], childProps.param[1], parentProps.param[1]],
             timeout: 1, enforceOrder: true)
    }

    func testWatchChild() {
        // Arrange

        enum Action: AnyMessage {
            case poisonChild(Int)
        }

        class ParentActor: Actor {
            typealias ParamType = [XCTestExpectation]

            var children: [ActorRef] = []
            var context: ActorContext!
            let expectations: [XCTestExpectation]

            required init(_ param: ParamType) {
                self.expectations = param
            }

            lazy var receive = behavior { [unowned self] in

                switch $0 {
                case let msg as Action:

                    switch msg {
                    case .poisonChild(let index):
                        let child = self.children[index]
                        child.tell(message: .poisonPill)

                    }

                case let msg as NotificationMessage:

                    switch msg {
                    case .terminated(let actor):
                        let firstIndex = self.children.firstIndex { $0 === actor }

                        guard let index = firstIndex else {
                            XCTFail()
                            return .unhandled
                        }

                        self.expectations[index].fulfill()
                    }

                default: return .unhandled
                }


                return .same
            }

            func preStart() {
                children = (0..<5).map {
                    spawn(echoActorProps, name: "child_\($0)")
                }

                for child in children {
                    context.watch(child)
                }

            }
        }

        let expectations = (0..<5).map {
            expectation(description: "stopped_child_\($0)")
        }

        let props = Props(ParentActor.self,
                          param: expectations)

        let parent = system.spawn(props, name: "parent")

        // Act
        for i in 0..<5 {
            parent ! Action.poisonChild(i)
        }

        // Assert
        // Note that children may not stop in order of poison, if running on different
        // dispatch queues.
        wait(for: expectations, timeout: 1)
    }

}

