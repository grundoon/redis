import Async
import Bits
import Foundation

struct ByteScanner {
    private var buffer: ByteBuffer
    private var offset: Int

    var count: Int {
        return buffer.count - offset
    }

    mutating func pop() -> Byte? {
        defer { offset += 1 }
        return peek()
    }

    mutating func peek() -> Byte? {
        guard offset < count else {
            return nil
        }
        return self[0]
    }

    mutating func skip(count: Int) {
        offset += count
    }

    mutating func requirePop() throws -> Byte {
        guard let pop = self.pop() else {
            fatalError() // FIXME
        }
        return pop
    }

    mutating func consume(count: Int) -> ByteBuffer? {
        guard count + offset < buffer.count else {
            return nil
        }

        defer { offset += count }
        return ByteBuffer(
            start: buffer.baseAddress?.advanced(by: offset + count),
            count: count
        )
    }

    mutating func requireConsume(count: Int) throws -> ByteBuffer {
        guard let buffer = consume(count: count) else {
            fatalError()
        }
        return buffer
    }

    subscript(_ index: Int) -> Byte {
        return buffer[offset + index]
    }
}

/// Translates `ByteBuffer`s to `RedisData`.
internal final class RedisDataParser: TranslatingStream {
    typealias Input = ByteScanner

    typealias Output = RedisData

    /// Creates a new `RedisDataParser`
    init() {}

    /// See `TranslatingStream.translate(input:)`
    public func translate(input: inout TranslationInput) throws -> TranslationOutput {
        guard let next = input.next else {
            return .insufficient(nil)
        }

        guard next.count >= 1 else {
            return .insufficient(next)
        }

        var bytes = next
        switch try bytes.requirePop() {
        case .asterisk: fatalError()
        case .plus:
            guard let string = try bytes.extractSimpleString() else {
                return .insufficient(next)
            }

            let redisString = RedisData.simpleString(string)
            switch bytes.count {
            case 0: return .sufficient(redisString)
            default: return .excess(redisString, bytes)
            }
        default: fatalError()
        }
    }

    func append(_ suffix: ByteScanner, to prefix: ByteScanner) -> ByteScanner {
        fatalError()
    }
}

extension ByteScanner {
    mutating func extractSimpleString() throws -> String? {
        guard count >= 2 else {
            return nil
        }

        for i in 1..<count {
            if buffer[i - 1] == .carriageReturn && buffer[i] == .newLine {
                defer { skip(count: 2) }
                return try String(bytes: requireConsume(count: i - 1), encoding: .utf8)
            }
        }

        return nil
    }
}

