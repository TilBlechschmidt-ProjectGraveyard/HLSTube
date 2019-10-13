//
//  StreamDescriptor.swift
//  HLSTube
//
//  Created by Til Blechschmidt on 12.10.19.
//

import Foundation
import Combine

public struct StreamDescriptor {
    public let url: String?
    public let itag: String?
    public let mimeType: String?
    public let codecs: String?

    public let index: Range<Int>?
    public let initRange: Range<Int>?

    public let bitrate: UInt32?
    public let fps: UInt8?

    public let width: UInt16?
    public let height: UInt16?

    public let qualityLabel: String?

    public let audioSampleRate: UInt32?
    public let audioChannels: UInt8?

    static func create(fromDict data: [String: String], videoID: VideoID) -> AnyPublisher<StreamDescriptor, Error> {
        let itag = data["itag"]
        let type = data["type"]?.components(separatedBy: ";+codecs=")
        let mimeType = type?[0]
        let codecs = type?[1].dropFirst(1).dropLast(1)
        
        var index: Range<Int>? = nil
        if let indexComponents = data["index"]?.components(separatedBy: "-").compactMap(Int.init) {
            index = indexComponents[0]..<indexComponents[1]
        }
        
        var initRange: Range<Int>? = nil
        if let initComponents = data["init"]?.components(separatedBy: "-").compactMap(Int.init) {
            initRange = initComponents[0]..<initComponents[1]
        }
        
        let bitrate = data["bitrate"].flatMap(UInt32.init)
        let fps = data["fps"].flatMap(UInt8.init)

        var width: UInt16? = nil
        var height: UInt16? = nil
        if let sizeComponents = data["size"]?.components(separatedBy: "x") {
            width = UInt16(sizeComponents[0])
            height = UInt16(sizeComponents[1])
        }

        let qualityLabel = data["quality_label"]

        let audioSampleRate = data["audio_sample_rate"].flatMap(UInt32.init)
        let audioChannels = data["audio_channels"].flatMap(UInt8.init)
        
        var url = data["url"]
        
        let buildDescriptor = {
            return StreamDescriptor(
                url: url,
                itag: itag,
                mimeType: mimeType,
                codecs: codecs.flatMap { String($0) },
                index: index,
                initRange: initRange,
                bitrate: bitrate,
                fps: fps,
                width: width,
                height: height,
                qualityLabel: qualityLabel,
                audioSampleRate: audioSampleRate,
                audioChannels: audioChannels)
        }
        
        return Future { observer in
            // Handle encryption
            if let signature = data["signature"] {
                url = url.flatMap { $0 + "&signature=\(signature)" }
                observer(.success(buildDescriptor()))
            } else if let encryptedSignature = data["s"] {
                // TODO Find better solution for this pure evil
                var cancellable: AnyCancellable? = nil
                cancellable = SignatureAPI.shared.decrypt(signature: encryptedSignature, videoID: videoID).sink(receiveCompletion: { result in
                    cancellable = nil

                    switch result {
                    case .finished:
                        break
                    case .failure(let error):
                        print(error)
                    }

                    observer(.success(buildDescriptor()))
                }, receiveValue: { decryptedSignature in
                    url = url.flatMap { $0 + "&sig=\(decryptedSignature)" }
                })
            } else {
                observer(.success(buildDescriptor()))
            }
        }.eraseToAnyPublisher()
    }
}
