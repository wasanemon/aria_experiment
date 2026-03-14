#include "glog/logging.h"

#include "benchmark/ycsb/Context.h"
#include "benchmark/ycsb/Query.h"
#include "benchmark/ycsb/Random.h"
#include "common/Zipf.h"
#include "core/Table.h"
#include "protocol/Aria/AriaHelper.h"
#if defined(ARIAER_ABORT_SHARED_STATE_V1) || defined(ARIAER_ABORT_SHARED_STATE_V2)
#include "protocol/Aria/CommitSharedState.h"
#endif

#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

using namespace aria;

namespace {

constexpr std::size_t kWorkerNum = 4;
constexpr uint32_t kEpoch = 1;
constexpr std::size_t kMaxKeys = 100;
using TestTable = Table<256, uint64_t, uint64_t>;

struct TxnSpec {
  uint32_t tid;
  std::size_t tid_offset;
  std::size_t partition_id;
  std::vector<uint64_t> writes;
  std::vector<uint64_t> reads;
  bool waw = false;
  bool war = false;
  bool raw = false;
};

struct Scenario {
  std::string name;
  uint64_t seed;
  std::size_t batch_size;
  ycsb::Context context;
  double zipf = 0.0;
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

uint64_t fnv1a(const std::string &s) {
  uint64_t h = 1469598103934665603ull;
  for (unsigned char c : s) {
    h ^= static_cast<uint64_t>(c);
    h *= 1099511628211ull;
  }
  return h;
}

std::string hex64(uint64_t value) {
  std::ostringstream out;
  out << std::hex << std::setw(16) << std::setfill('0') << value;
  return out.str();
}

ycsb::Context make_context() {
  ycsb::Context context;
  context.coordinator_id = 0;
  context.coordinator_num = 1;
  context.partition_num = 4;
  context.worker_num = kWorkerNum;
  context.keysPerPartition = 64;
  context.keysPerTransaction = 10;
  context.readWriteRatio = 80;
  context.readOnlyTransaction = 0;
  context.crossPartitionProbability = 100;
  context.skewPattern = ycsb::YCSBSkewPattern::BOTH;
  context.strategy = ycsb::PartitionStrategy::ROUND_ROBIN;
  context.two_partitions = false;
  context.global_key_space = false;
  context.isUniform = true;
  return context;
}

std::vector<TxnSpec> generate_batch(const Scenario &scenario) {
  ycsb::Context context = scenario.context;
  if (scenario.zipf > 0) {
    context.isUniform = false;
    if (context.global_key_space) {
      Zipf::globalZipf().init(context.keysPerPartition * context.partition_num,
                              scenario.zipf);
    } else {
      Zipf::globalZipf().init(context.keysPerPartition, scenario.zipf);
    }
  }

  ycsb::Random random(scenario.seed);
  std::vector<TxnSpec> batch;
  batch.reserve(scenario.batch_size);
  auto partition_num_per_node = context.partition_num / context.coordinator_num;
  for (std::size_t i = 0; i < scenario.batch_size; i++) {
    auto partition_id =
        random.uniform_dist(0, partition_num_per_node - 1) * context.coordinator_num +
        context.coordinator_id;
    auto query = ycsb::makeYCSBQuery<kMaxKeys>()(context, partition_id, random);

    TxnSpec txn;
    txn.tid = static_cast<uint32_t>(i + 1);
    txn.tid_offset = i;
    txn.partition_id = partition_id;
    for (std::size_t op = 0; op < context.keysPerTransaction; op++) {
      if (query.UPDATE[op]) {
        txn.writes.push_back(static_cast<uint64_t>(query.Y_KEY[op]));
      } else {
        txn.reads.push_back(static_cast<uint64_t>(query.Y_KEY[op]));
      }
    }
    batch.push_back(txn);
  }
  return batch;
}

std::string batch_query_signature(const std::vector<TxnSpec> &batch) {
  std::ostringstream out;
  for (const auto &txn : batch) {
    out << "T" << txn.tid << "@p" << txn.partition_id << ":";
    for (auto key : txn.reads) {
      out << "r" << key << ",";
    }
    out << "/";
    for (auto key : txn.writes) {
      out << "w" << key << ",";
    }
    out << "|";
  }
  return out.str();
}

void populate_table_for_batch(TestTable &table, const std::vector<TxnSpec> &batch) {
  std::vector<uint64_t> inserted;
  for (const auto &txn : batch) {
    for (auto key : txn.reads) {
      if (std::find(inserted.begin(), inserted.end(), key) == inserted.end()) {
        uint64_t value = key + 1;
        table.insert(&key, &value);
        inserted.push_back(key);
      }
    }
    for (auto key : txn.writes) {
      if (std::find(inserted.begin(), inserted.end(), key) == inserted.end()) {
        uint64_t value = key + 1;
        table.insert(&key, &value);
        inserted.push_back(key);
      }
    }
  }
}

std::string evaluate_batch(const std::vector<TxnSpec> &input_batch) {
  auto batch = input_batch;
  TestTable table(0, 0);
  populate_table_for_batch(table, batch);
  AbortStateAdapter aborts(batch.size());
  aborts.begin_batch(batch.size());

  for (const auto &txn : batch) {
    for (auto key : txn.writes) {
      AriaHelper::reserve_write(table.search_metadata(&key), kEpoch, txn.tid);
    }
  }

  for (auto &txn : batch) {
    for (auto key : txn.writes) {
      auto meta = table.search_metadata(&key).load();
      auto wts = AriaHelper::get_wts(meta);
      if (AriaHelper::get_epoch(meta) == kEpoch && wts < txn.tid && wts != 0) {
        txn.waw = true;
        break;
      }
    }
    if (txn.waw) {
      aborts.mark_abort(txn.tid_offset);
    }
  }

  for (const auto &txn : batch) {
    if (txn.waw) {
      continue;
    }
    for (auto key : txn.reads) {
      AriaHelper::reserve_read(table.search_metadata(&key), kEpoch, txn.tid);
    }
  }

  std::ostringstream out;
  for (auto &txn : batch) {
    if (!txn.waw) {
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
    out << "T" << txn.tid << "[" << txn.waw << txn.war << txn.raw << "]|";
  }
  return out.str();
}

std::string run_scenario(const Scenario &scenario) {
  auto batch1 = generate_batch(scenario);
  auto batch2 = generate_batch(scenario);

  const auto query_sig1 = batch_query_signature(batch1);
  const auto query_sig2 = batch_query_signature(batch2);
  CHECK_EQ(query_sig1, query_sig2) << "Query generation must be deterministic.";

  const auto result_sig1 = evaluate_batch(batch1);
  const auto result_sig2 = evaluate_batch(batch2);
  CHECK_EQ(result_sig1, result_sig2) << "Conflict outcome must be deterministic.";

  std::ostringstream out;
  out << scenario.name << ":q=" << hex64(fnv1a(query_sig1))
      << ",r=" << hex64(fnv1a(result_sig1));
  return out.str();
}

} // namespace

int main(int argc, char *argv[]) {
  google::InitGoogleLogging(argv[0]);
  google::InstallFailureSignalHandler();

  auto uniform = make_context();

  auto global_zipf = make_context();
  global_zipf.global_key_space = true;
  global_zipf.isUniform = false;

  auto two_part = make_context();
  two_part.two_partitions = true;
  two_part.crossPartitionProbability = 100;

  std::vector<Scenario> scenarios = {
      {"uniform_multi", 0x1234, 12, uniform, 0.0},
      {"global_zipf", 0x5678, 12, global_zipf, 0.8},
      {"two_partition", 0x9abc, 12, two_part, 0.0},
  };

  std::ostringstream signature;
  for (std::size_t i = 0; i < scenarios.size(); i++) {
    if (i > 0) {
      signature << "|";
    }
    signature << run_scenario(scenarios[i]);
  }

  std::cout << "YCSB_EQUIVALENCE_SIGNATURE=" << signature.str() << std::endl;
  return 0;
}
