# Abort/Commit 比の Zipf 依存性実験

## 目的

Aria と AriaER (ariaer\_cache\_fix\_v2) において、Zipf 係数（データアクセスの偏り）を変化させたときの **abort/commit 比** を比較し、AriaER の早期依存解決が abort 抑制にどの程度寄与しているかを定量的に示す。

throughput の差だけでは「commit が増えた」という結果は見えるが、その原因が abort 削減にあることを裏付けるためにこの指標を用いる。

## abort/commit 比の定義と計測方法

### ログ出力

`Coordinator.h` の計測ループが 1 秒ごとに全ワーカーの `n_commit`、`n_abort_no_retry`、`n_abort_lock`、`n_abort_read_validation` を集計し、warmup / cooldown 区間を除いた実測区間について以下の最終サマリ行を出力する。

```
average commit: <C>  abort: <A> (<n_abort_no_retry>/<n_abort_lock>/<n_abort_read_validation>)
```

- **commit (C)**: 1 秒あたりの平均 commit 数（= throughput）
- **abort (A)**: 1 秒あたりの平均 abort 数（3 種類の合計）
  - `n_abort_no_retry`: トランザクション生成段階での abort
  - `n_abort_lock`: 依存検査（WAW/RAW/WAR）による abort
  - `n_abort_read_validation`: read validation による abort

### abort/commit 比の算出

各ログの最終サマリ行から `average_abort / average_commit` を計算している。

例: Aria, Zipf = 0.9 のログ → `commit: 287.6, abort: 132012` → abort/commit = **459.0**

この値は「1 件のトランザクションが commit されるまでに、平均何件の abort が発生しているか」を意味する。

## 実験条件

| パラメータ          | 値                        |
|---------------------|---------------------------|
| Workload            | YCSB                      |
| read\_write\_ratio  | 80（read 80%, write 20%） |
| ops\_per\_txn       | 100                       |
| batch\_size         | 1,000                     |
| threads             | 12                        |
| partitions          | 12                        |
| keys (per partition)| 40,000                    |
| cross\_ratio        | 100                       |
| global\_key\_space  | True                      |
| Zipf 係数           | 0.0, 0.1, …, 0.9, 0.99   |

- ソースログ: `result_for_journal/ycsb_vary_zipf_op_100/20260319_081820/`
- 実行スクリプト: `scripts_for_journal/ycsb_vary_zipf_op_100.sh`

## ディレクトリ構成

```
20260319_081820/
├── README.md                          # 本ファイル
├── abort_commit_ratio.csv             # zipf × engine の abort/commit 比
├── abort_commit_ratio.svg             # 上記の 2 系列折れ線グラフ（x=zipf, y=abort/commit）
├── abort_commit_aria_over_ariaer.csv  # Aria の abort/commit を AriaER の abort/commit で割った比
└── abort_commit_aria_over_ariaer.svg  # 上記の折れ線グラフ（x=zipf, y=Aria/AriaER）
```

## 結果の概要

### abort/commit 比（各エンジン）

| Zipf  | Aria     | AriaER   |
|-------|----------|----------|
| 0.0   | 1.88     | 1.52     |
| 0.1   | 1.91     | 1.55     |
| 0.2   | 2.05     | 1.64     |
| 0.3   | 2.40     | 1.91     |
| 0.4   | 3.34     | 2.57     |
| 0.5   | 5.87     | 4.23     |
| 0.6   | 13.60    | 8.48     |
| 0.7   | 42.00    | 20.95    |
| 0.8   | 154.33   | 69.48    |
| 0.9   | 459.01   | 260.39   |
| 0.99  | 772.62   | 611.99   |

- 全ての Zipf 係数で AriaER の abort/commit が Aria より小さい。
- 低競合 (Zipf ≤ 0.3) では両者とも 2 前後で差は小さい。
- Zipf = 0.8 で Aria は 154、AriaER は 69 と約 2.2 倍の差が開く。
- Zipf = 0.9 で Aria は 459、AriaER は 260 となり、Aria は 1 commit あたり約 459 回の abort が発生。

### Aria/AriaER の abort/commit 比率

| Zipf  | Aria / AriaER |
|-------|---------------|
| 0.0   | 1.24          |
| 0.3   | 1.26          |
| 0.5   | 1.39          |
| 0.6   | 1.60          |
| 0.7   | 2.00          |
| 0.8   | **2.22**      |
| 0.9   | 1.76          |
| 0.99  | 1.26          |

- Zipf = 0.8 で最大の 2.22 倍に達する（Aria は AriaER の 2.22 倍 abort が多い）。
- Zipf = 0.9 以降は比率が減少する。これは競合が極めて高い領域では、WAW 以外の依存（RAW/WAR）による abort が支配的になり、AriaER の早期 WAW 検出による削減余地が相対的に小さくなるためと考えられる。

## 考察

1. **AriaER による abort 抑制の機構**: Aria では WAW 依存で本来 abort されるべきトランザクションが依然として read reservation を保持し、後段の RAW/WAR 検査で他のトランザクションを巻き込んで false positive な abort を誘発する。AriaER は WAW 依存を早期に検出し、abort 確定トランザクションの影響を後段から除外することで、この連鎖的 abort を抑制する。

2. **ピークが Zipf = 0.8 付近にある理由**: 低競合では abort 自体が少なく差が出にくい。一方、極高競合 (Zipf ≥ 0.9) では WAW 以外の依存 (RAW/WAR) による abort が支配的となり、早期 WAW 検出だけでは吸収しきれない。中高競合（Zipf = 0.7–0.8）が AriaER の早期依存解決が最も効率的に作用する領域である。

3. **throughput との対応**: `esample.tex` に記載の通り、throughput 比（AriaER/Aria）は Zipf = 0.8 で約 2.36 倍であり、abort/commit 比の改善（2.22 倍）と強い相関がある。abort の削減が直接的に throughput の向上に繋がっていることを示す。

## 対応する論文記述箇所

`esample.tex`「早期依存解決・無駄な操作の省略の効果の分析」節において、本実験の abort/commit 比較結果を引用し、Aria の abort/commit が全 Zipf 係数で AriaER より大きいこと、Zipf = 0.8 で約 2.22 倍に達することを述べている。
