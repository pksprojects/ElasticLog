import XCTest

@testable import ElasticLog
@testable import Logging

final class ElasticLogTests: XCTestCase {

    func test_bootstrap_swift_log() throws {
        let e = expectation(description: "execution complete")

        let settings = ElasticLogSystem.Settings(logLevel: .debug, appenderSettings: [
            LogstashTCPAppender.Settings(host: "localhost", port: 12345),
        ])
        
        try ElasticLogSystem.bootstrapSwiftLog(with: settings)

        let logger = Logger(label: #function)

        measure {
            logger.info("Test bootstrap swift-log", metadata: nil)
        }
        sleep(1)
        e.fulfill()

        waitForExpectations(timeout: 5)
    }

    func test_LogstashTCPAppender() throws {
        let e = expectation(description: "execution complete")

        let settings = ElasticLogSystem.Settings(logLevel: .debug, appenderSettings: [
            LogstashTCPAppender.Settings(host: "localhost", port: 12345),
        ])
        LoggingSystem.bootstrapInternal(try ElasticLogSystem.bootstrapFactory(with: settings))

        let logger = Logger(label: #function)

        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 1000
        if #available(OSX 10.15, *) {
            measure(options: measureOptions) {
                logger.info("TCP test message", metadata: nil)
            }
        } else {
            measure {
                logger.info("TCP test message", metadata: nil)
            }
        }
        sleep(1)
        e.fulfill()

        waitForExpectations(timeout: 5)
    }

    func test_LogstashUDPAppender() throws {
        let e = expectation(description: "execution complete")

        let settings = ElasticLogSystem.Settings(logLevel: .debug, appenderSettings: [
            LogstashUDPAppender.Settings(host: "0.0.0.0", port: 9090),
        ])
        LoggingSystem.bootstrapInternal(try ElasticLogSystem.bootstrapFactory(with: settings))

        let logger = Logger(label: #function)

        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 1000
        if #available(OSX 10.15, *) {
            measure(options: measureOptions) {
                logger.info("UDP test message", metadata: nil)
            }
        } else {
            measure {
                logger.info("UDP test message", metadata: nil)
            }
        }
        sleep(1)
        e.fulfill()

        waitForExpectations(timeout: 5)
    }
    
    func test_External_Log_Handlers() throws {
        let e = expectation(description: "execution complete")

        let settings = ElasticLogSystem.Settings(logLevel: .debug, appenderSettings: [
            LogstashUDPAppender.Settings(host: "0.0.0.0", port: 9090),
        ], handlerFactories: [StreamLogHandler.standardOutput])
        LoggingSystem.bootstrapInternal(try ElasticLogSystem.bootstrapFactory(with: settings))

        let logger = Logger(label: #function)

        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 1000
        if #available(OSX 10.15, *) {
            measure(options: measureOptions) {
                logger.info("UDP test message", metadata: nil)
            }
        } else {
            measure {
                logger.info("UDP test message", metadata: nil)
            }
        }
        sleep(1)
        e.fulfill()

        waitForExpectations(timeout: 5)
    }
}
