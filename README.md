# Aria and AriaER Variants Implementation

This repository contains implementations of the deterministic concurrency control protocol **Aria** and its extended version **AriaER**, along with several intermediate variants for ablation studies.

## Overview of Contributions

AriaER introduces three main optimizations (contributions) over the original Aria protocol:

*   **(a) Separated Dependency Check**: Reduces unnecessary aborts caused by WAR/RAW dependencies by separating the validation phase into WAW checks and WAR/RAW checks. Transactions aborted by WAW are excluded from WAR/RAW checks.
*   **(b) Abort List**: Reduces the number of global barriers required during the commit phase by using a shared `abort_list` to notify workers of aborted transactions immediately.
*   **(c) Split Reservation**: Reduces unnecessary read reservations by splitting the reservation phase. Read reservations are performed only by transactions that have survived the WAW check (Write-Reservation -> Barrier -> WAW Check -> Read-Reservation).

## Implemented Protocols

The repository includes the following 5 implementations:

### 1. Aria (Original)
*   **Path:** `aria/`
*   **Features:** None (Baseline)
*   **Description:** The existing deterministic concurrency control protocol. It performs Read and Write reservations together in the `read_snapshot` phase, followed by a single validation phase for WAW, WAR, and RAW dependencies.

### 2. AriaER (Extended)
*   **Path:** `ariaer/`
*   **Features:** **a + b + c**
*   **Description:** The fully optimized version of Aria.
    *   **Split Reservation (c):** Only writes are reserved first. Reads are reserved later in the commit phase.
    *   **Separated Check (a):** WAW dependencies are checked first.
    *   **Abort List (b):** Transactions aborted by WAW mark themselves in a shared `abort_list`, allowing surviving transactions to ignore them during RAW/WAR checks without needing extra barriers or reservation modifications.

### 3. AriaER (Split Reservation w/o Abort List)
*   **Path:** `ariaer_split_reservation_without_abort_list/`
*   **Features:** **a + c**
*   **Description:** AriaER without the shared `abort_list` component.
    *   **Mechanism:** Instead of using an `abort_list`, transactions that abort due to WAW explicitly **modify their reservations** (setting WTS to 0) to signal their abortion to other workers.
    *   **Trade-off:** This removes the need for a shared bitset but requires an additional barrier synchronization after the reservation modification step.

### 4. AriaER (No Split Reservation w/o Abort List)
*   **Path:** `ariaer_without_split_reservation_without_abort_list/`
*   **Features:** **a**
*   **Description:** The minimal extension to Aria, introducing only the separated dependency check.
    *   **Mechanism:** Reservations (Read/Write) are done together as in Aria. The validation logic is separated into WAW and WAR/RAW phases. Like implementation #3, it uses **reservation modification** instead of an `abort_list` to handle WAW aborts.

### 5. AriaER (No Split Reservation w/ Abort List)
*   **Path:** `ariaer_without_split_reservation_with_abort_list/`
*   **Features:** **a + b**
*   **Description:** AriaER without Split Reservation.
    *   **Mechanism:** Reservations (Read/Write) are done together in the `read_snapshot` phase (like Aria). However, it uses the **Separated Check (a)** and **Abort List (b)** during the commit phase to efficiently handle dependencies.

## Comparison Table

| # | Protocol Name | Dependency Check (a) | Abort List (b) | Split Reservation (c) | Base Code |
|---|---|:---:|:---:|:---:|---|
| 1 | **Aria** | No | No | No | Aria |
| 2 | **AriaER** | **Yes** | **Yes** | **Yes** | AriaER |
| 3 | **Split w/o AbortList** | **Yes** | No | **Yes** | Aria (Modified) |
| 4 | **No Split w/o AbortList** | **Yes** | No | No | Aria (Modified) |
| 5 | **No Split w/ AbortList** | **Yes** | **Yes** | No | AriaER (Modified) |

## Implementation Details

*   **Abort List:** A shared bit-vector used to broadcast the abort status of transactions.
*   **Modify Reservation:** In protocols without an Abort List (#3, #4), a transaction that detects a WAW conflict executes `modify_reservation_on_waw()` to clear its Write Timestamp (WTS) from the metadata, effectively removing itself from the dependency graph of subsequent transactions.

