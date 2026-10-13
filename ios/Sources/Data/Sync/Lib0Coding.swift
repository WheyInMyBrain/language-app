import Foundation

public enum Lib0Encoder {
    public static func writeVarUInt(_ num: UInt64, into buf: inout Data) {
        var n = num
        while n >= 0x80 {
            buf.append(UInt8((n & 0x7F) | 0x80))
            n >>= 7
        }
        buf.append(UInt8(n & 0x7F))
    }

    public static func writeVarUInt8Array(_ bytes: Data, into buf: inout Data) {
        writeVarUInt(UInt64(bytes.count), into: &buf)
        buf.append(bytes)
    }
}

public enum Lib0Decoder {
    public static func readVarUInt(from data: Data, offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt32 = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    public static func readVarUInt8Array(from data: Data, offset: inout Int) -> Data? {
        guard let len = readVarUInt(from: data, offset: &offset) else { return nil }
        let length = Int(len)
        guard offset + length <= data.count else { return nil }
        let sub = data.subdata(in: offset..<(offset + length))
        offset += length
        return sub
    }
}