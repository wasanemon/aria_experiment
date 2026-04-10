# Vary Batch Size 実験

## 1 batch の定義と計測区間

Aria / AriaER はともに、固定数のトランザクションをまとめて処理する **batch 実行モデル** を採用している。
`AriaManager::coordinator_start()` の 1 ループが 1 batch に対応し、以下のフェーズを順に実行する。

```
batch_start = steady_clock::now()          ← 計測開始
─────────────────────────────────────────
(1) cleanup_batch()
      前回 batch で abort されたトランザクションを次の batch 先頭に移動し、
      残りのスロットを空にする。
(2) Aria_READ フェーズ
      全ワーカースレッドがトランザクションを実行し、
      read/write set の構築と write reservation を行う。
      → 全ワーカー完了後、全マシン間で同期 (wait4_ack)
(3) Aria_COMMIT フェーズ
      依存検査 (WAW / RAW / WAR) を行い、commit または abort を決定する。
      AriaER ではこのフェーズの前に WAW 早期検出結果を共有する
      (commit_shared_state.begin_commit_phase())。
      → 全ワーカー完了後、全マシン間で同期 (wait4_ack)
─────────────────────────────────────────
total_batch_duration += steady_clock::now() - batch_start  ← 計測終了
total_batches++
```

計測は `std::chrono::steady_clock` による壁時計時間で、`cleanup_batch()` の開始から `Aria_COMMIT` フェーズ後の最終同期 (`wait4_ack()`) 完了までの **end-to-end 時間** を 1 batch の所要時間とする。
全 batch の累積時間を batch 回数で割った値が `average batch time (ms)` としてログに出力される。

この定義は `aria_time_experiment/` と `ariaer_cache_fix_v2_time_experiment/` の両方の `AriaManager.h` で共通であり、計測対象となるフェーズの範囲は同一である。

## 目的

Aria と AriaER (ariaer\_cache\_fix\_v2) の throughput 差が batch size の増大に伴ってどのように変化するかを明らかにする。
Gria (Lu et al.) は「batch size は workload に応じて調整すべきであり、低競合ほど大きな batch size が適する」と指摘している。
本実験は、batch size を系統的に変化させることで AriaER の batch-level 処理省略効果が累積的に拡大するかを検証する。

## 実験条件

| パラメータ          | 値                                        |
|---------------------|-------------------------------------------|
| Workload            | YCSB                                      |
| read\_write\_ratio  | 95（read 95%, write 5%）                  |
| ops\_per\_txn       | 100                                       |
| batch\_size         | 1,000 / 2,000 / 3,000 / … / 10,000       |
| threads             | 12                                        |
| partitions          | 12                                        |
| keys (per partition)| 40,000                                    |
| cross\_ratio        | 100（全トランザクションがクロスパーティション）|
| global\_key\_space  | True（グローバルホットスポット）            |
| Zipf 係数           | 0.0, 0.1, 0.2, …, 0.9, 0.99              |
| 比較対象            | aria（オリジナル Aria）, ariaer\_cache\_fix\_v2（AriaER 提案手法）|

- 実行スクリプト: `scripts_for_journal/ycsb_op_100_vary_zipf_vary_batch.sh`
- 後処理スクリプト: `scripts_for_journal/ycsb_logs_to_csv_vary_batch.sh`

## ディレクトリ構成

```
vary_batch/
├── ycsb_op_100_vary_zipf_vary_batch/
│   └── 20260319_084212/          # 実行結果
│       ├── *.log                 # 各条件の生ログ（throughput, latency）
│       ├── condition_summaries/  # zipf ごとの CSV（batch_size × engine の throughput）
│       └── plots/                # x=batch_size, y=throughput の SVG グラフ（zipf ごと）
└── ycsb_op_100_vary_zipf_vary_batch_ratio/
    └── rw95_ops100_zipf0.9_t12_p12_k40000/
        ├── ratio.csv             # batch_size ごとの throughput 比（AriaER / Aria）
        └── ratio.svg             # 上記の折れ線グラフ
```

## 結果の概要

### 1. 低競合（Zipf = 0.0）: 両手法の差はほぼ無い

| batch\_size | Aria     | AriaER   | 比率 |
|-------------|----------|----------|------|
| 1,000       | 139,311  | 139,361  | 1.00 |
| 5,000       | 54,171   | 56,787   | 1.05 |
| 10,000      | 30,028   | 32,210   | 1.07 |

競合がほとんど発生しないため abort 自体が少なく、AriaER の早期依存解決が発揮される余地が小さい。
throughput 比はいずれの batch size でも 1.00–1.07 の範囲にとどまる。

### 2. 中程度の競合（Zipf = 0.5）: batch size の増大に応じて差が開き始める

| batch\_size | Aria    | AriaER  | 比率 |
|-------------|---------|---------|------|
| 1,000       | 89,003  | 91,109  | 1.02 |
| 5,000       | 29,147  | 32,307  | 1.11 |
| 10,000      | 16,519  | 19,425  | 1.18 |

### 3. 高競合（Zipf = 0.9）: AriaER の優位性が顕著に拡大

| batch\_size | Aria    | AriaER  | 比率 |
|-------------|---------|---------|------|
| 1,000       | 17,345  | 25,421  | 1.47 |
| 5,000       | 7,472   | 14,759  | 1.98 |
| 10,000      | 5,192   | 11,586  | 2.23 |

batch\_size = 1,000 では約 1.47 倍、10,000 では約 2.23 倍に達し、batch size の増大に対して throughput 比は単調増加する。

### 4. 極高競合（Zipf = 0.99）: 最大の性能差

| batch\_size | Aria    | AriaER  | 比率 |
|-------------|---------|---------|------|
| 1,000       | 11,178  | 18,110  | 1.62 |
| 5,000       | 5,283   | 11,141  | 2.11 |
| 10,000      | 3,970   | 9,084   | 2.29 |

## 考察

1. **batch size 増大による処理省略の累積効果**: Aria では abort されるトランザクションに対しても read reservation と依存解決を行うが、AriaER は WAW 依存の早期検出により、abort 確定トランザクションの後段処理を省略する。batch 内トランザクション数が増えるほど、不要な処理の累積コストが大きくなるため、AriaER の相対的な優位性が拡大する。

2. **競合率との相乗効果**: 高い Zipf 係数ほど abort 対象トランザクションの割合が増えるため、省略効果が大きくなる。batch size と競合率の二つの要因が相乗的に作用し、Zipf = 0.9, batch\_size = 10,000 で約 2.23 倍という最大の性能差が生じている。

3. **Gria の指摘との関連**: Gria は低競合ワークロードでは大きな batch size が適すると述べているが、本実験結果は高競合下でも AriaER が大きな batch size から恩恵を受けることを示しており、AriaER が Aria の batch size 選択に関する制約を緩和する可能性を示唆する。

## 対応する論文記述箇所

`esample.tex` の「batch sizeごとの実験結果」節（§4 付近）において、Zipf = 0.9 における throughput 比の単調増加（1.47 倍→2.23 倍）と、その原因分析（read reservation 省略・依存検査省略の累積効果）を記述している。
