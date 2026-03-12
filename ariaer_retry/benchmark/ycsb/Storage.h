//
// Created by Yi Lu on 9/12/18.
//

#pragma once

#include "benchmark/ycsb/Schema.h"

namespace aria {

namespace ycsb {
struct Storage {
  ycsb::key ycsb_keys[100];
  ycsb::value ycsb_values[100];
};

} // namespace ycsb
} // namespace aria