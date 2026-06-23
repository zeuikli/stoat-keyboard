// rime_selftest.mm — 在 iOS simulator 跑 librime + 預編譯 RimeData，驗證真注音查詢。
// 用法（simctl spawn）：rime_selftest <shared> <user> <prebuilt> [keys]
#import <Foundation/Foundation.h>
#import "rime_api.h"
#include <cstdio>

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 4) { printf("usage: shared user prebuilt [keys]\n"); return 2; }
    RimeApi *api = rime_get_api();
    RIME_STRUCT(RimeTraits, t);
    t.shared_data_dir = argv[1];
    t.user_data_dir = argv[2];
    t.prebuilt_data_dir = argv[3];
    t.distribution_name = "selftest";
    t.distribution_code_name = "selftest";
    t.distribution_version = "1";
    t.app_name = "rime.selftest";
    t.min_log_level = 2;
    api->setup(&t);
    const char *keys0 = (argc > 4) ? argv[4] : "cl3";
    if (strcmp(keys0, "DEPLOY") == 0) {        // 部署模式：編譯自訂詞庫
      api->deployer_initialize(&t);
      bool ok = api->deploy();
      api->finalize();
      printf("deploy=%d\n", ok ? 1 : 0);
      return ok ? 0 : 1;
    }
    api->initialize(&t);
    if (api->start_maintenance(False)) api->join_maintenance_thread();
    RimeSessionId s = api->create_session();
    printf("session=%llu\n", (unsigned long long)s);
    if (!s) { printf("NO SESSION\n"); return 1; }

    if (argc > 5) { api->set_option(s, argv[5], True); printf("set_option %s=1\n", argv[5]); }
    const char *keys = (argc > 4) ? argv[4] : "cl3";  // ㄏㄠˇ  // PAGE_DOWN_TEST
    int pages = (argc > 6) ? atoi(argv[6]) : 0;
    for (const char *p = keys; *p; ++p) api->process_key(s, (int)*p, 0);
    for (int pg = 0; pg < pages; pg++) api->process_key(s, 0xff56, 0);  // Page_Down
    if (argc > 7 && strcmp(argv[7],"commit")==0) {  // COMMIT_PREDICT：選首選上字、看預測
      api->select_candidate_on_current_page(s, 0);
    }

    RIME_STRUCT(RimeContext, ctx);
    api->get_context(s, &ctx);
    printf("input=%s\n", keys);
    printf("preedit=%s\n", ctx.composition.preedit ? ctx.composition.preedit : "(nil)");
    const char* gi = api->get_input(s); printf("get_input=%s\n", gi?gi:"(nil)");
    printf("num_candidates=%d\n", ctx.menu.num_candidates);
    for (int i = 0; i < ctx.menu.num_candidates && i < 12; i++) {
      printf("cand[%d]=%s | %s\n", i, ctx.menu.candidates[i].text,
             ctx.menu.candidates[i].comment ? ctx.menu.candidates[i].comment : "");
    }
    api->free_context(&ctx);

    // §89 全候選列舉 + 絕對索引選字驗證
    RimeCandidateListIterator it; memset(&it, 0, sizeof(it));
    int total = 0; const char *last = "(nil)";
    if (api->candidate_list_begin(s, &it)) {
      while (api->candidate_list_next(&it)) {
        if (total < 3 || total % 20 == 0)
          printf("allcand[%d]=%s\n", it.index, it.candidate.text ? it.candidate.text : "");
        last = it.candidate.text ? it.candidate.text : "(nil)";
        total++; if (total >= 200) break;
      }
      api->candidate_list_end(&it);
    }
    printf("allcand_total=%d last=%s\n", total, last);
    bool absok = api->select_candidate(s, 1);   // 絕對索引選第 2 個
    printf("select_candidate(abs1)=%d\n", absok ? 1 : 0);
    return 0;
  }
}
