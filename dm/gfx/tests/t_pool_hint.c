#include <assert.h>
#include <stdint.h>
#include "../nvn/nvn_pool_hint.h"

int main(void) {
    assert(nvn_pool_hint_index_valid(0, 1, 7, 7));
    assert(!nvn_pool_hint_index_valid(-1, 1, 7, 7));
    assert(!nvn_pool_hint_index_valid(1, 1, 7, 7));
    assert(!nvn_pool_hint_index_valid(0, 1, 7, 8));
    assert(nvn_pool_hint_key_matches(7, 7, 0x1100, 0x1100, 1, 1));
    assert(!nvn_pool_hint_key_matches(7, 8, 0x1100, 0x1100, 1, 1));
    assert(!nvn_pool_hint_key_matches(7, 7, 0x1100, 0x1101, 1, 1));
    assert(!nvn_pool_hint_key_matches(7, 7, 0x1100, 0x1100, 1, 2));
    assert(nvn_pool_hint_range_matches(0x1100, 1, 0x1000, 0x2000));
    assert(nvn_pool_hint_range_matches(0x1fff, 1, 0x1000, 0x2000));
    assert(!nvn_pool_hint_range_matches(0x0fff, 1, 0x1000, 0x2000));
    assert(!nvn_pool_hint_range_matches(0x2000, 1, 0x1000, 0x2000));
    assert(!nvn_pool_hint_range_matches(UINT64_MAX, 2, 0, UINT64_MAX));
    return 0;
}