//import Async
//import Bits
//import Foundation
//
///// Various states the parser stream can be in
//enum ProtocolParserState {
//    /// normal state
//    case ready
//
//    /// waiting for data from upstream
//    case awaitingUpstream
//}
//
///// A streaming Redis value parser
//internal final class RedisDataParser: Async.Stream {
//    /// See InputStream.Input
//    typealias Input = ByteBuffer
//
//    /// See OutputStream.RedisData
//    typealias Output = RedisData
//
//    /// The in-progress parsing value
//    var processing: PartialRedisData?
//
//    /// Use a basic output stream to implement server output stream.
//    var downstream: AnyInputStream<Output>?
//
//    /// Current state
//    var state: ProtocolParserState
//
//    var parsing: ByteBuffer? {
//        didSet {
//            parsedBytes = 0
//        }
//    }
//
//    var parsedBytes: Int = 0
//
//    /// Creates a new ValueParser
//    init() {
//        state = .ready
//    }
//
//    func input(_ event: InputEvent<ByteBuffer>) {
//        switch event {
//        case .close:
//            downstream?.close()
//        case .error(let error):
//            downstream?.error(error)
//        case .next(let next, let ready):
//            do {
//                self.parsing = next
//                try transform(ready)
//            } catch {
//                self.downstream?.error(error)
//            }
//        }
//    }
//
//    func output<S>(to inputStream: S) where S : Async.InputStream, Output == S.Input {
//        self.downstream = AnyInputStream(inputStream)
//    }
//
//    /// Parses a basic String (no \r\n's) `String` starting at the current position
//    fileprivate func simpleString(from input: ByteBuffer, at offset: inout Int) -> String? {
//        var carriageReturnFound = false
//        var base = offset
//
//        // Loops until the carriagereturn
//        detectionLoop: while offset < input.count {
//            offset += 1
//
//            if input[offset] == .carriageReturn {
//                carriageReturnFound = true
//                break detectionLoop
//            }
//        }
//
//        // Expects a carriage return
//        guard carriageReturnFound else {
//            return nil
//        }
//
//        // newline
//        guard offset < input.count, input[offset + 1] == .newLine else {
//            return nil
//        }
//
//        // past clrf
//        defer { offset += 2 }
//
//        // Returns a String initialized with this data
//        return String(bytes: input[base..<offset], encoding: .utf8)
//    }
//
//    /// Parses an integer associated with the token at the provided position
//    fileprivate func integer(from input: ByteBuffer, at offset: inout Int) throws -> Int? {
//        // Parses a string
//        guard let string = simpleString(from: input, at: &offset) else {
//            return nil
//        }
//
//        // Instantiate the integer
//        guard let number = Int(string) else {
//            throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//        }
//
//        return number
//    }
//
//    /// Parses the value for the provided Token at the current position
//    ///
//    /// - throws: On an unexpected result
//    /// - returns: The value (and if it's completely parsed) as a tuple, or `nil` if more data is needed to continue
//    fileprivate func parseToken(_ token: UInt8, from input: ByteBuffer, at position: inout Int) throws -> PartialRedisData {
//        switch token {
//        case .plus:
//            // Simple string
//            guard let string = simpleString(from: input, at: &position) else {
//                throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//            }
//
//            return .parsed(.basicString(string))
//        case .hyphen:
//            // Error
//            guard let string = simpleString(from: input, at: &position) else {
//                throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//            }
//
//            let error = RedisError(identifier: "serverSide", reason: string)
//            return .parsed(.error(error))
//        case .colon:
//            // Integer
//            guard let number = try integer(from: input, at: &position) else {
//                throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//            }
//
//            return .parsed(.integer(number))
//        case .dollar:
//            // Bulk strings start with their length
//            guard let size = try integer(from: input, at: &position) else {
//                throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//            }
//
//            // Negative bulk strings are `null`
//            if size < 0 {
//                return .parsed(.null)
//            }
//
//            // Parse the following length in data
//            guard
//                size > -1,
//                size < input.distance(from: position, to: input.endIndex)
//            else {
//                throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//            }
//
//            let endPosition = input.index(position, offsetBy: size)
//
//            defer {
//                position = input.index(position, offsetBy: size + 2)
//            }
//
//            return .parsed(.bulkString(Data(input[position..<endPosition])))
//        case .asterisk:
//            // Arrays start with their element count
//            guard let size = try integer(from: input, at: &position) else {
//                throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//            }
//
//            guard size >= 0 else {
//                throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//            }
//
//            var array = [PartialRedisData](repeating: .notYetParsed, count: size)
//
//            // Parse all elements
//            for index in 0..<size {
//                guard input.count - position >= 1 else {
//                    return .parsing(array)
//                }
//
//                let token = input[position]
//                position += 1
//
//                // Parse the individual nested element
//                let result = try parseToken(token, from: input, at: &position)
//
//                array[index] = result
//            }
//
//            let values = try array.map { value -> RedisData in
//                guard case .parsed(let value) = value else {
//                    throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//                }
//
//                return value
//            }
//
//            // All elements have been parsed, return the complete array
//            return .parsed(.array(values))
//        default:
//            throw RedisError(identifier: "invalidTypeToken", reason: "Unexpected error while parsing RedisData.")
//        }
//    }
//
//    fileprivate func continueParsing(partial value: inout PartialRedisData, from input: ByteBuffer, at offset: inout Int) throws -> Bool {
//        // Parses every `notyetParsed`
//        switch value {
//        case .parsed(_):
//            return true
//        case .notYetParsed:
//            // need 1 byte for the token
//            guard input.count - offset >= 1 else {
//                return false
//            }
//
//            let token = input[offset]
//            offset += 1
//
//            value = try parseToken(token, from: input, at: &offset)
//
//            if case .parsed(_) = value {
//                return true
//            }
//        case .parsing(var values):
//            for i in 0..<values.count {
//                guard try continueParsing(partial: &values[i], from: input, at: &offset) else {
//                    value = .parsing(values)
//                    return false
//                }
//            }
//
//            let values = try values.map { value -> RedisData in
//                guard case .parsed(let value) = value else {
//                    throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//                }
//
//                return value
//            }
//
//            value = .parsed(.array(values))
//            return true
//        }
//
//        return false
//    }
//
//    /// Continues parsing the `Data` buffer
//    func transform(_ parsing: ByteBuffer, _ ready: Promise<Void>) throws {
//        var value: PartialRedisData
//
//        // Continues parsing while there are still pending requests
//        repeat {
//            if let processing = self.processing {
//                value = processing
//            } else {
//                value = .notYetParsed
//            }
//
//            if try continueParsing(partial: &value, from: parsing, at: &parsedBytes) {
//                guard case .parsed(let value) = value else {
//                    throw RedisError(identifier: "parse", reason: "Unexpected error while parsing RedisData.")
//                }
//
//                self.processing = nil
//                flush(value, ready)
//            } else {
//                self.processing = value
//            }
//        } while parsedBytes < parsing.count
//    }
//
//    private func flush(_ data: RedisData, _ ready: Promise<Void>) {
//        self.downstream?.next(data, ready)
//    }
//}
//
///// A parsing-in-progress Redis value
//indirect enum PartialRedisData {
//    /// Placeholder for values in arrays
//    case notYetParsed
//
//    /// An array that's being parsed
//    case parsing([PartialRedisData])
//
//    /// A correctly parsed value
//    case parsed(RedisData)
//}

