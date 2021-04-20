import Foundation

extension NetSocket {
    struct CycleBuffer: CustomDebugStringConvertible {
        var bytes: UnsafePointer<UInt8>? {
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> UnsafePointer<UInt8>? in
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self).advanced(by: head)
            }
        }
        var maxLength: Int {
            min(count, capacity - head)
        }
        var debugDescription: String {
            Mirror(reflecting: self).debugDescription
        }
        private var count: Int {
            let value = tail - head
            return value < 0 ? value + capacity : value
        }
        private var data: Data
        private var capacity: Int = 0 {
            didSet {
                logger.info("extends a buffer size from ", oldValue, " to ", capacity)
            }
        }
        private var head: Int = 0
        private var tail: Int = 0
        private var locked: UnsafeMutablePointer<UInt32>?
        private var lockedTail: Int = -1

        init(capacity: Int) {
            self.capacity = capacity
            data = .init(repeating: 0, count: capacity)
        }

        mutating func append(_ data: Data, locked: UnsafeMutablePointer<UInt32>? = nil) {
            guard data.count + count < capacity else {
                extend(data)
                return
            }
            let count = data.count
            if self.locked == nil {
                self.locked = locked
            }
            let length = min(count, capacity - tail)
            self.data.replaceSubrange(tail..<tail + length, with: data)
            if length < count {
                tail = count - length
                self.data.replaceSubrange(0..<tail, with: data.advanced(by: length))
            } else {
                tail += count
            }
            if capacity == tail {
                tail = 0
            }
            if locked != nil {
                lockedTail = tail
            }
        }

        mutating func markAsRead(_ count: Int) {
            let length = min(count, capacity - head)
            if length < count {
                head = count - length
            } else {
                head += count
            }
            if capacity == head {
                head = 0
            }
            if let locked = locked, -1 < lockedTail && lockedTail <= head {
                OSAtomicAnd32Barrier(0, locked)
                lockedTail = -1
            }
        }

        mutating func clear() {
            head = 0
            tail = 0
            locked = nil
            lockedTail = 0
        }

        private mutating func extend(_ data: Data) {
            if 0 < head {
                let subdata = self.data.subdata(in: 0..<tail)
                self.data.replaceSubrange(0..<capacity - head, with: self.data.advanced(by: head))
                self.data.replaceSubrange(capacity - head..<capacity - head + subdata.count, with: subdata)
                tail = capacity - head + subdata.count
            }
            self.data.append(.init(count: capacity))
            head = 0
            capacity = self.data.count
            append(data)
        }
    }
}
