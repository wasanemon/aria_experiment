# Handoff: `ariaer_retry` vs `ariaer_retry_patch`

## 目的

この作業の主目的は、`ariaer` 系で観測された `retry-fixed ariaer` の性能低下、とくに `skew=0` 付近の挙動を調べ、`abort_list` と barrier の実装改善が有効かを検証できる状態を正確に整理すること。

このドキュメントは、次の担当者がこれだけ読めば状況を正しく把握し、比較実験をそのまま再開できるように作成している。

## 現在のブランチ

- 現在の作業ブランチ: `ariaer-local-abort-barrier`

## 重要な注意

途中で exploratory な変更を root の `ariaer` に入れてしまったため、一時的に比較軸が混乱した。
その後、**比較用ディレクトリを作り直して整理し直した**。

今後、性能比較で使うべき基準は **root の `ariaer` ではなく** `ariaer_retry`。

## 現在のディレクトリの意味

### baseline / main 相当

- `aria`
  - main 相当の `aria`
- `ariaer`
  - `main` ブランチ上の `ariaer` に同期済み
  - `abort()` は no-op

### retry 版

- `aria_retry`
  - `aria` に retry 処理を加えた版
- `ariaer_retry`
  - `ariaer` に retry 処理を加えた版
  - 今後の **baseline**

### retry + patch 版

- `ariaer_retry_patch`
  - `ariaer_retry` に今回の patch を追加した版
  - 今後の **patched 対象**

## retry の意味

retry は `protocol/Aria/Aria.h` の `abort()` において

```cpp
txn.abort_lock = true;
```

を設定すること。

この差により、`cleanup_batch()` が abort transaction を次 batch に持ち越す。

### 現在の `abort()` の状態

- `ariaer/protocol/Aria/Aria.h`
  - `// nothing needs to be done`
- `ariaer_retry/protocol/Aria/Aria.h`
  - `txn.abort_lock = true;`
- `ariaer_retry_patch/protocol/Aria/Aria.h`
  - `txn.abort_lock = true;`

## patch の内容

`ariaer_retry_patch` にだけ入っている差分は、基本的に以下の 2 つ。

1. `abort_list` を 1 本の共有配列から per-worker 風の配列構造へ変更
2. barrier の待ち方を軽量化

### 差分が入っているファイル

- `ariaer_retry_patch/protocol/Aria/AriaExecutor.h`
- `ariaer_retry_patch/protocol/Aria/AriaManager.h`

### 差分が入っていないことを期待するファイル

- `ariaer_retry_patch/protocol/Aria/Aria.h`
  - `ariaer_retry` と同じ retry 実装

## patch の要点

### 1. WAW abort 記録先の変更

旧:

- `abort_list[tid_offset] = 1`

新:

- `owner = tid_offset % worker_num`
- `abort_flags_by_worker[owner][tid_offset] = 1`

RAW 判定時も、

- 旧: `abort_list[writer_offset]`
- 新: `abort_flags_by_worker[owner_worker_for_offset(writer_offset)][writer_offset]`

を見る。

意味は変えず、共有配列アクセスを分散させるのが狙い。

### 2. barrier の変更

旧:

- `yield()` を回し続ける barrier

新:

- 短い spin をしつつ、ときどき `yield()` する barrier

これも意味は変えず、待機コストを下げるのが狙い。

## 決定論性・整合性に関する考え方

今回の patch は、

- commit / abort の判定規則そのもの
- WAW / WAR / RAW の意味

は変えていない。

変えているのは、

- WAW abort の記録場所
- barrier の待ち方

だけ。

単一ノード前提では、

- `tid_offset`
- `worker id`
- `owner = tid_offset % worker_num`

の対応は固定なので、設計意図としては決定論性・整合性を壊さない想定。

ただし、最終的には性能実験とは別に、必要なら commit / abort 総数の比較で実証すること。

## ビルド確認済み

以下は `bench_ycsb` のビルド成功を確認済み。

