import Foundation
import NIO
import ArgumentParser


enum FingerError: Error {
    case invalidUserDirectory(_ userDirectory: String)
}

private final class FingerHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let verboseKey: String = "/W"
    private let userError: String = "user not found"

    private var received: String = ""
    private var answer: String = ""
    private var userDirectory: String
    private var verbose: Bool

    init(userDirectory: String, verbose: Bool) {

        if userDirectory.hasSuffix("/") {
            self.userDirectory = String(userDirectory.dropLast())
        } else {
            self.userDirectory = userDirectory
        }
        self.verbose = verbose
    }

    private func fileExists(username: String) -> Bool {
        let exists = FileManager.default.fileExists(atPath: "\(self.userDirectory)/\(username).txt")

        if self.verbose && !exists {
            print("[x] could not find \(username).txt in \(self.userDirectory)")
        }
        return exists
    }

    private func readFile(username: String) -> String {
        if !self.fileExists(username: username) {
            return userError
        }

        let url = URL(fileURLWithPath: "\(self.userDirectory)/\(username).txt")

        do {
            let data = try Data(contentsOf: url)
            if let contents = String(data: data, encoding: .utf8) {
                return contents
            }
        } catch {
            print("[x] error reading \(username).txt in \(self.userDirectory): ", error)
        }
        return userError
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {

        var byteBuffer = unwrapInboundIn(data)
        let r = byteBuffer.readString(length: byteBuffer.readableBytes) ?? "\r\n"

        received.append(r)

        if r.hasSuffix("\r\n") {

            // NOTE: won't support verbose
            let cleaned = received.replacingOccurrences(of: verboseKey, with: "")
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            print("[-] using tidied value: '\(trimmed)' from received value: '\(received)'")

            if trimmed == "" {
                self.answer = "[error]\r\nonly single user look-up is supporter at the moment."
            } else {
                answer = self.readFile(username: trimmed)
            }

            let answerResponse = "\(answer)\r\n"
            var buffOut = context.channel.allocator.buffer(capacity: answerResponse.count)
            buffOut.writeString(answerResponse)

            context.writeAndFlush(self.wrapOutboundOut(buffOut)).whenComplete {_ in
                if self.verbose {
                    print("[-] closing connection")
                }
                context.close(promise: nil)
              }
        }
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        if self.verbose {
            print("[-] channel read complete")
        }
        context.flush()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[x] error: ", error)
        context.close(promise: nil)
    }
}

struct Fingerd: ParsableCommand {
    @Flag(name: .shortAndLong, help: "Include more verbose output")
    var verbose = false

    @Option(name: .shortAndLong, help: "the port to use. NOTE: most clients will want the default.")
    var port: Int = 79

    @Option(name: .shortAndLong, help: "the address to run on.")
    var host: String = "::1"

    @Option(name: [.customShort("d"), .customLong("user-directory")], completion: .directory, help: "the directory where user text files are stored.")
    var userDirectory: String = "/tmp"

    mutating func run() throws {

        let userDirectory = NSString(string: self.userDirectory).expandingTildeInPath
        let verbose = self.verbose

        var isDir : ObjCBool = true
        if !FileManager.default.fileExists(atPath: userDirectory, isDirectory:&isDir) {
            throw FingerError.invalidUserDirectory(userDirectory)
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let bootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

            // Set the handlers that are appled to the accepted Channels
            .childChannelInitializer { channel in
                // Ensure we don't read faster than we can write by adding the BackPressureHandler into the pipeline.
                channel.pipeline.addHandler(BackPressureHandler()).flatMap { v in
                    channel.pipeline.addHandler(FingerHandler(userDirectory: userDirectory, verbose: verbose))
                }
            }

            // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
        defer {
            try! group.syncShutdownGracefully()
        }


        enum BindTo {
            case ip(host: String, port: Int)
            case unixDomainSocket(path: String)
        }

        let bindTarget: BindTo

        bindTarget = .ip(host: self.host, port: self.port)


        let channel = try { () -> Channel in
            switch bindTarget {
            case .ip(let host, let port):
                return try bootstrap.bind(host: host, port: port).wait()
            case .unixDomainSocket(let path):
                return try bootstrap.bind(unixDomainSocketPath: path).wait()
            }
        }()

        print("[-] server started and listening on \(channel.localAddress!)")
        print("[-] verbose: \(verbose)")
        print("[-] user directory: \(userDirectory)")

        // This will never unblock as we don't close the ServerChannel
        try channel.closeFuture.wait()

        print("[-] server closed")

    }
}

Fingerd.main()
