#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

#include "glog/logging.h"

namespace aria {

class AbortRegistry {
public:
  static constexpr std::size_t kCacheLineSize = 64;

  struct alignas(kCacheLineSize) AbortSlot {
    uint64_t generation;
    char padding[kCacheLineSize - sizeof(uint64_t)];

    AbortSlot() : generation(0), padding{} {}
  };

  static_assert(sizeof(AbortSlot) == kCacheLineSize,
                "AbortSlot must occupy exactly one cache line.");

  AbortRegistry() : generation_(1) {}

  explicit AbortRegistry(std::size_t batch_size) : generation_(1) {
    resize(batch_size);
  }

  void resize(std::size_t batch_size) { slots_.resize(batch_size); }

  void begin_commit_phase() { generation_++; }

  void mark_abort(std::size_t tid_offset) {
    DCHECK(tid_offset < slots_.size());
    slots_[tid_offset].generation = generation_;
  }

  bool is_aborted(std::size_t tid_offset) const {
    DCHECK(tid_offset < slots_.size());
    return slots_[tid_offset].generation == generation_;
  }

private:
  uint64_t generation_;
  std::vector<AbortSlot> slots_;
};

struct alignas(64) PaddedAtomicUInt32 {
  std::atomic<uint32_t> value;
  char padding[64 - sizeof(std::atomic<uint32_t>)];

  explicit PaddedAtomicUInt32(uint32_t initial = 0) : value(initial), padding{} {}
};

static_assert(sizeof(PaddedAtomicUInt32) == 64,
              "PaddedAtomicUInt32 must occupy exactly one cache line.");

struct AriaCommitSharedState {
  AriaCommitSharedState() = default;

  explicit AriaCommitSharedState(std::size_t batch_size) : aborts(batch_size) {}

  void resize(std::size_t batch_size) { aborts.resize(batch_size); }

  void begin_commit_phase() { aborts.begin_commit_phase(); }

  AbortRegistry aborts;
  PaddedAtomicUInt32 barrier_count;
  PaddedAtomicUInt32 barrier_gen;
};

} // namespace aria
