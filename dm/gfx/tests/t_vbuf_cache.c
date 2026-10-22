#include <assert.h>
#include <stdint.h>
#include "../nvn/nvn_vbuf_cache.h"
int main(void) {
    nvn_vbuf_cache c = {0};
    assert(nvn_vbuf_should_bind(&c, 1, 16, 0x1234));
    assert(!nvn_vbuf_should_bind(&c, 1, 16, 0x1234));
    assert(nvn_vbuf_should_bind(&c, 1, 16, 0x5678));
    assert(nvn_vbuf_should_bind(&c, 1, 17, 0x5678));
    // Slot 30 receives a zero buffer at the end of each draw, and might
    // have been used by vertex stream 14 earlier in that same draw.
    assert(nvn_vbuf_should_bind(&c, 1, 30, 0x9999));
    assert(nvn_vbuf_should_bind(&c, 1, 30, 0xaaaa));
    assert(!nvn_vbuf_should_bind(&c, 1, 30, 0xaaaa));
    assert(nvn_vbuf_should_bind(&c, 2, 16, 0x5678));
    assert(nvn_vbuf_should_bind(&c, 2, 30, 0xaaaa));
    assert(!nvn_vbuf_should_bind(&c, 2, 16, 0x5678));
    assert(nvn_vbuf_should_bind(&c, 2, 32, 0x5678));
    assert(c.sent == 7 && c.skipped == 3);
    return 0;
}
