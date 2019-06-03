import XCTest
import SwiftActors

extension XCTestExpectation: AnyMessage {}

class NoOpActor: Actor {
    
    typealias MessageType = XCTestExpectation
    
    var context: ActorContext<XCTestExpectation>!
    
    lazy var behavior: Behavior = { msg -> Receive<XCTestExpectation> in
        msg.fulfill()
        return .same
    }
    
}

struct Response: AnyMessage {
    let result: String
}

class MyMessage: AnyMessage {}

class MyOtherMessage<T: Actor>: MyMessage {
    let sender: T
    init(sender: T) {
        self.sender = sender
    }
}

class MyResponse: AnyMessage {}

class BasicActor: Actor {
    
    typealias MessageType = MyMessage
    
    var context: ActorContext<MyMessage>!
    
    var behavior: Behavior = { msg -> Receive<MyMessage> in
        
        switch msg {
        case let msg as MyOtherMessage<<#T: Actor#>>:
            break
        default:
            break
        }
        
        print("received message \(msg)")
        return .same
    }
    
}

enum Request: AnyMessage {
    case ping(value: String, replyTo: (String) -> Void)
}

class Ping: Actor {
    typealias MessageType = Request
    
    var context: ActorContext<Request>!
    
    var behavior: Behavior = { msg -> Receive<Request> in
        switch msg {
        case .ping(let value, let replyTo):
            replyTo(value)
        }
        return .same
    }
    
}


final class ActorBasicTests: XCTestCase {

    var system: ActorSystem!
    
    override func setUp() {
        system = ActorSystem(name: "test")
    }
    
    override func tearDown() {
        system.stop()
        system = nil
    }
    
    func testAsk() {
        
    }
    
    func testPingActor() {
        
        enum TestMessage: AnyMessage {
            case createPinger
            case pingPinger
            case result(String)
        }
        
        class TestActor: Actor {
            typealias MessageType = TestMessage
            var context: ActorContext<TestMessage>!
            var pinger: Ping!
            var expect: XCTestExpectation
            
            lazy var behavior: Behavior = { msg -> Receive<TestMessage> in
                switch msg {
                case .createPinger:
                    self.pinger = self.spawn(name: "ping", actor: Ping())
                case .pingPinger:
                    self.pinger.tell(message: .ping(value: "hello", replyTo: { result in
                        self.tell(message: .result(result))
                    }))
                    break
                case .result(let value):
                    XCTAssert(value == "hello")
                    self.expect.fulfill()
                }
                return .same
            }
            
            init(_ e: XCTestExpectation) {
                expect = e
            }
        }
        
        let expect = expectation(description: "pingHello")
        let testActor = system.spawn(name: "test", actor: TestActor(expect))
        testActor.tell(message: .createPinger)
        testActor.tell(message: .pingPinger)
        
        wait(for: [expect], timeout: 1)
    }
    
    func testOneMessageSend() {
        let ref = system.spawn(name: "testActor", actor: NoOpActor())
        
        let expect = expectation(description: "receive message")
        ref.tell(message: expect)
        wait(for: [expect], timeout: 1)
    }
    
    func testMultipleMessageSend() {
        let ref = system.spawn(name: "testActor", actor: NoOpActor())
        var expectations = [XCTestExpectation]()
        
        for _ in 1...10 {
            let expect = expectation(description: "receive message")
            expectations.append(expect)
            ref.tell(message: expect)
        }
        
        wait(for: expectations, timeout: 1, enforceOrder: true)
    }
    
    func testMessageSendActorToActor() {
        
        enum Forwarding: AnyMessage {
            case forward(to: NoOpActor)
        }
        
        class ForwardingActor: Actor {
            typealias MessageType = Forwarding
            
            let forwardExpect: XCTestExpectation
            let noopExpect: XCTestExpectation
            
            var context: ActorContext<Forwarding>!
            
            lazy var behavior: Behavior = {
                switch $0 {
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
        
        let forwardingActor = system.spawn(name: "forwarding",
                                           actor: ForwardingActor(forwardExpect: forwardExpect, noopExpect: noopExpect))
        
        let noopActor = system.spawn(name: "noop", actor: NoOpActor())
        
        // Sends first message to forwarding actor
        forwardingActor.tell(message: Forwarding.forward(to: noopActor))
        
        wait(for: [forwardExpect, noopExpect], timeout: 1, enforceOrder: true)
    }
    
    func testMessageSendPerf() {
        
        class MultipleMsg: Actor {
            typealias MessageType = Int
            let expects: [XCTestExpectation]
            var context: ActorContext<Int>!
            
            lazy var behavior: Behavior = {
                self.expects[$0].fulfill()
                return .same
            }
            
            init(_ e: [XCTestExpectation]) {
                expects = e
            }
        }
        
        let expects = [ expectation(description: "0"),
                        expectation(description: "1"),
                        expectation(description: "2"),
                        expectation(description: "3"),
                        expectation(description: "4"),
                        expectation(description: "5"),
                        expectation(description: "6"),
                        expectation(description: "7"),
                        expectation(description: "8"),
                        expectation(description: "9") ]
        
        let actor = system.spawn(name: "multiple", actor: MultipleMsg(expects))
        var i = 0
        
        self.measure {
            actor.tell(message: i)
            wait(for: [expects[i]], timeout: 1)
            i += 1
        }
        
    }

//    static var allTests = [
//        ("testExample", testExample),
//    ]
}
