import XCTest

@testable import ElasticLog
@testable import Logging

final class ElasticLogTests: XCTestCase {
    func testExample() throws {
        let e = expectation(description: "execution complete")

        let settings = ElasticLogSystem.Settings(logLevel: .debug, appenderSettings: [
            LogstashTCPAppender.Settings(host: "localhost", port: 12345),
        ])
        LoggingSystem.bootstrapInternal(try ElasticLogSystem.bootstrapFactory(with: settings))

        let logger = Logger(label: #function)

        measure {
            logger.info("testMessage", metadata: nil)
        }
        sleep(1)
        e.fulfill()

        waitForExpectations(timeout: 5)
    }

    func testTCPExample() throws {
        let e = expectation(description: "execution complete")

        let settings = ElasticLogSystem.Settings(logLevel: .debug, appenderSettings: [
            LogstashTCPAppender.Settings(host: "localhost", port: 12345),
        ])
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
        let e = expectation(description: "execution complete")

        let settings = ElasticLogSystem.Settings(logLevel: .debug, appenderSettings: [
            LogstashUDPAppender.Settings(host: "localhost", port: 9090, listenPort: 8080),
        ])
        LoggingSystem.bootstrapInternal(try ElasticLogSystem.bootstrapFactory(with: settings))

        let logger = Logger(label: #function)

        measure {
            logger.info("testMessage", metadata: nil)
        }
        sleep(1)
        e.fulfill()

        waitForExpectations(timeout: 5)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
