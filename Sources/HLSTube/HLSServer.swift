//
//  HLSServer.swift
//  HLSServer
//
//  Created by Til Blechschmidt on 20.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Network
import Combine

public class HLSServer {
    private let listener: NWListener
    private let hlsBuilder = HLSBuilder()

    public init(port: UInt16) throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: port))
    }

    private func response(status: String, contentType: String = "application/vnd.apple.mpegurl", contentLength: Int = 0, body: String = "") -> String {
        return """
        HTTP/1.1 \(status)\r
        Date: Thu, 20 May 2018 21:20:58 GMT\r
        Connection: close\r
        Content-Type: \(contentType)\r
        Content-Length: \(contentLength)\r
        \r
        \(body)
        """
    }

    private func notFound() -> AnyPublisher<String, Error> {
        return Just(response(status: "404 Not Found", contentType: "text/html"))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    private func badRequest(_ reason: String = "") -> AnyPublisher<String, Error> {
        return Just(response(status: "400 Bad Request", contentType: "text/html"))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    private func process(headers: [String]) -> [String: String] {
        return headers.reduce(into: [:]) { (acc, field) in
            let keyValue = field.components(separatedBy: ": ")
            if keyValue.count == 2 {
                acc[keyValue[0]] = keyValue[1]
            }
        }
    }

    private func process(httpRequest request: String) -> AnyPublisher<String, Error> {
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard !parts.isEmpty else { return badRequest("Invalid HTTP request") }
        var headers = parts[0].components(separatedBy: "\r\n")

        let requestSpecification = headers[0].components(separatedBy: " ")
        headers.remove(at: 0)
        guard requestSpecification.count == 3 else { return badRequest("Invalid HTTP request") }

        let url = requestSpecification[1]
        let urlParts = url.components(separatedBy: "/")

        if urlParts.count == 3 && urlParts[2].hasSuffix(".m3u8") {
            // Playlist m3u8
            let videoID = urlParts[1]
            let itag = urlParts[2].dropLast(5)

            return hlsBuilder.playlist(forVideoID: videoID, itag: String(itag)).map {
                self.response(status: "200 OK", contentLength: $0.count, body: $0)
            }.eraseToAnyPublisher()
        } else if urlParts.count == 2 && urlParts[1].hasSuffix(".m3u8") {
            // Master m3u8
            let videoID = urlParts[1].dropLast(5)

            return hlsBuilder.masterPlaylist(forVideoID: String(videoID)).map {
                self.response(status: "200 OK", contentLength: $0.count, body: $0)
            }.eraseToAnyPublisher()
        } else {
            // Should rather be 404
            return notFound()
        }
    }

    public func listen(onQueue queue: DispatchQueue = DispatchQueue.global()) {
        let maximumReceiveLength = 1000

        listener.newConnectionHandler = { connection in
            connection.receive(minimumIncompleteLength: 10, maximumLength: maximumReceiveLength) { data, _, _, _ in
                guard let data = data, let request = String(data: data, encoding: .utf8) else { return }

                var cancellable: AnyCancellable?
                
                cancellable = self.process(httpRequest: request).sink(
                    receiveCompletion: { result in
                        switch result {
                        case .finished:
                            break
                        case .failure(let error):
                            print("Error during request!", error)
                        }
                        
                        cancellable = nil
                    },
                    receiveValue: { response in
                        connection.send(content: response.data(using: .utf8), completion: .idempotent)
                    }
                )
            }
            connection.start(queue: DispatchQueue.global())
        }

        listener.start(queue: queue)
    }
}
