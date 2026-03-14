#include "glog/logging.h"

#include "core/Table.h"
#include "protocol/Aria/AriaHelper.h"

// 簡易テスト: TableメタデータとAriaHelperを直接用いて、
// WAW/WAR/RAW の条件が論文アルゴリズム通りになるか確認する。

using namespace aria;

struct TestKey
{
    uint64_t id;
    bool operator==(const TestKey &o) const { return id == o.id; }
};

// HashMap のキーとして標準のhashが不要な実装になっているが、
// core/Table.h の HashMap は独自実装なのでこのままで動作する。

int main(int argc, char *argv[])
{
    google::InitGoogleLogging(argv[0]);
    google::InstallFailureSignalHandler();

    // 小さなテーブルを作る: key=uint64_t, value=uint64_t
    Table<16, uint64_t, uint64_t> table(0, 0);

    auto insert_row = [&](uint64_t k, uint64_t v)
    {
        table.insert(&k, &v);
        // メタデータ初期値は0（epoch/rts/wts=0）
    };

    // 予備データ
    insert_row(1, 111);
    insert_row(2, 222);
    insert_row(3, 333);

    const uint32_t epoch = 1;

    // シナリオA: WAW 検出と WAW-abort のread予約スキップ相当を確認
    // T1(id=1) が key1, key2 を write 予約 → T2(id=2) も key1 を write 予約
    // → WAW(T2) が成立 (key1 で wts=1 < 2)

    // 初期化: メタデータを0に戻す
    {
        uint64_t k1 = 1, k2 = 2, k3 = 3;
        table.search_metadata(&k1).store(0);
        table.search_metadata(&k2).store(0);
        table.search_metadata(&k3).store(0);
    }

    // T1 reserve write: keys {1,2}
    {
        uint64_t k1 = 1, k2 = 2;
        auto &m1 = table.search_metadata(&k1);
        auto &m2 = table.search_metadata(&k2);
        CHECK(AriaHelper::reserve_write(m1, epoch, 1));
        CHECK(AriaHelper::reserve_write(m2, epoch, 1));
    }
    // T2 reserve write: keys {1,3}
    {
        uint64_t k1 = 1, k3 = 3;
        auto &m1 = table.search_metadata(&k1);
        auto &m3 = table.search_metadata(&k3);
        // reserve_writeはfalse返る可能性があるが、Aria実装は戻り値を使用しない
        AriaHelper::reserve_write(m1, epoch, 2);
        AriaHelper::reserve_write(m3, epoch, 2);
    }

    // WAW判定 for T2
    {
        uint64_t k1 = 1;
        uint64_t meta_k1 = table.search_metadata(&k1).load();
        uint64_t ep = AriaHelper::get_epoch(meta_k1);
        uint64_t wts = AriaHelper::get_wts(meta_k1);
        CHECK_EQ(ep, epoch);
        CHECK_EQ(wts, 1u);
        bool waw_T2 = (ep == epoch && wts < 2 && wts != 0);
        CHECK(waw_T2) << "T2 should detect WAW on key1 (wts=1 < tid=2).";
    }

    // シナリオB: RAW 検出 (writer未中止)
    // T1(id=1) が key2 を write、T2(id=2) が key2 を read → RAW(T2)=true
    // (AbortList[writer]==0 を想定)

    // 初期化
    {
        uint64_t k1 = 1, k2 = 2, k3 = 3;
        table.search_metadata(&k1).store(0);
        table.search_metadata(&k2).store(0);
        table.search_metadata(&k3).store(0);
    }

    // T1 reserve write: key2
    {
        uint64_t k2 = 2;
        auto &m2 = table.search_metadata(&k2);
        CHECK(AriaHelper::reserve_write(m2, epoch, 1));
    }
    // T2 reserve read: key2
    {
        uint64_t k2 = 2;
        auto &m2 = table.search_metadata(&k2);
        CHECK(AriaHelper::reserve_read(m2, epoch, 2));
    }
    // RAW判定 for T2 on key2
    {
        uint64_t k2 = 2;
        uint64_t meta_k2 = table.search_metadata(&k2).load();
        uint64_t ep = AriaHelper::get_epoch(meta_k2);
        uint64_t wts = AriaHelper::get_wts(meta_k2);
        CHECK_EQ(ep, epoch);
        CHECK_EQ(wts, 1u);
        // writer未中止を想定 (AbortList[1-1]==0)
        bool raw_T2 = (ep == epoch && wts < 2 && wts != 0);
        CHECK(raw_T2) << "T2 should detect RAW on key2 (wts=1 < tid=2).";
    }

    // シナリオC: WAR 検出
    // T1(id=1) が key3 を read、T2(id=2) が key3 を write → WAR(T2)=true

    // 初期化
    {
        uint64_t k1 = 1, k2 = 2, k3 = 3;
        table.search_metadata(&k1).store(0);
        table.search_metadata(&k2).store(0);
        table.search_metadata(&k3).store(0);
    }

    // T1 reserve read: key3
    {
        uint64_t k3 = 3;
        auto &m3 = table.search_metadata(&k3);
        CHECK(AriaHelper::reserve_read(m3, epoch, 1));
    }
    // T2 reserve write: key3
    {
        uint64_t k3 = 3;
        auto &m3 = table.search_metadata(&k3);
        AriaHelper::reserve_write(m3, epoch, 2);
    }
    // WAR判定 for T2 on key3
    {
        uint64_t k3 = 3;
        uint64_t meta_k3 = table.search_metadata(&k3).load();
        uint64_t ep = AriaHelper::get_epoch(meta_k3);
        uint64_t rts = AriaHelper::get_rts(meta_k3);
        CHECK_EQ(ep, epoch);
        CHECK_EQ(rts, 1u);
        bool war_T2 = (ep == epoch && rts < 2 && rts != 0);
        CHECK(war_T2) << "T2 should detect WAR on key3 (rts=1 < tid=2).";
    }

    LOG(INFO) << "AriaER simple tests passed.";
    return 0;
}
