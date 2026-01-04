// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Hyperpolymath

@@ocaml.doc("
Zero-copy shared memory for JS-to-WASM data transfer.
Uses SharedArrayBuffer for high-performance data passing without serialization overhead.
Ideal for large repo metadata objects and commit histories.
")

// ============================================================================
// SharedArrayBuffer Bindings
// ============================================================================

module SharedArrayBuffer = {
  type t

  @new external create: int => t = "SharedArrayBuffer"
  @get external byteLength: t => int = "byteLength"
  @send external slice: (t, int, int) => t = "slice"

  @ocaml.doc("Check if SharedArrayBuffer is available (requires cross-origin isolation)")
  let isAvailable = (): bool => {
    %raw(`typeof SharedArrayBuffer !== 'undefined'`)
  }

  @ocaml.doc("Check if cross-origin isolation is enabled")
  let isCrossOriginIsolated = (): bool => {
    %raw(`typeof crossOriginIsolated !== 'undefined' && crossOriginIsolated`)
  }
}

// ============================================================================
// Typed Array Views
// ============================================================================

module Uint8View = {
  type t

  @new external fromBuffer: SharedArrayBuffer.t => t = "Uint8Array"
  @new external fromBufferWithOffset: (SharedArrayBuffer.t, int) => t = "Uint8Array"
  @new external fromBufferWithOffsetAndLength: (SharedArrayBuffer.t, int, int) => t = "Uint8Array"
  @get external length: t => int = "length"
  @get external buffer: t => SharedArrayBuffer.t = "buffer"
  @get_index external get: (t, int) => int = ""
  @set_index external set: (t, int, int) => unit = ""
  @send external subarray: (t, int, int) => t = "subarray"
}

module Uint32View = {
  type t

  @new external fromBuffer: SharedArrayBuffer.t => t = "Uint32Array"
  @new external fromBufferWithOffset: (SharedArrayBuffer.t, int) => t = "Uint32Array"
  @new external fromBufferWithOffsetAndLength: (SharedArrayBuffer.t, int, int) => t = "Uint32Array"
  @get external length: t => int = "length"
  @get external buffer: t => SharedArrayBuffer.t = "buffer"
  @get_index external get: (t, int) => int = ""
  @set_index external set: (t, int, int) => unit = ""
}

module BigUint64View = {
  type t

  @new external fromBuffer: SharedArrayBuffer.t => t = "BigUint64Array"
  @new external fromBufferWithOffset: (SharedArrayBuffer.t, int) => t = "BigUint64Array"
  @get external length: t => int = "length"
  @get external buffer: t => SharedArrayBuffer.t = "buffer"
  @get_index external get: (t, int) => Js.BigInt.t = ""
  @set_index external set: (t, int, Js.BigInt.t) => unit = ""
}

module Float64View = {
  type t

  @new external fromBuffer: SharedArrayBuffer.t => t = "Float64Array"
  @new external fromBufferWithOffset: (SharedArrayBuffer.t, int) => t = "Float64Array"
  @get external length: t => int = "length"
  @get external buffer: t => SharedArrayBuffer.t = "buffer"
  @get_index external get: (t, int) => float = ""
  @set_index external set: (t, int, float) => unit = ""
}

// ============================================================================
// Atomics for Thread-Safe Access
// ============================================================================

module Atomics = {
  @scope("Atomics") @val external load: (Uint32View.t, int) => int = "load"
  @scope("Atomics") @val external store: (Uint32View.t, int, int) => int = "store"
  @scope("Atomics") @val external add: (Uint32View.t, int, int) => int = "add"
  @scope("Atomics") @val external sub: (Uint32View.t, int, int) => int = "sub"
  @scope("Atomics") @val external and_: (Uint32View.t, int, int) => int = "and"
  @scope("Atomics") @val external or_: (Uint32View.t, int, int) => int = "or"
  @scope("Atomics") @val external xor: (Uint32View.t, int, int) => int = "xor"
  @scope("Atomics") @val external exchange: (Uint32View.t, int, int) => int = "exchange"
  @scope("Atomics") @val external compareExchange: (Uint32View.t, int, int, int) => int = "compareExchange"
  @scope("Atomics") @val external wait: (Uint32View.t, int, int) => string = "wait"
  @scope("Atomics") @val external waitWithTimeout: (Uint32View.t, int, int, int) => string = "wait"
  @scope("Atomics") @val external notify: (Uint32View.t, int) => int = "notify"
  @scope("Atomics") @val external notifyCount: (Uint32View.t, int, int) => int = "notify"
}

// ============================================================================
// Shared Memory Pool
// ============================================================================

@ocaml.doc("Memory pool configuration")
type poolConfig = {
  initialSize: int,     // Initial buffer size in bytes
  maxSize: int,         // Maximum buffer size
  growthFactor: float,  // How much to grow when expanding (e.g., 1.5)
}

let defaultPoolConfig: poolConfig = {
  initialSize: 1024 * 1024,      // 1MB initial
  maxSize: 256 * 1024 * 1024,    // 256MB max
  growthFactor: 1.5,
}

@ocaml.doc("Shared memory pool for zero-copy transfers")
type memoryPool = {
  mutable buffer: SharedArrayBuffer.t,
  mutable writeOffset: int,
  config: poolConfig,
}

@ocaml.doc("Create a new memory pool")
let createPool = (~config=defaultPoolConfig, ()): result<memoryPool, string> => {
  if !SharedArrayBuffer.isAvailable() {
    Error("SharedArrayBuffer not available. Enable cross-origin isolation.")
  } else {
    Ok({
      buffer: SharedArrayBuffer.create(config.initialSize),
      writeOffset: 0,
      config,
    })
  }
}

@ocaml.doc("Reset pool for reuse (doesn't reallocate)")
let resetPool = (pool: memoryPool): unit => {
  pool.writeOffset = 0
}

@ocaml.doc("Ensure pool has enough space, grow if needed")
let ensureCapacity = (pool: memoryPool, needed: int): result<unit, string> => {
  let currentSize = SharedArrayBuffer.byteLength(pool.buffer)
  let requiredSize = pool.writeOffset + needed

  if requiredSize <= currentSize {
    Ok()
  } else {
    // Calculate new size
    let newSize = ref(currentSize)
    while newSize.contents < requiredSize {
      newSize := Int.fromFloat(Float.fromInt(newSize.contents) *. pool.config.growthFactor)
    }

    if newSize.contents > pool.config.maxSize {
      Error("Pool would exceed maximum size")
    } else {
      // Create new buffer and copy data
      let newBuffer = SharedArrayBuffer.create(newSize.contents)
      let oldView = Uint8View.fromBuffer(pool.buffer)
      let newView = Uint8View.fromBuffer(newBuffer)

      for i in 0 to pool.writeOffset - 1 {
        Uint8View.set(newView, i, Uint8View.get(oldView, i))
      }

      pool.buffer = newBuffer
      Ok()
    }
  }
}

// ============================================================================
// Data Serialization to Shared Memory
// ============================================================================

@ocaml.doc("Header structure for data blocks in shared memory")
type blockHeader = {
  blockType: int,   // Type discriminator
  length: int,      // Data length in bytes
  checksum: int,    // Simple checksum for integrity
}

let headerSize = 12  // 3 x 4 bytes

@ocaml.doc("Block types for serialized data")
module BlockType = {
  let string = 1
  let intArray = 2
  let floatArray = 3
  let commitHistory = 4
  let repoMetadata = 5
  let dependencyGraph = 6
}

@ocaml.doc("Write a header to the pool")
let writeHeader = (pool: memoryPool, header: blockHeader): unit => {
  let view = Uint32View.fromBufferWithOffset(pool.buffer, pool.writeOffset)
  Uint32View.set(view, 0, header.blockType)
  Uint32View.set(view, 1, header.length)
  Uint32View.set(view, 2, header.checksum)
  pool.writeOffset = pool.writeOffset + headerSize
}

@ocaml.doc("Read a header from an offset")
let readHeader = (buffer: SharedArrayBuffer.t, offset: int): blockHeader => {
  let view = Uint32View.fromBufferWithOffset(buffer, offset)
  {
    blockType: Uint32View.get(view, 0),
    length: Uint32View.get(view, 1),
    checksum: Uint32View.get(view, 2),
  }
}

@ocaml.doc("Calculate simple checksum for data integrity")
let calculateChecksum = (data: Uint8View.t): int => {
  let sum = ref(0)
  for i in 0 to Uint8View.length(data) - 1 {
    sum := sum.contents + Uint8View.get(data, i)
  }
  land(sum.contents, 0xFFFFFFFF)
}

// ============================================================================
// High-Level Data Transfer
// ============================================================================

@ocaml.doc("Write a string to shared memory (zero-copy ready)")
let writeString = (pool: memoryPool, str: string): result<int, string> => {
  let encoder = %raw(`new TextEncoder()`)
  let encoded: Uint8View.t = %raw(`encoder.encode(str)`)
  let len = Uint8View.length(encoded)

  switch ensureCapacity(pool, headerSize + len) {
  | Error(e) => Error(e)
  | Ok() => {
      let startOffset = pool.writeOffset

      writeHeader(pool, {
        blockType: BlockType.string,
        length: len,
        checksum: calculateChecksum(encoded),
      })

      // Copy string data
      let destView = Uint8View.fromBufferWithOffsetAndLength(pool.buffer, pool.writeOffset, len)
      for i in 0 to len - 1 {
        Uint8View.set(destView, i, Uint8View.get(encoded, i))
      }
      pool.writeOffset = pool.writeOffset + len

      Ok(startOffset)
    }
  }
}

@ocaml.doc("Read a string from shared memory")
let readString = (buffer: SharedArrayBuffer.t, offset: int): result<string, string> => {
  let header = readHeader(buffer, offset)
  if header.blockType != BlockType.string {
    Error("Expected string block")
  } else {
    let dataView = Uint8View.fromBufferWithOffsetAndLength(buffer, offset + headerSize, header.length)

    // Verify checksum
    if calculateChecksum(dataView) != header.checksum {
      Error("Checksum mismatch")
    } else {
      let decoder = %raw(`new TextDecoder()`)
      Ok(%raw(`decoder.decode(dataView)`))
    }
  }
}

@ocaml.doc("Write an int array to shared memory")
let writeIntArray = (pool: memoryPool, arr: array<int>): result<int, string> => {
  let len = Array.length(arr) * 4  // 4 bytes per int

  switch ensureCapacity(pool, headerSize + len) {
  | Error(e) => Error(e)
  | Ok() => {
      let startOffset = pool.writeOffset

      // Write header
      writeHeader(pool, {
        blockType: BlockType.intArray,
        length: len,
        checksum: 0,  // Skip checksum for performance
      })

      // Write data
      let view = Uint32View.fromBufferWithOffset(pool.buffer, pool.writeOffset)
      arr->Array.forEachWithIndex((value, i) => {
        Uint32View.set(view, i, value)
      })
      pool.writeOffset = pool.writeOffset + len

      Ok(startOffset)
    }
  }
}

@ocaml.doc("Read an int array from shared memory")
let readIntArray = (buffer: SharedArrayBuffer.t, offset: int): result<array<int>, string> => {
  let header = readHeader(buffer, offset)
  if header.blockType != BlockType.intArray {
    Error("Expected int array block")
  } else {
    let count = header.length / 4
    let view = Uint32View.fromBufferWithOffset(buffer, offset + headerSize)
    let arr = Array.make(~length=count, 0)
    for i in 0 to count - 1 {
      arr->Array.setUnsafe(i, Uint32View.get(view, i))
    }
    Ok(arr)
  }
}

// ============================================================================
// Commit History Optimized Format
// ============================================================================

@ocaml.doc("Compact commit record for shared memory")
type compactCommit = {
  timestamp: float,
  authorHash: int,    // Hash of author string
  messageHash: int,   // Hash of message (first 100 chars)
  additions: int,
  deletions: int,
}

@ocaml.doc("Write commit history to shared memory")
let writeCommitHistory = (pool: memoryPool, commits: array<compactCommit>): result<int, string> => {
  let recordSize = 24  // 8 (float) + 4*4 (ints) = 24 bytes per commit
  let len = Array.length(commits) * recordSize

  switch ensureCapacity(pool, headerSize + 4 + len) {
  | Error(e) => Error(e)
  | Ok() => {
      let startOffset = pool.writeOffset

      writeHeader(pool, {
        blockType: BlockType.commitHistory,
        length: 4 + len,  // count + data
        checksum: 0,
      })

      // Write count
      let countView = Uint32View.fromBufferWithOffset(pool.buffer, pool.writeOffset)
      Uint32View.set(countView, 0, Array.length(commits))
      pool.writeOffset = pool.writeOffset + 4

      // Write commits
      commits->Array.forEach(commit => {
        let floatView = Float64View.fromBufferWithOffset(pool.buffer, pool.writeOffset)
        Float64View.set(floatView, 0, commit.timestamp)
        pool.writeOffset = pool.writeOffset + 8

        let intView = Uint32View.fromBufferWithOffset(pool.buffer, pool.writeOffset)
        Uint32View.set(intView, 0, commit.authorHash)
        Uint32View.set(intView, 1, commit.messageHash)
        Uint32View.set(intView, 2, commit.additions)
        Uint32View.set(intView, 3, commit.deletions)
        pool.writeOffset = pool.writeOffset + 16
      })

      Ok(startOffset)
    }
  }
}

// ============================================================================
// WASM Integration Helpers
// ============================================================================

@ocaml.doc("Get the underlying buffer for passing to WASM")
let getBuffer = (pool: memoryPool): SharedArrayBuffer.t => {
  pool.buffer
}

@ocaml.doc("Get current write offset")
let getWriteOffset = (pool: memoryPool): int => {
  pool.writeOffset
}

@ocaml.doc("Create a view into the pool's buffer for WASM")
let createWasmView = (pool: memoryPool): Uint8View.t => {
  Uint8View.fromBuffer(pool.buffer)
}

@ocaml.doc("Import object for WASM that includes shared memory")
let createWasmImports = (pool: memoryPool): Js.Dict.t<'a> => {
  let imports = Js.Dict.empty()
  Js.Dict.set(imports, "memory", pool.buffer)
  Js.Dict.set(imports, "readOffset", () => pool.writeOffset)
  imports
}
