// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

struct LeastRecentlyUsed<Key: Hashable, Value> {
  private struct Entry {
    let key: Key
    let value: Value
    let bytes: Int
    var older: Int?
    var newer: Int?
  }

  let capacity: Int
  private(set) var bytes = 0
  private var entries: [Entry?] = []
  private var vacant: [Int] = []
  private var slots: [Key: Int] = [:]
  private var newest: Int?
  private var oldest: Int?

  init(capacity: Int) { self.capacity = max(0, capacity) }

  mutating func value(for key: Key) -> Value? {
    guard let slot = slots[key] else { return nil }
    unlink(slot)
    link(slot)
    return entries[slot]!.value
  }

  /// Returns the values this displaces, so callers can release them elsewhere. Entries larger
  /// than the whole capacity are not stored, so they cannot empty the cache.
  @discardableResult
  mutating func insert(_ value: Value, bytes: Int, for key: Key) -> [Value] {
    var removed: [Value] = []
    if let slot = slots[key] { removed.append(remove(slot)) }
    guard bytes <= capacity else { return removed }
    let slot = vacant.popLast() ?? entries.count
    let entry = Entry(key: key, value: value, bytes: bytes)
    if slot == entries.count { entries.append(entry) } else { entries[slot] = entry }
    slots[key] = slot
    link(slot)
    self.bytes += bytes
    while self.bytes > capacity, let oldest { removed.append(remove(oldest)) }
    return removed
  }

  private mutating func remove(_ slot: Int) -> Value {
    unlink(slot)
    let entry = entries[slot]!
    bytes -= entry.bytes
    slots.removeValue(forKey: entry.key)
    entries[slot] = nil
    vacant.append(slot)
    return entry.value
  }

  private mutating func link(_ slot: Int) {
    entries[slot]!.older = newest
    entries[slot]!.newer = nil
    if let newest { entries[newest]!.newer = slot } else { oldest = slot }
    newest = slot
  }

  private mutating func unlink(_ slot: Int) {
    let older = entries[slot]!.older
    let newer = entries[slot]!.newer
    if let older { entries[older]!.newer = newer } else { oldest = newer }
    if let newer { entries[newer]!.older = older } else { newest = older }
  }
}
