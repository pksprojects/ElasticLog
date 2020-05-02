//
//  UDPClient.swift
//
//
//  Created by Prafull Kumar Soni on 12/22/19.
//

import Foundation
import Logging
import NIO
import NIOSSL

// MARK: - UDPClient

/// NIO based Basic UDP Client.
public class UDPClient {
    let group: EventLoopGroup
    let host: String
    let port: Int
    let bindHost: String
    let bindPort: Int
    let sslContext: NIOSSLContext?
    private let isSharedPool: Bool
    let socketAddress: SocketAddress

    let errorCallback: (Error?) -> Void = { _ in }

    public init(_ host: String, port: Int, bindHost: String, bindPort: Int, eventLoopProvider: EventLoopProvider = .createNew(threads: 1), sslContext: NIOSSLContext? = nil) throws {
        self.host = host
        self.port = port
        switch eventLoopProvider {
        case let .createNew(threads):
            group = MultiThreadedEventLoopGroup(numberOfThreads: threads)
            isSharedPool = false
        case let .shared(group):
            self.group = group
            isSharedPool = true
        }
        self.sslContext = sslContext
        socketAddress = try SocketAddress.makeAddressResolvingHost(self.host, port: self.port)
        self.bindHost = bindHost
        self.bindPort = bindPort
    }

    public func execute(_ data: Data) -> EventLoopFuture<Data> {
        let promise = group.next().makePromise(of: Data.self)
        let handler = UDPChannelHandler(for: data, remote: socketAddress, promise: promise)
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                if let sslContext = self.sslContext {
                    return channel.pipeline.addHandlerThrowing {
                        let openSslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.host)
                        return openSslHandler
                    }.flatMap {
                        channel.pipeline.addHandler(handler)
                    }
                } else {
                    return channel.pipeline.addHandler(handler)
                }
            }
        bootstrap.bind(host: bindHost, port: bindPort)
            .whenComplete { result in
                switch result {
                case let .failure(error):
                    promise.fail(error)
                case .success:
                    promise.succeed(Data())
                }
            }
        return promise.futureResult
    }

    deinit {
        if !self.isSharedPool {
            group.shutdownGracefully(self.errorCallback)
        }
    }
}

// MARK: - UDP Channel Handler

private final class UDPChannelHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let logger = Logger(label: "org.pksprojects.ElasticLog.UDPClient.UDPCHannelHandler")

    let data: Data
    let remoteAddress: SocketAddress
    let responsePromise: EventLoopPromise<Data>

    init(for data: Data, remote: SocketAddress, promise: EventLoopPromise<Data>) {
        self.data = data
        responsePromise = promise
        remoteAddress = remote
    }

    public func channelActive(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let addBuffer = AddressedEnvelope<ByteBuffer>(remoteAddress: remoteAddress, data: buffer)
        context.writeAndFlush(wrapOutboundOut(addBuffer), promise: nil)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var response = unwrapInboundIn(data)
        if let bytes = response.data.readBytes(length: response.data.readableBytes) {
            responsePromise.succeed(Data(bytes))
        } else {
            responsePromise.succeed(Data())
        }
        context.close(promise: nil)
    }
}
