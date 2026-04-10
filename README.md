# aria_experiment

Aria 系の各実装バリアントをビルドし、YCSB / TPCC ベンチマークを実行するためのリポジトリです。

## 前提環境

Ubuntu / Debian 系であれば、最低限次のパッケージがあればビルドできます。

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  cmake \
  pkg-config \
  libgoogle-glog-dev \
  libgflags-dev \
  libjemalloc-dev
```

補足:

- ベンチマーク実行スクリプトは `bash`, `grep`, `sed`, `awk`, `tee`, `readlink` を使います
- サブディレクトリ内の補助スクリプトを使う場合は `python3` が必要になることがあります

## ディレクトリ構成

主な手法ディレクトリ:

- `aria`
- `aria_abort_lock_fix`
- `ariaer`
- `ariaer_abort_lock_fix`
- `ariaer_cache_fix`
- `ariaer_cache_fix_abort_lock_fix`
- `ariaer_cache_fix_v2`
- `ariaer_cache_fix_v2_abort_lock_fix`

各ディレクトリには `compile.sh` があり、単体でクリーンビルドできます。

## セットアップ

リポジトリ直下で作業します。

```bash
cd /work/miyayu/aria_experiment
```

### 全手法をまとめてビルド

```bash
./scripts/compile_all.sh
```

### 個別にビルド

例: `ariaer` だけビルドする場合

```bash
cd ariaer
./compile.sh
```

`compile.sh` は毎回クリーンビルドを行い、`build/` 配下に生成物を作ります。
既存スクリプトとの互換のため、`bench_*` と `compile_commands.json` は各手法ディレクトリ直下にもシンボリックリンクが作られます。

## 実行例

### YCSB

```bash
./scripts/run_ycsb.sh run
```

abort lock fix 系を使う場合:

```bash
./scripts/run_ycsb_abort_lock_fix.sh run
```

### TPCC

```bash
./scripts/run_tpcc.sh run
```

abort lock fix 系を使う場合:

```bash
./scripts/run_tpcc_abort_lock_fix.sh run
```

## 結果の出力先

- YCSB の結果は主に `result/`
- TPCC の結果は主に `result_tpcc/`
- 論文用の結果は `result_for_journal/`
- 各実行の最新結果は `latest` シンボリックリンクから参照可能

実行スクリプトは `THREADS`, `PARTITIONS`, `RESULTS_ROOT`, `OUT_DIR` などの環境変数で上書きできます。

例:

```bash
THREADS=12 PARTITIONS=12 ./scripts/run_ycsb.sh run
```

---

## 論文用スクリプト・結果・図の対応関係

### ソースディレクトリ

| ディレクトリ | 説明 |
|---|---|
| `aria/` | ベースライン Aria |
| `ariaer_cache_fix_v2/` | 提案手法 AriaER |
| `aria_time_experiment/` | バッチ実行時間計測用 Aria |
| `ariaer_cache_fix_v2_time_experiment/` | バッチ実行時間計測用 AriaER |
| `aria_commit_rate/` | バッチ内commit率計測用 Aria |
| `ariaer_cache_fix_v2_commit_rate/` | バッチ内commit率計測用 AriaER |

### 実験スクリプト → 結果ディレクトリ → 図

以下はすべて `scripts_for_journal/` 配下のスクリプトと `result_for_journal/` 配下の結果の対応です。

| 実験スクリプト | 結果ディレクトリ | 後処理 | 生成図 (論文使用) |
|---|---|---|---|
| `ycsb_vary_zipf_op_100.sh` | `ycsb_vary_zipf_op_100/` | `ycsb_logs_to_csv.sh` | `medium_high.pdf` |
| `ycsb_vary_zipf.sh` | `ycsb_vary_zipf/` | `ycsb_logs_to_csv.sh` | `same_condition.pdf` |
| `ycsb_op_100_vary_zipf_vary_batch.sh` | `ycsb_op_100_vary_zipf_vary_batch/` | `ycsb_logs_to_csv_vary_batch.sh` | `vary_batch.pdf`, `vary_batch_ratio.pdf` |
| `ycsb_commit_rate.sh` | `ycsb_commit_rate/` | スクリプト内蔵 | `commit_rate.pdf` |
| `ycsb_vary_zipf_op_100.sh` (abort集計) | `ycsb_vary_zipf_op_100_abort_commit/` | `ycsb_logs_to_csv.sh` | `abort_commit_ratio.pdf` (参考) |
| `ycsb_vary_zipf_op_100_batch_time.sh` | `ycsb_vary_zipf_op_100_batch_time/` | `ycsb_logs_to_csv_batch_time.sh` | `batch_time.pdf`, `batch_time_diff.pdf` |
| `ycsb_sleep_experiment.sh` | `ycsb_sleep_experiment/` | スクリプト内蔵 | `sleep_throughput.pdf` |

### 図の生成

全図を一括生成:

```bash
python3 scripts_for_journal/generate_figures_matplotlib.py
```

このスクリプトは各CSVを読み込み、`aria_journal/figure_pdf_python/` に PDF を出力します。
論文 (`aria_journal/esample.tex`) は `aria_journal/figure_pdf/` を参照するため、使用する図はそちらにコピーしてください。

### 生成される図の一覧

| 出力ファイル | データソース (CSV) | 論文での用途 |
|---|---|---|
| `medium_high.pdf` | `aria_journal/figure/medium_to_high_contention/.../rw80_ops100_bs1000_t12_p12_k40000.csv` | Fig: 中〜高競合でのスループット比較 |
| `same_condition.pdf` | `aria_journal/figure/same_condition/.../rw80_ops10_bs1000_t12_p12_k40000.csv` | Fig: 原論文条件でのスループット比較 |
| `vary_batch.pdf` | `aria_journal/figure/vary_batch/.../rw95_ops100_zipf0.9_t12_p12_k40000.csv` | Fig: バッチサイズ変化時のスループット |
| `vary_batch_ratio.pdf` | `aria_journal/figure/vary_batch/.../ratio.csv` | Fig: AriaER/Ariaスループット比 |
| `commit_rate.pdf` | `result_for_journal/ycsb_commit_rate/*/commit_rate.csv` | Fig: バッチ内commit率 (スケジューリング空間) |
| `commit_rate_log.pdf` | 同上 | 参考 (対数スケール版) |
| `abort_commit_ratio.pdf` | `aria_journal/figure/abort_ratio/.../abort_commit_ratio.csv` | 参考 (旧指標) |
| `abort_commit_ratio_log.pdf` | 同上 | 参考 (対数スケール版) |
| `abort_commit_aria_over_ariaer.pdf` | `aria_journal/figure/abort_ratio/.../abort_commit_aria_over_ariaer.csv` | 参考 (旧指標) |
| `batch_time.pdf` | `aria_journal/figure/batch_execution_time/.../rw80_ops100_bs1000_t12_p12_k40000.csv` | Fig: 平均バッチ実行時間 |
| `batch_time_diff.pdf` | `aria_journal/figure/batch_execution_time/.../..._minus_....csv` | Fig: バッチ実行時間差分 |
| `batch_time_dual_axis.pdf` | 上記2つのCSV | 参考 (2軸版) |
| `sleep_throughput.pdf` | `result_for_journal/ycsb_sleep_experiment/*/condition_summaries/sleep_experiment.csv` | Fig: sleep実験スループット |

### SVG→PDF変換 (レガシー)

既存SVGのラベル修正・PDF変換:

```bash
python3 scripts_for_journal/fix_svg_and_convert.py
```

現在は `generate_figures_matplotlib.py` で直接PDF生成しているため、基本的に不要です。

---

## 困ったとき

- `glog`, `gflags`, `jemalloc` が見つからない場合は依存パッケージを再確認してください
- ビルドをやり直したい場合は各手法ディレクトリで `./compile.sh` を再実行してください
- すべての手法をまとめて作り直したい場合は `./scripts/compile_all.sh` を使ってください
