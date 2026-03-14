#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <thread>
#include <vector>

#include "glog/logging.h"

namespace aria {

class AbortRegistry {
public:
  AbortRegistry() : worker_num_(0), batch_size_(0) {}

  AbortRegistry(std::size_t worker_num, std::size_t batch_size) {
    resize(worker_num, batch_size);
  }

  void resize(std::size_t worker_num, std::size_t batch_size) {
    worker_num_ = worker_num;
    batch_size_ = batch_size;
    shards_.clear();
    shards_.resize(worker_num_);
    for (std::size_t worker = 0; worker < worker_num_; worker++) {
      shards_[worker].assign(shard_size(worker), 0);
    }
  }

  void clear() {
    for (auto &shard : shards_) {
      std::fill(shard.begin(), shard.end(), 0);
    }
  }

  void mark_abort(std::size_t tid_offset) {
    DCHECK(tid_offset < batch_size_);
    auto worker = owner_worker(tid_offset);
    auto index = local_index(tid_offset);
    DCHECK(worker < shards_.size());
    DCHECK(index < shards_[worker].size());
    shards_[worker][index] = 1;
  }

  bool is_aborted(std::size_t tid_offset) const {
    DCHECK(tid_offset < batch_size_);
    auto worker = owner_worker(tid_offset);
    auto index = local_index(tid_offset);
    DCHECK(worker < shards_.size());
    DCHECK(index < shards_[worker].size());
    return shards_[worker][index] != 0;
  }

private:
  std::size_t owner_worker(std::size_t tid_offset) const {
    DCHECK(worker_num_ > 0);
    return tid_offset % worker_num_;
  }

  std::size_t local_index(std::size_t tid_offset) const {
    DCHECK(worker_num_ > 0);
    return tid_offset / worker_num_;
  }

  std::size_t shard_size(std::size_t worker) const {
    if (worker_num_ == 0 || worker >= batch_size_) {
      return 0;
    }
    return ((batch_size_ - 1 - worker) / worker_num_) + 1;
  }

private:
  std::size_t worker_num_;
  std::size_t batch_size_;
  std::vector<std::vector<uint8_t>> shards_;
};

class DisseminationBarrier {
public:
  static constexpr std::size_t kCacheLineSize = 64;

  struct alignas(kCacheLineSize) BarrierCell {
    std::atomic<uint64_t> generation;
    char padding[kCacheLineSize - sizeof(std::atomic<uint64_t>)];

    BarrierCell() : generation(0), padding{} {}
  };

  static_assert(sizeof(BarrierCell) == kCacheLineSize,
                "BarrierCell must occupy exactly one cache line.");

  DisseminationBarrier() : worker_num_(0), rounds_(0) {}

  explicit DisseminationBarrier(std::size_t worker_num) { resize(worker_num); }

  void resize(std::size_t worker_num) {
    worker_num_ = worker_num;
    rounds_ = 0;
    while ((1ull << rounds_) < worker_num_) {
      rounds_++;
    }

    if (worker_num_ == 0 || rounds_ == 0) {
      cells_.reset();
      return;
    }

    cells_ = std::make_unique<BarrierCell[]>(worker_num_ * rounds_);
  }

  void wait(std::size_t worker_id, uint64_t &local_generation) {
    DCHECK(worker_id < worker_num_);

    local_generation++;
    if (worker_num_ <= 1 || rounds_ == 0) {
      return;
    }

    for (std::size_t round = 0; round < rounds_; round++) {
      auto partner = (worker_id + (std::size_t{1} << round)) % worker_num_;
      cell(partner, round).generation.store(local_generation,
                                            std::memory_order_release);
      while (cell(worker_id, round).generation.load(std::memory_order_acquire) !=
             local_generation) {
        std::this_thread::yield();
      }
    }
  }

private:
  BarrierCell &cell(std::size_t worker_id, std::size_t round) {
    return cells_[worker_id * rounds_ + round];
  }

private:
  std::size_t worker_num_;
  std::size_t rounds_;
  std::unique_ptr<BarrierCell[]> cells_;
};

struct AriaCommitSharedState {
  AriaCommitSharedState() = default;

  AriaCommitSharedState(std::size_t worker_num, std::size_t batch_size)
      : aborts(worker_num, batch_size), barrier(worker_num) {}

  void resize(std::size_t worker_num, std::size_t batch_size) {
    aborts.resize(worker_num, batch_size);
    barrier.resize(worker_num);
  }

  void begin_commit_phase() { aborts.clear(); }

  AbortRegistry aborts;
  DisseminationBarrier barrier;
};

} // namespace aria
