#ifndef DM_NVN_VBUF_CACHE_H
#define DM_NVN_VBUF_CACHE_H
#include <stdint.h>

// A render encoder owns slots 0..31. Its serial changes whenever a new
// encoder is opened, including a restart with identical render targets.
typedef struct {
    uint64_t pass;
    uint64_t gpu[32];
    uint32_t valid;
    uint64_t sent, skipped;
} nvn_vbuf_cache;

static inline int nvn_vbuf_should_bind(nvn_vbuf_cache *c, uint64_t pass, unsigned slot, uint64_t gpu) {
    if (slot >= 32) return 1; // Never suppress an unexpected index.
    if (c->pass != pass) { c->pass = pass; c->valid = 0; }
    const uint32_t bit = (uint32_t)1u << slot;
    if ((c->valid & bit) && c->gpu[slot] == gpu) { c->skipped++; return 0; }
    c->valid |= bit;
    c->gpu[slot] = gpu;
    c->sent++;
    return 1;
}
#endif
