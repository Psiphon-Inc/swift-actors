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

class PatternsTests: XCTestCase {
    
    var system: ActorSystem!
    
    override func setUp() {
        system = ActorSystem(name: "system")
    }
    
    override func tearDown() {
        system.stop()
        system = nil
    }
    
    func testAskPatternBasicFunctionality() {
        // Arrange
        let echo = system.spawn(name: "echo", actor: EchoActor())
        let done = expectation(description: "testDone")
        
        // Act
        ask(actor: echo, message: 1).then { result in
            // Assert
            guard let result = result as? Int else {
                XCTFail()
                return
            }
            XCTAssert(result == 2)
            done.fulfill()
        }
        
        wait(for: [done], timeout: 1)
    }
    
    func testAskPatternTimeout() {
        // Arrange
        let echo = system.spawn(name: "echo", actor: EchoActor())
        let done = expectation(description: "testDone")
        
        // Act
        let msg = EchoActor.Action.respondWithDelay(interval: 0.2, value: 1)
        ask(actor: echo, message: msg, timeoutMillis: 100).catch { err in
            // Assert
            if case ActorErrors.timeout = err {
                done.fulfill()
            } else {
                XCTFail()
            }
        }
        
        wait(for: [done], timeout: 1)
    }
    
    func testBangBangOperator() {
        // Arrange
        let echo = system.spawn(name: "echo", actor: EchoActor())
        let done = expectation(description: "testDone")
        
        // Act
        (echo !! 1).then { result in
            // Assert
            guard let result = result as? Int else {
                XCTFail()
                return
            }
            XCTAssert(result == 2)
            done.fulfill()
        }
        
        wait(for: [done], timeout: 1)
    }
    
    func testBangBangOperatorWithTimeout() {
        // Arrange
        let echo = system.spawn(name: "echo", actor: EchoActor())
        let done = expectation(description: "testDone")
        
        // Act
        let msg = EchoActor.Action.respondWithDelay(interval: 0.2, value: 1)
        (echo !! (msg, 100)).catch { err in
            // Assert
            if case ActorErrors.timeout = err {
                done.fulfill()
            } else {
                XCTFail()
            }
        }
        
        wait(for: [done], timeout: 1)
    }
    
}
