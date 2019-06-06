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
    var echo: EchoActor!
    
    override func setUp() {
        system = ActorSystem(name: "system")
        echo = system.spawn(name: "echo", actor: EchoActor())
    }
    
    override func tearDown() {
        system.stop()
        system = nil
        echo = nil
    }
    
    /// Tests adding one child to the root, and sending parent a message.
    func testAddChildToRoot() {
        // Arrange
        let expects = [ expectation(description: "Ping"),
                        expectation(description: "parentPint") ]
        
        class ParentForwardActor: Actor {
            var context: ActorContext!
            
            let expects: [XCTestExpectation]
            
            lazy var receive: Behavior = { [unowned self] msg -> Receive in
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
            
            init(_ e: [XCTestExpectation]) {
                expects = e
            }
        }
        
        // Act
        let forwardActor = echo.spawn(name: "child", actor: ParentForwardActor(expects))
        forwardActor ! "ping"
        forwardActor ! "pingParent"
        
        // Assert
        wait(for: expects, timeout: 1, enforceOrder: true)
    }
    
    func testAddChild() {
        // Arrange
        class PingerActor: Actor {
            var context: ActorContext!
            let expect: XCTestExpectation
            
            lazy var receive: Behavior = { [unowned self] msg -> Receive in
                guard let msg = msg as? String else {
                    XCTFail()
                    return .same
                }
                
                if msg == "createChild" {
                    self.spawn(name: "pingChild", actor: PingActor())
                }
                if msg == "pingChild" {
                    self.context.children["pingChild"]! ! ("ping", self)
                }
                if msg == "ping_back" {
                    XCTAssert(self.context.sender() === self.context.children["pingChild"])
                    self.expect.fulfill()
                }
                
                return .same
            }
            
            init(_ e: XCTestExpectation) {
                expect = e
            }
        }
        
        class PingActor: Actor {
            var context: ActorContext!
            
            lazy var receive: Behavior = { [unowned self] msg -> Receive in
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
        }
        
        let expect = expectation(description: "pingBack")
        
        // Act
        let parent = echo.spawn(name: "parent", actor: PingerActor(expect))
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
            case addChild(name: String, actor: TestActor)
            case passChild(name: String, actor: TestActor)
        }
        
        class TestActor: Actor {
            var context: ActorContext!
            let startExpect: XCTestExpectation
            
            unowned var child: Actor!
            
            init(start: XCTestExpectation) {
                startExpect = start
            }
            
            lazy var receive: Behavior = { [unowned self] msg -> Receive in
                guard let msg = msg as? Message else {
                    XCTFail()
                    return .same
                }
                
                switch msg {
                case .addChild(let name, let actor):
                    self.child = self.spawn(name: name, actor: actor)
                case .passChild(let name, let actor):
                    self.child ! Message.addChild(name: name, actor: actor)
                    
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
        
        // Act
        let parent = echo.spawn(name: "parent", actor: TestActor(start: parentExpect))
        parent ! Message.addChild(name: "child", actor: TestActor(start: childExpect))
        parent ! Message.passChild(name: "subchild", actor: TestActor(start: subchildExpect))
        
        // Assert
        wait(for: [parentExpect, childExpect, subchildExpect], timeout: 1, enforceOrder: true)
    }
    
    /// Creates an actor hierarchy with a parent, child and subchild actors. Checks if the order of stop lifecycle
    /// callbacks is correct.
    func testStopHierarchy() {
        // Arrange
        enum Message: AnyMessage {
            case addChild(name: String, actor: TestActor)
            case passChild(name: String, actor: TestActor)
        }
        
        class TestActor: Actor {
            var context: ActorContext!
            let startExpect: XCTestExpectation
            let stopExpect: XCTestExpectation
            
            unowned var child: Actor!
            
            init(start: XCTestExpectation, stop: XCTestExpectation) {
                startExpect = start
                stopExpect = stop
            }
            
            lazy var receive: Behavior = { [unowned self] msg -> Receive in
                guard let msg = msg as? Message else {
                    XCTFail()
                    return .same
                }
                
                switch msg {
                case .addChild(let name, let actor):
                    self.child = self.spawn(name: name, actor: actor)
                case .passChild(let name, let actor):
                    self.child ! Message.addChild(name: name, actor: actor)
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
        
        let parentStartExpect = expectation(description: "parentStart")
        let childStartExpect = expectation(description: "childStart")
        let subchildStartExpect = expectation(description: "subchildStart")
        
        let parentStopExpect = expectation(description: "parentStop")
        let childStopExpect = expectation(description: "childStop")
        let subchildStopExpect = expectation(description: "subchildStop")
        
        let parent = echo.spawn(name: "parent", actor: TestActor(start: parentStartExpect, stop: parentStopExpect))
        parent ! Message.addChild(name: "child",
                                  actor: TestActor(start: childStartExpect, stop: childStopExpect))
        parent ! Message.passChild(name: "subchild",
                                   actor: TestActor(start: subchildStartExpect, stop: subchildStopExpect))
        wait(for: [parentStartExpect, childStartExpect, subchildStartExpect], timeout: 1, enforceOrder: true)
        
        // Act
        parent.stop()
        
        // Assert
        wait(for: [subchildStopExpect, childStopExpect, parentStopExpect], timeout: 1, enforceOrder: true)
    }
    
}
