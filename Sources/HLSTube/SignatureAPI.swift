//
//  SignatureAPI.swift
//  HLSTube
//
//  Created by Til Blechschmidt on 13.10.19.
//

import Foundation
import Combine
import JavaScriptCore

enum SignatureAPIError: Error {
    case unableToParsePlayer
    case decryptionFunctionNotFound
    case decryptionFunctionNotParsable
    case helperObjectNotFound
    case helperObjectNotParsable
    case decryptionFailed
}

public class SignatureAPI {
    fileprivate static let videoPagePath = "https://www.youtube.com/watch?v=%@&gl=US&hl=en&has_verified=1&bpctr=9999999999"
    
    fileprivate static let targetDecryptionFunctionName = "decryptYouTubeSignature"
    
    private var decryptionCodeCache: [VideoID: CurrentValueSubject<String?, Error>] = [:]
    
    public static let shared = SignatureAPI()
    
    private init() {}
    
    private static func downloadWebpage(_ path: String) -> AnyPublisher<String, Error> {
        return Future { observer in
            // Build the request URL
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
                guard let data = data, !data.isEmpty, let body = String(data: data, encoding: .utf8) else {
                    observer(.failure(StreamAPIError.invalidResponse))
                    return
                }
                
                observer(.success(body))
            }.resume()
        }.eraseToAnyPublisher()
    }
    
    private static func extractDecryptionFunctionName(from playerCode: String) -> String? {
        let match = SimpleRegexMatcher.firstMatch(forPattern: "\\b[cs]\\s*&&\\s*[adf]\\.set\\([^,]+\\s*,\\s*encodeURIComponent\\s*\\(\\s*([a-zA-Z0-9$]+)\\(", in: playerCode)

        return match?.groups[1].flatMap { String($0) }
    }
    
    private static func extractDecryptionFunction(withName name: String, fromCode playerCode: String) -> (args: Substring, code: Substring)? {
        let regexTemplate = """
        (?x)
        (?:function\\s+%@|[{;,]\\s*%@\\s*=\\s*function|var\\s+%@\\s*=\\s*function)\\s*
        \\(([^)]*)\\)\\s*
        \\{([^}]+)\\}
        """
        let regex = String(format: regexTemplate, name, name, name)
        
        guard let match = SimpleRegexMatcher.firstMatch(forPattern: regex, in: playerCode),
            let args = match.groups[1],
            let code = match.groups[2]
        else {
            return nil
        }
        
        return (args: args, code: code)
    }
    
    private static func extractHelperObjectName(fromDecryptionCode code: String) -> Substring? {
        let objectNameMatch = SimpleRegexMatcher.firstMatch(forPattern: "; ?([a-zA-Z]+?)\\.", in: code)
        return objectNameMatch?.groups[1]
    }
    
    private static func extractHelperObject(withName name: String, fromCode playerCode: String) -> String? {
        let objectStartMatch = SimpleRegexMatcher.firstMatch(forPattern: "var \(name) ?= ?", in: playerCode)
        
        guard let objectStartRange = objectStartMatch?.ranges.first ?? nil else {
            return nil
        }
        
        let range = objectStartRange.lowerBound..<playerCode.endIndex
        let subCode = playerCode[range]

        var bracketCounter = 0
        var foundOpening = false
        var objectCode = ""
        
        for index in subCode.indices {
            let character = subCode[index]
            objectCode += String(character)
            
            if character == "{" {
                bracketCounter += 1
            } else if character == "}" {
                bracketCounter -= 1
            }
            
            if bracketCounter == 0 && foundOpening {
                break
            } else if bracketCounter > 0 {
                foundOpening = true
            }
        }
        
        if bracketCounter != 0 {
            return nil
        }
        
        return objectCode
    }
    
    private static func buildDecryptionCode(fromFunction function: (args: Substring, code: Substring), andHelperObject helperObject: String, functionName: String) -> String {
        return "\(helperObject); function \(functionName)(\(function.args)) { \(function.code) }"
    }
    
    private static func extractDecryptionCode(from playerCode: String, functionName: String = SignatureAPI.targetDecryptionFunctionName) throws -> String {
        guard let decryptionFunctionName = extractDecryptionFunctionName(from: playerCode) else {
            throw SignatureAPIError.decryptionFunctionNotFound
        }
        
        guard let decryptionFunction = extractDecryptionFunction(withName: decryptionFunctionName, fromCode: playerCode) else {
            throw SignatureAPIError.decryptionFunctionNotParsable
        }
        
        guard let helperObjectName = extractHelperObjectName(fromDecryptionCode: String(decryptionFunction.code)) else {
            throw SignatureAPIError.helperObjectNotFound
        }
        
        // TODO Split up and throw specific errors
        guard let helperObject = extractHelperObject(withName: String(helperObjectName), fromCode: playerCode) else {
            throw SignatureAPIError.helperObjectNotParsable
        }
        
        return buildDecryptionCode(fromFunction: decryptionFunction, andHelperObject: helperObject, functionName: functionName)
    }
    
    private static func decrypt(signature: String, withDecryptionCode code: String, functionName: String = SignatureAPI.targetDecryptionFunctionName) throws -> String {
        let context = JSContext()
        context?.evaluateScript(code)
        
        // TODO Add exception handler to handle execution errors properly

        guard let decryptionFunction = context?.objectForKeyedSubscript(functionName),
            let result = decryptionFunction.call(withArguments: [signature]),
            result.isString,
            let decryptedSignature = result.toString()
        else {
            throw SignatureAPIError.decryptionFailed
        }
        
        return decryptedSignature
    }
    
    public func decrypt(signature: String, videoID: VideoID) -> AnyPublisher<String, Error> {
        if let cacheEntry = decryptionCodeCache[videoID] {
            return cacheEntry
                .filter { $0 != nil }
                .map { $0! }
                .first()
                .tryMap { decryptionCode in
                    return try SignatureAPI.decrypt(signature: signature, withDecryptionCode: decryptionCode)
                }
                .eraseToAnyPublisher()
        } else {
            decryptionCodeCache[videoID] = CurrentValueSubject(nil)
        }
        
        let path = String(format: SignatureAPI.videoPagePath, videoID)
        
        return SignatureAPI.downloadWebpage(path)
            // Parse player path
            .tryMap {
                let match: Substring? = SimpleRegexMatcher.firstMatch(forPattern: "\"assets\":.+?\"js\":\\s*(\"[^\"]+\")", in: $0).flatMap { $0.groups[1] } ?? nil
                
                guard
                    let playerPath = match.flatMap({
                        String($0).data(using: .utf8).flatMap {
                            try? JSONDecoder().decode(String.self, from: $0)
                        }
                    })
                else {
                    throw SignatureAPIError.unableToParsePlayer
                }
                
                return "https://youtube.com" + playerPath
            }
            // Download the player
            .flatMap { SignatureAPI.downloadWebpage($0) }
            .tryMap { player in
                let decryptionCode = try SignatureAPI.extractDecryptionCode(from: player)
                
                self.decryptionCodeCache[videoID]?.send(decryptionCode)
                
                return try SignatureAPI.decrypt(signature: signature, withDecryptionCode: decryptionCode)
            }
            .eraseToAnyPublisher()
    }
}
