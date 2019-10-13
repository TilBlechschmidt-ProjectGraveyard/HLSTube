//
//  StreamAPI.swift
//  HLSTube
//
//  Created by Til Blechschmidt on 12.10.19.
//

import Foundation
import Combine

public enum StreamAPIError: Error {
    case invalidRequestURL
    case invalidResponse
}

public struct StreamAPI {
    fileprivate static let videoInfoPath = "https://www.youtube.com/get_video_info?video_id=%@&asv=3&el=detailpage&ps=default&hl=en_US"
    
    private static func streamDictionaries(forVideoID videoID: VideoID) -> AnyPublisher<[[String: String]], Error> {
        return Future { observer in
            // Build the request URL
            let path = String(format: StreamAPI.videoInfoPath, videoID)
            guard let url = URL(string: path) else {
                observer(.failure(StreamAPIError.invalidRequestURL))
                return
            }

            // Build the request
            var req = URLRequest(url: url)
            req.addValue("en", forHTTPHeaderField: "Accept-Language")

            // Send the request
            let session = URLSession(configuration: URLSessionConfiguration.default)
            session.dataTask(with: req) { data, _, error in
                // Convert the response to a string
                guard let data = data, !data.isEmpty, let urlParameters = String(data: data, encoding: .utf8) else {
                    observer(.failure(StreamAPIError.invalidResponse))
                    return
                }

                // Parse the returned data as URL parameters
                let dictionary = dictionaryFromURL(parameterStrings: urlParameters.components(separatedBy: "&"))
                
                if let errorCode = dictionary["errorcode"], errorCode == "2" {
                    observer(.failure(StreamAPIError.invalidRequestURL))
                    return
                }
                
                // Extract the list of streams and convert them to dictionaries
                guard let adaptiveFormats = dictionary["adaptive_fmts"] else {
                    observer(.failure(StreamAPIError.invalidResponse))
                    return
                }

                let streams = adaptiveFormats.components(separatedBy: ",")
                let formattedStreamDictionaries = streams.map { stream in
                    return dictionaryFromURL(parameterStrings: stream.split(separator: "&").map(String.init))
                }

                observer(.success(formattedStreamDictionaries))
            }.resume()
        }.eraseToAnyPublisher()
    }

    public static func streams(forVideoID videoID: String) -> AnyPublisher<[StreamDescriptor], Error> {
        return streamDictionaries(forVideoID: videoID)
            .flatten()
            .flatMap {
                StreamDescriptor.create(fromDict: $0, videoID: videoID)
            }
            .collect()
            .eraseToAnyPublisher()
    }
}

private func dictionaryFromURL(parameterStrings: [String]) -> [String: String] {
    return parameterStrings.reduce(into: [:]) { result, variable in
        let keyValue = variable.components(separatedBy: "=")
        if keyValue.count == 2, let decoded = keyValue[1].removingPercentEncoding {
            result[keyValue[0]] = decoded
        } else {
            print("Failed to parse URL parameter: \(keyValue)")
        }
    }
}

extension Publisher where Output: Sequence {
    func flatten() -> Publishers.FlatMap<Publishers.Sequence<Output, Failure>, Self> {
        return self.flatMap { Publishers.Sequence(sequence: $0) }
    }
}
