import XCTest

@testable import ElasticLog
@testable import Logging

final class ElasticLogTests: XCTestCase {
    func testExample() throws {
        let e = expectation(description: "execution complete")
        
        let settings = ElasticLogSystem.Settings(host: "localhost", port: 12345, logLevel: .debug)
        
        LoggingSystem.bootstrapInternal(try ElasticLogSystem.bootstrapFactory(with: settings))
        
        let logger = Logger(label: #function)
        
        measure {
            logger.info("testMessage", metadata: nil)
        }
        sleep(1)
        e.fulfill()
        
        waitForExpectations(timeout: 5)
    }
    
    func testUDPExample() throws {
        //let e = expectation(description: "execution complete")
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        //XCTAssertEqual(ElasticLog().text, "Hello, World!")
        
//        let client = try UDPClient()
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
//        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
//        let logHandler = ElasticLogHandler(label: "testLogger", loglevel: .debug, tcpClient: client, formatter: dateFormatter)
        
        //logHandler.log(level: .info, message: "testMessage", metadata: nil, file: "Hello", function: "func", line: 0)
        
        //"2019-12-20T04:04:43.260Z info testLogger :  testMessage"
//        let dic = [
//            "message": "testMessageUDP",
//            "label": "testLogger",
//            "level": "info",
//            "timestamp": "\(dateFormatter.string(from: Date()))"
//        ]
//        let encoder = JSONEncoder()
//        let data = try encoder.encode(dic)
//        client.execute("\(String(data: data, encoding: .utf8)!)")
//            .whenComplete { result in
//                switch result {
//                case .failure(let error):
//                    print("Error: \(error)")
//                case .success(let res):
//                    print("Data: \(String(data: res, encoding: .utf8) ?? "")")
//                    print(res)
//                }
//        }
//        sleep(1)
//        e.fulfill()
//
//        waitForExpectations(timeout: 5)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
