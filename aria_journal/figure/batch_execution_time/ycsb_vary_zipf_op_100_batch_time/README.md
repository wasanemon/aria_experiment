# `ycsb_vary_zipf_op_100_batch_time`

このディレクトリは、YCSB の `vary_zipf_op_100` 条件で `1 batch あたりの平均実行時間` を比較するための実験結果を保存します。

## 実験の目的

- `aria_time_experiment`
- `ariaer_cache_fix_v2_time_experiment`

の 2 系列について、`zipf` を変化させたときの batch 実行時間の違いを見るための実験です。

ここでの batch time は、`AriaManager` の 1 ループ全体を 1 batch とみなし、

- `cleanup_batch()`
- `Aria_READ`
- `Aria_COMMIT`
- 同期完了 (`wait4_ack()`)

までを含む end-to-end の壁時計時間です。

## 実験条件

- workload: YCSB
- read_write_ratio: `80`
- ops_per_txn: `100`
- batch_size: `1000`
- threads: `12`
- partitions: `12`
- keys: `40000`
- cross_ratio: `100`
- global_key_space: `True`
- vary 対象: `zipf`

実行スクリプトは `scripts_for_journal/ycsb_vary_zipf_op_100_batch_time.sh` です。  
後処理は `scripts_for_journal/ycsb_logs_to_csv_batch_time.sh` が行います。

## ディレクトリ構成

各タイムスタンプ付きディレクトリは 1 回の実行結果です。中には主に次のものがあります。

- `*.log`
  - 各条件・各エンジンの生ログ
  - ログ末尾に `average batch time: <ms>` を出力
- `summary.tsv`, `summary.csv`
  - 生ログから抽出した要約
- `condition_summaries/`
  - 条件ごとの整形 CSV
- `plots/`
  - `x軸=zipf`, `y軸=average batch time (ms)` のグラフ
- `ratio_summaries/`, `ratio_plots/`
  - `aria_time_experiment / ariaer_cache_fix_v2_time_experiment`
- `diff_summaries/`, `diff_plots/`
  - `aria_time_experiment - ariaer_cache_fix_v2_time_experiment`
- `plots/*_with_diff_dual_axis.svg`
  - 左軸に両系列の batch time、右軸に差分を重ねた複合グラフ

## グラフの見方

- `plots/*.svg`
  - 2 系列の batch time を直接比較する基本グラフ
- `ratio_plots/*.svg`
  - 相対比を見るグラフ
  - `1` より大きければ `aria_time_experiment` の方が遅い
- `diff_plots/*.svg`
  - 絶対差を見るグラフ
  - 正なら `aria_time_experiment` の方が遅い
- `plots/*_with_diff_dual_axis.svg`
  - 左軸で batch time、右軸で差分を同時に確認するためのグラフ

## 補足

このディレクトリは throughput 実験とは別で、時間計測専用の実装を使っています。

- `aria_time_experiment/`
- `ariaer_cache_fix_v2_time_experiment/`

既存の `aria/` や `ariaer_cache_fix_v2/` を直接上書きせず、専用ディレクトリで計測ロジックを持たせています。
