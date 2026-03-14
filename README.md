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
- 各実行の最新結果は `latest` シンボリックリンクから参照可能

実行スクリプトは `THREADS`, `PARTITIONS`, `RESULTS_ROOT`, `OUT_DIR` などの環境変数で上書きできます。

例:

```bash
THREADS=12 PARTITIONS=12 ./scripts/run_ycsb.sh run
```

## 困ったとき

- `glog`, `gflags`, `jemalloc` が見つからない場合は依存パッケージを再確認してください
- ビルドをやり直したい場合は各手法ディレクトリで `./compile.sh` を再実行してください
- すべての手法をまとめて作り直したい場合は `./scripts/compile_all.sh` を使ってください
