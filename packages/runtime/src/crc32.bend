import Base

# CRC-32 (ISO-HDLC: the reflected polynomial 0xEDB88320, initial and final
# value 0xFFFFFFFF) over bytes, as used by the AWS event-stream framing.

def bit(count: Nat, +crc: U32) -> U32:
  match count:
    case 0n: crc
    case 1n+rest: bit(rest, Bool.pick(U32, U32.is_eq(U32.and(crc, 1), 1), U32.xor(U32.shrn(crc, 1n), 3988292384), U32.shrn(crc, 1n)))

def step(crc: U32, byte: U32) -> U32: bit(8n, U32.xor(crc, byte))

def fold(bytes: List<&2, U32>, crc: U32) -> U32:
  match bytes:
    case Nil{}: crc
    case byte <> rest: fold(rest, step(crc, byte))

# Continue a checksum over more bytes.
def update(crc: U32, bytes: List<&2, U32>) -> U32: U32.xor(fold(bytes, U32.xor(crc, 4294967295)), 4294967295)

def checksum(bytes: List<&2, U32>) -> U32: update(0, bytes)
