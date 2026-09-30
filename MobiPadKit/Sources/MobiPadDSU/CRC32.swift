/// CRC-32 as used by zlib (and so by the DSU protocol): reflected polynomial 0xEDB88320.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in
            crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
    }

    static func checksum(_ bytes: some Sequence<UInt8>) -> UInt32 {
        ~bytes.reduce(~UInt32(0)) { crc, byte in
            table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
    }
}
