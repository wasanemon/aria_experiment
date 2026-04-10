#include "glog/logging.h"
#include "core/Table.h"
#include "protocol/Aria/AriaHelper.h"
#if defined(ARIAER_ABORT_SHARED_STATE_V1) || defined(ARIAER_ABORT_SHARED_STATE_V2)
#include "protocol/Aria/CommitSharedState.h"
#endif
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

using namespace aria;

namespace {
constexpr std::size_t kWorkerNum = 4;
constexpr uint32_t kEpoch = 1;
using TestTable = Table<16, uint64_t, uint64_t>;

struct TxnSpec {
  uint32_t tid;
  std::size_t tid_offset;
  std::vector<uint64_t> writes;
  std::vector<uint64_t> reads;
  bool waw = false;
  bool war = false;
  bool raw = false;
};

class AbortStateAdapter {
public:
  explicit AbortStateAdapter(std::size_t batch_size)
#if defined(ARIAER_ABORT_SHARED_STATE_V1)
      : shared_state_(kWorkerNum, batch_size), batch_size_(batch_size) {}
#elif defined(ARIAER_ABORT_SHARED_STATE_V2)
      : shared_state_(batch_size), batch_size_(batch_size) {}
#else
      : abort_list_(batch_size, 0), batch_size_(batch_size) {}
#endif

  void begin_batch(std::size_t batch_size) {
    batch_size_ = batch_size;
#if defined(ARIAER_ABORT_SHARED_STATE_V1)
    shared_state_.resize(kWorkerNum, batch_size);
    shared_state_.begin_commit_phase();
#elif defined(ARIAER_ABORT_SHARED_STATE_V2)
    shared_state_.resize(batch_size);
    shared_state_.begin_commit_phase();
#else
    abort_list_.assign(batch_size, 0);
#endif
  }

  void mark_abort(std::size_t tid_offset) {
    DCHECK(tid_offset < batch_size_);
#if defined(ARIAER_ABORT_SHARED_STATE_V1) || defined(ARIAER_ABORT_SHARED_STATE_V2)
    shared_state_.aborts.mark_abort(tid_offset);
#else
    abort_list_[tid_offset] = 1;
#endif
  }

  bool is_aborted(std::size_t tid_offset) const {
    DCHECK(tid_offset < batch_size_);
#if defined(ARIAER_ABORT_SHARED_STATE_V1) || defined(ARIAER_ABORT_SHARED_STATE_V2)
    return shared_state_.aborts.is_aborted(tid_offset);
#else
    return abort_list_[tid_offset] != 0;
#endif
  }

private:
#if defined(ARIAER_ABORT_SHARED_STATE_V1) || defined(ARIAER_ABORT_SHARED_STATE_V2)
  AriaCommitSharedState shared_state_;
#else
  std::vector<uint8_t> abort_list_;
#endif
  std::size_t batch_size_;
};

void reset_keys(TestTable &table, std::initializer_list<uint64_t> keys) {
  for (auto key : keys) {
    table.search_metadata(&key).store(0);
  }
}

std::string summarize(const std::vector<TxnSpec> &txns) {
  std::ostringstream out;
  for (std::size_t i = 0; i < txns.size(); i++) {
    if (i) out << ";";
    out << "T" << txns[i].tid << "[" << txns[i].waw << txns[i].war << txns[i].raw << "]";
  }
  return out.str();
}

std::string run_batch(TestTable &table, AbortStateAdapter &aborts, std::vector<TxnSpec> txns) {
  aborts.begin_batch(txns.size());
  for (const auto &txn : txns) {
    for (auto key : txn.writes) {
      AriaHelper::reserve_write(table.search_metadata(&key), kEpoch, txn.tid);
    }
  }
  for (auto &txn : txns) {
    for (auto key : txn.writes) {
      auto meta = table.search_metadata(&key).load();
      auto wts = AriaHelper::get_wts(meta);
      if (AriaHelper::get_epoch(meta) == kEpoch && wts < txn.tid && wts != 0) {
        txn.waw = true;
        break;
      }
    }
    if (txn.waw) aborts.mark_abort(txn.tid_offset);
  }
  for (const auto &txn : txns) {
    if (txn.waw) continue;
    for (auto key : txn.reads) {
      AriaHelper::reserve_read(table.search_metadata(&key), kEpoch, txn.tid);
    }
  }
  for (auto &txn : txns) {
    if (txn.waw) continue;
    for (auto key : txn.writes) {
      auto meta = table.search_metadata(&key).load();
      auto rts = AriaHelper::get_rts(meta);
      if (AriaHelper::get_epoch(meta) == kEpoch && rts < txn.tid && rts != 0) {
        txn.war = true;
        break;
      }
    }
    for (auto key : txn.reads) {
      auto meta = table.search_metadata(&key).load();
      auto wts = AriaHelper::get_wts(meta);
      if (AriaHelper::get_epoch(meta) == kEpoch && wts < txn.tid && wts != 0) {
        auto writer_offset = static_cast<std::size_t>(wts - 1);
        if (!aborts.is_aborted(writer_offset)) {
          txn.raw = true;
          break;
        }
      }
    }
  }
  return summarize(txns);
}

std::string run_reset(AbortStateAdapter &aborts) {
  aborts.begin_batch(3);
  aborts.mark_abort(1);
  bool seen = aborts.is_aborted(1);
  aborts.begin_batch(3);
  bool cleared = !aborts.is_aborted(1);
  std::ostringstream out;
  out << "reset[" << seen << cleared << "]";
  return out.str();
}
} // namespace

int main(int argc, char *argv[]) {
  google::InitGoogleLogging(argv[0]);
  google::InstallFailureSignalHandler();
  TestTable table(0, 0);
  for (uint64_t key = 1; key <= 8; key++) {
    uint64_t value = key * 10;
    table.insert(&key, &value);
  }
  AbortStateAdapter aborts(8);
  std::ostringstream sig;
  reset_keys(table, {1, 2});
  sig << run_batch(table, aborts, {{1, 0, {1}, {}}, {2, 1, {1, 2}, {}}, {3, 2, {}, {2}}});
  reset_keys(table, {4});
  sig << "|" << run_batch(table, aborts, {{1, 0, {4}, {}}, {2, 1, {}, {4}}});
  reset_keys(table, {5});
  sig << "|" << run_batch(table, aborts, {{1, 0, {}, {5}}, {2, 1, {5}, {}}});
  sig << "|" << run_reset(aborts);
  const std::string actual = sig.str();
  const std::string expected =
      "T1[000];T2[100];T3[000]|T1[000];T2[001]|T1[000];T2[010]|reset[11]";
  CHECK_EQ(actual, expected);
  std::cout << "EQUIVALENCE_SIGNATURE=" << actual << std::endl;
  return 0;
}
