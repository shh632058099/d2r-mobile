#ifndef DM_NVN_POOL_HINT_H
#define DM_NVN_POOL_HINT_H
#include <stdint.h>

// Reuse a lookup only for the exact address/length and unchanged pool table;
// this preserves first-match behavior even if registered ranges ever overlap.
static inline int nvn_pool_hint_key_matches(uint64_t cached_gen, uint64_t current_gen, uint64_t cached_addr, uint64_t addr, uint64_t cached_len, uint64_t len) {
    return cached_gen == current_gen && cached_addr == addr && cached_len == len;
}

// A cached pool index is usable only while the pool table generation matches.
// The caller must validate the index before reading that pool's range.
static inline int nvn_pool_hint_index_valid(int hint, int count, uint64_t cached_gen, uint64_t current_gen) {
    return hint >= 0 && hint < count && cached_gen == current_gen;
}

// The caller holds the pool-table lock while checking this range.
static inline int nvn_pool_hint_range_matches(uint64_t addr, uint64_t len, uint64_t lo, uint64_t hi) {
    return addr >= lo && addr <= hi && len <= hi - addr;
}
#endif
