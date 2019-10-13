//
//  HLSBuilder.swift
//  HLSServer
//
//  Created by Til Blechschmidt on 20.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation
import Combine

public typealias VideoID = String
public typealias ITag = String

enum HLSBuilderError: Error {
    case itagDescriptorNotFound
    case unableToReadSegmentData
}

class HLSBuilder {
    private var cache: [VideoID: [ITag: StreamDescriptor]] = [:]

    private func addToCache(_ streamDescriptor: StreamDescriptor, videoID: VideoID) {
        if cache.index(forKey: videoID) == nil {
            cache[videoID] = [:]
        }
        
        if let itag = streamDescriptor.itag {
            cache[videoID]?[itag] = streamDescriptor
        }
    }

    private func streamsDescriptors(forVideoID videoID: VideoID) -> AnyPublisher<[StreamDescriptor], Error> {
        // TODO Take cache age into account (after a certain time the cache invalidates because the URLs expire)
        if let descriptors = cache[videoID] {
            return Just(Array(descriptors.values))
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        } else {
            return StreamAPI.streams(forVideoID: videoID)
        }
    }

    public func masterPlaylist(forVideoID videoID: VideoID) -> AnyPublisher<String, Error> {
        let m3u8Header = """
        #EXTM3U
        #EXT-X-VERSION:4


        """

        return streamsDescriptors(forVideoID: videoID)
            .reduce([], { $0 + $1 })
            .flatMap { Publishers.Sequence(sequence: $0) }
            .filter { $0.mimeType?.contains("mp4") ?? false } // Since HLS only supports fMP4 streams we can dump all the webm streams
            // TODO We probably need to filter the codecs to not include vp9
            .handleEvents(receiveOutput: { streamDescriptor in
                self.addToCache(streamDescriptor, videoID: videoID)
            })
            .map { streamDescriptor in
                let streamManifestURL = "\(videoID)/\(streamDescriptor.itag ?? "invalidITag").m3u8"
                if streamDescriptor.audioChannels != nil {
                    return """
                    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",LANGUAGE="en",NAME="English",DEFAULT=YES,AUTOSELECT=YES,URI="\(streamManifestURL)"
                    """
                } else {
                    return """
                    #EXT-X-STREAM-INF:BANDWIDTH=\(streamDescriptor.bitrate ?? 0),CODECS="\(streamDescriptor.codecs ?? "")",RESOLUTION=\(streamDescriptor.width ?? 0)x\(streamDescriptor.height ?? 0),AUDIO="aac"
                    \(streamManifestURL)
                    """
                }
            }
            .collect()
            .map { m3u8Header + $0.joined(separator: "\n") }
            .eraseToAnyPublisher()
    }

    public func playlist(forVideoID videoID: VideoID, itag: ITag) -> AnyPublisher<String, Error> {
        return streamsDescriptors(forVideoID: videoID)
            .flatten()
            .filter { $0.itag == itag }
            .collect()
            .tryMap { descriptors in
                guard descriptors.count == 1, let descriptor = descriptors.first else {
                    throw HLSBuilderError.itagDescriptorNotFound
                }

                return descriptor
            }
            .flatMap { (descriptor: StreamDescriptor) -> Future<String, Error> in
                return Future { observer in
                    guard let path = descriptor.url, let url = URL(string: path), let index = descriptor.index else {
                        observer(.failure(HLSBuilderError.unableToReadSegmentData))
                        return
                    }
                    
                    var request = URLRequest(url: url)
                    request.setValue("bytes=\(index.lowerBound)-\(index.upperBound)", forHTTPHeaderField: "Range")
                    
                    let task = URLSession.shared.dataTask(with: request) { (data, request, error) in
                        guard let data = data else {
                            observer(.failure(HLSBuilderError.unableToReadSegmentData))
                            return
                        }

                        do {
                            let info = try SegmentInformation(fromData: data, inRange: 0..<index.count+1)
                            observer(.success(info.generateM3U8(withFilePath: path)))
                        } catch {
                            observer(.failure(error))
                        }
                    }

                    task.resume()
                }
            }
            .eraseToAnyPublisher()
    }
}
