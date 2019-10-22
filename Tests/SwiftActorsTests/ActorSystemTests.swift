///*
//* Copyright (c) 2019, Psiphon Inc.
//* All rights reserved.
//*
//* This program is free software: you can redistribute it and/or modify
//* it under the terms of the GNU General Public License as published by
//* the Free Software Foundation, either version 3 of the License, or
//* (at your option) any later version.
//*
//* This program is distributed in the hope that it will be useful,
//* but WITHOUT ANY WARRANTY; without even the implied warranty of
//* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//* GNU General Public License for more details.
//*
//* You should have received a copy of the GNU General Public License
//* along with this program.  If not, see <http:www.gnu.org/licenses/>.
//*
//*/
//
//import XCTest
//@testable import SwiftActors
//
//class ActorSystemTests: XCTestCase {
//
//    func testRepeatedStops() {
//        // Arrange
//        class TestActor: Actor {
//            var context: ActorContext!
//            var receive = XCTestExpectation.be {
//                $0.fulfill()
//                return .same
//            }
//            required init(_ param: Void) {}
//        }
//
//        let testSystem = ActorSystem(name: #file)
//
//        let props = Props(TestActor.self, param: ())
//        let actor = testSystem.spawn(props, name: #function)
//
//        /// Waits for the actor to be started and process at least one message.
//        let expect = expectation(description: #function)
//        actor ! expect
//        wait(for: [expect], timeout: 1)
//
//        // Act
//        testSystem.stop()
//        testSystem.stop()
//        testSystem.stop()
//
//        // Assert
//        // Will never reach here if a race condition occurs with the stops.
//    }
//
//}