- `aria_retry/build/bench_ycsb`
- `ariaer_retry/build/bench_ycsb`
- `ariaer_retry_patch/build/bench_ycsb`

### ビルド時の注意

`ariaer_retry` は C++11 設定下で以下の警告が出る。

- `inline static std::vector<uint8_t> abort_list;`
- `inline static std::atomic<uint32_t> barrier_count{0};`
- `inline static std::atomic<uint32_t> barrier_gen{0};`

これは retry baseline 側の既存実装に由来する警告で、現状ビルドは通る。

`ariaer_retry_patch` はこの警告は出ていない。

## これまでの性能結果について

### 無効 / 比較軸が混ざっている結果

以下の quick result は、**正しい baseline (`ariaer_retry`) ではなく別の `ariaer` を使って比較してしまった時期のものを含むため、そのまま結論に使わないこと**。

- `results/quick_perf_checks/repeated_compare_t12_rw50_ops100_bs1024.txt`
- `results/quick_perf_checks/repeated_compare_t12_rw50_ops100_bs1024.png`
- `results/quick_perf_checks/allskew_compare_t12_rw50_ops100_bs1024.txt`
- `results/quick_perf_checks/allskew_compare_t12_rw50_ops100_bs1024.png`

これらは参考にはできるが、**最終結論には使わないこと**。

### 有効な今後の比較軸

今後の正しい比較は必ずこれに固定すること。

- baseline: `ariaer_retry`
- patched: `ariaer_retry_patch`

## 推奨する最小比較条件

まずは次の条件で 1 条件だけ比較するのがよい。

- workload: YCSB A
- threads: `12`
- partitions: `12`
- keys per partition: `40000`
- `rw=50`
- `ops_per_txn=100`
- `batch_size=1024`
- `global_key_space=True`
- `cross_ratio=100`
- `skew_pattern=both`

まずは

- `zipf=0.0`
- `zipf=0.2`

から始める。

その後必要なら

- `0.4`
- `0.6`
- `0.8`
- `0.9`

へ広げる。

## 実行コマンド例

### baseline

```bash
./build/bench_ycsb \
  --logtostderr=1 \
  --protocol=Aria \
  --id=0 \
  --servers=127.0.0.1:10010 \
  --partition_num=12 \
  --threads=12 \
  --io=1 \
  --cpu_affinity=true \
  --batch_size=1024 \
  --read_write_ratio=50 \
  --read_only_ratio=0 \
  --skew_pattern=both \
  --zipf=0.0 \
  --ops_per_txn=100 \
  --keys=40000 \
  --global_key_space=True \
  --cross_ratio=100
```

`ariaer_retry` でこのコマンドを実行。

### patched

同じコマンドを `ariaer_retry_patch` で実行。

## 次にやるべきこと

優先順位順に書く。

1. `ariaer_retry` vs `ariaer_retry_patch` のみで、`zipf=0.0` と `0.2` を再計測
2. 差が確認できたら、`0.4, 0.6, 0.8, 0.9` へ拡張
3. 新しい quick result は、必ず `results/quick_perf_checks/` の中でも別ファイル名で保存
4. 必要なら `Step1(WAW)`, `Step2(read reserve)`, `Step3(WAR/RAW)`, barrier 待ち時間を計測

## 現在の作業ツリーの状態

関連する未コミット状態は概ね以下。

- `ariaer/protocol/Aria/AriaExecutor.h`
- `ariaer/protocol/Aria/AriaManager.h`
  - root `ariaer` の exploratory patch 履歴として変更扱い
- `aria_retry/`
- `ariaer_retry/`
- `ariaer_retry_patch/`
  - 新規ディレクトリ

重要なのは、**今後の評価は root `ariaer` ではなく `ariaer_retry` / `ariaer_retry_patch` で行うこと**。

## 一言まとめ

今の正しい比較対象はこれだけ。

- `ariaer_retry`: retry あり、patch なし
- `ariaer_retry_patch`: retry あり、patch あり

root `ariaer` を baseline に使ってはいけない。
