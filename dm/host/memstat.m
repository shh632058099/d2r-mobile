// 内存账：DM_MEMSTAT=<tsv 路径> 时每秒记一行（Mac / iOS 通用）。
//   总量：phys_footprint（task_info TASK_VM_INFO，iOS 内存上限按它算）、os_proc_available_memory（仅 iOS）、Metal currentAllocatedSize
//   拆账：遍历本进程 VM 区（vm_region_recurse_64，VM_REGION_SUBMAP_INFO_64），按区归类，每类记
//         虚拟 = 地址空间大小（只预留也算）、常驻 = pages_resident、区域估算 = pages_dirtied + pages_swapped_out。
//         当前仅按 (对象号, 区域起始页) 抑制完全相同起点的重复项；这不是按页范围并集，不能当作严格物理内存拆账，共享 / 重叠映射仍可能重复计数。
//         因此区域估算合计可能高于 phys_footprint；差值为负表示估算偏差，不代表“负的未归属内存”。
//   类别：guest（客体地址空间整块，含 SetHeapSize 的堆、alias、栈；RomFS 经 pread 读进的数据也落在这里）、code（内嵌 / 装载的模块映像）、
//         malloc（宿主堆）、gpu（IOAccelerator / IOSurface / Metal 标签区）、stack、file（文件映射）、other
//   区域估算合计与 phys_footprint 不保证可加；footprint差值 = footprint − 区域估算合计，可正可负，不解释为「未归属」内存。
// Memory accounting: when DM_MEMSTAT=<tsv path> is set, one line is logged per second (common to Mac / iOS).
//   Totals: phys_footprint (task_info TASK_VM_INFO, which the iOS memory limit is based on), os_proc_available_memory (iOS only), Metal currentAllocatedSize
//   Breakdown: walk this process's VM regions (vm_region_recurse_64, VM_REGION_SUBMAP_INFO_64), classify by region, and for each class record
//         virtual = address space size, resident = pages_resident, region estimate = pages_dirtied + pages_swapped_out.
//         Current suppression only catches duplicate (object id, region-start offset) keys; it is not a page-range union, so shared / overlapping mappings may still be counted more than once.
//         The estimate sum can exceed phys_footprint; a negative delta indicates accounting-method error, not "negative unattributed memory".
//   Classes: guest (the whole guest address space block, including the SetHeapSize heap, alias, stacks; data read from RomFS through pread also lands here), code (embedded / loaded module images),
//         malloc (host heap), gpu (IOAccelerator / IOSurface / Metal tagged regions), stack, file (file mappings), other
//   Region-estimate sum and phys_footprint are not guaranteed to be additive; the signed footprint delta is not an "unattributed memory" measurement.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <TargetConditionals.h>
#include <mach/mach.h>
#if defined(__arm64__)
#include <mach/arm/thread_status.h>
#endif
#include <mach/vm_statistics.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdlib.h>
#if TARGET_OS_IPHONE
#include <os/proc.h>
#endif
#include "dm.h"

void svc_guest_range(uint8_t **base, size_t *size);
enum { C_GUEST, C_CODE, C_MALLOC, C_GPU, C_STACK, C_FILE, C_OTHER, NC };
static const char *k_cls[NC] = {"guest", "code", "malloc", "gpu", "stack", "file", "other"};

static int classify(vm_address_t a, const vm_region_submap_info_data_64_t *in) {
    uint8_t *gb; size_t gs; svc_guest_range(&gb, &gs);
    if (gb && a >= (vm_address_t)gb && a < (vm_address_t)gb + gs) return C_GUEST;
    for (int i = 0; i < g_nmod; i++)
        if (a >= (vm_address_t)g_mod[i].base && a < (vm_address_t)g_mod[i].base + g_mod[i].size) return C_CODE;
    switch (in->user_tag) {
        case VM_MEMORY_MALLOC: case VM_MEMORY_MALLOC_SMALL: case VM_MEMORY_MALLOC_LARGE: case VM_MEMORY_MALLOC_HUGE:
        case VM_MEMORY_MALLOC_TINY: case VM_MEMORY_MALLOC_LARGE_REUSABLE: case VM_MEMORY_MALLOC_LARGE_REUSED:
        case VM_MEMORY_MALLOC_NANO: case VM_MEMORY_MALLOC_MEDIUM: return C_MALLOC;
        case VM_MEMORY_IOACCELERATOR: case VM_MEMORY_IOSURFACE: case VM_MEMORY_IOKIT: return C_GPU;
        case VM_MEMORY_STACK: return C_STACK;
    }
    if (in->external_pager) return C_FILE;
    return C_OTHER;
}

// DM_MEMSTAT_DUMP=秒：到该秒时把每个 ≥1 MiB 的 VM 区逐行写到 <tsv>.regions（诊断记账口径用）
// DM_MEMSTAT_DUMP=seconds: at that second, write every VM region ≥1 MiB line by line to <tsv>.regions (for diagnosing the accounting method)
static void dump_regions(const char *path) {
    FILE *f = fopen(path, "w"); if (!f) return;
    fprintf(f, "起址	大小MiB	类别	user_tag	share_mode	obj_id	ref_count	常驻MiB	脏MiB	换出MiB	文件\n");
    vm_address_t a = 0; vm_size_t sz; natural_t depth = 0; vm_size_t pg = vm_page_size;
    for (;;) {
        vm_region_submap_info_data_64_t in; mach_msg_type_number_t cnt = VM_REGION_SUBMAP_INFO_COUNT_64;
        if (vm_region_recurse_64(mach_task_self(), &a, &sz, &depth, (vm_region_recurse_info_t)&in, &cnt) != KERN_SUCCESS) break;
        if (in.is_submap) { depth++; continue; }
        if (((uint64_t)in.pages_resident * pg >> 20) >= 1 || sz >= (64ull << 20))
            fprintf(f, "%#lx\t%lu\t%s\t%u\t%u\t%#x\t%u\t%llu\t%llu\t%llu\t%d\n", a, sz >> 20, k_cls[classify(a, &in)], in.user_tag, in.share_mode,
                    in.object_id, in.ref_count, (uint64_t)in.pages_resident * pg >> 20, (uint64_t)in.pages_dirtied * pg >> 20, (uint64_t)in.pages_swapped_out * pg >> 20, in.external_pager);
        a += sz;
    }
    fclose(f);
}

static void sample(FILE *f, double t, id<MTLDevice> dev) {
    task_vm_info_data_t vi; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    uint64_t fp = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vi, &n) == KERN_SUCCESS ? vi.phys_footprint : 0;
    uint64_t avail = 0;
#if TARGET_OS_IPHONE
    avail = os_proc_available_memory();
#endif
    uint64_t virt[NC] = {0}, res[NC] = {0}, estimate[NC] = {0};
    static uint32_t seen[1 << 16]; static uint32_t gen; gen++; if (!gen) { memset(seen, 0, sizeof seen); gen = 1; }   // 本次采样已计对象（开放寻址） | Objects already counted in this sample (open addressing)
    vm_address_t a = 0; vm_size_t sz; natural_t depth = 0; vm_size_t pg = vm_page_size;
    for (;;) {
        vm_region_submap_info_data_64_t in; mach_msg_type_number_t cnt = VM_REGION_SUBMAP_INFO_COUNT_64;
        if (vm_region_recurse_64(mach_task_self(), &a, &sz, &depth, (vm_region_recurse_info_t)&in, &cnt) != KERN_SUCCESS) break;
        if (in.is_submap) { depth++; continue; }
        int c = classify(a, &in);
        virt[c] += sz; res[c] += (uint64_t)in.pages_resident * pg;
        if (!in.external_pager) {                             // 文件页可回收，不进 footprint | File pages are reclaimable and do not count toward footprint
            static uint64_t key[1 << 16];                     // 键 = (对象号, 区域起始页)；只抑制完全相同的起点，重叠但起点不同的范围无法精确去重 | Key = (object id, region-start page); only identical starts are suppressed, overlapping ranges with different starts are not exactly deduplicated
            uint64_t k = (uint64_t)in.object_id << 32 ^ (in.offset / pg);
            uint32_t h = (uint32_t)((k * 0x9E3779B97F4A7C15ull) >> 48), dup = 0;
            while (seen[h] == gen) { if (key[h] == k) { dup = 1; break; } h = (h + 1) & 0xFFFF; }
            if (!dup) { seen[h] = gen; key[h] = k; estimate[c] += ((uint64_t)in.pages_dirtied + in.pages_swapped_out) * pg; }
        }
        a += sz; continue;
    }
    uint64_t estimate_sum = 0; for (int c = 0; c < NC; c++) estimate_sum += estimate[c];
    fprintf(f, "%.0f\t%llu\t%llu\t%llu\t%llu\t%llu\t%lld\t%lld", t, fp >> 20, avail >> 20, (unsigned long long)(dev.currentAllocatedSize >> 20),
            vi.internal >> 20, vi.compressed >> 20, (vi.ledger_tag_graphics_footprint + vi.ledger_tag_graphics_footprint_compressed) >> 20,
            (long long)(vi.limit_bytes_remaining >> 20));
    for (int c = 0; c < NC; c++) fprintf(f, "\t%llu/%llu/%llu", virt[c] >> 20, res[c] >> 20, estimate[c] >> 20);
    fprintf(f, "\t%llu\t%lld\n", estimate_sum >> 20, ((int64_t)fp - (int64_t)estimate_sum) >> 20);
    fflush(f);
}

static void *memstat_thread(void *p) {
    pthread_setname_np("dm-memstat");
    char path[1024]; int iv = 1; const char *spec = (const char *)p; const char *comma = strchr(spec, ',');
    snprintf(path, sizeof path, "%.*s", comma ? (int)(comma - spec) : (int)strlen(spec), spec);
    if (comma) iv = atoi(comma + 1);
    free(p);
    if (iv < 1) iv = 1;
    if (iv > 300) iv = 300;
    FILE *f = fopen(path, "w");
    if (!f) { LOG("memstat：打不开 %s", path); return NULL; }
    fprintf(f, "# 单位 MiB；internal/compressed/graphics/距上限为内核记账字段；类别列 = 虚拟/常驻/区域估算；区域估算合计可能因共享 / 重叠映射而重复计数；footprint差值 = phys_footprint − 区域估算合计（可为负，不代表未归属内存）\n秒\tphys_footprint\t可用\tmetal_alloc\tinternal\tcompressed\tgraphics\t距上限");
    for (int c = 0; c < NC; c++) fprintf(f, "\t%s", k_cls[c]);
    fprintf(f, "\t区域估算合计\tfootprint差值\n");
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();   // 与图形后端同一设备对象（系统缺省设备单例） | The same device object as the graphics backend (the system default device singleton)
    uint64_t t0 = now_ns();
    const char *ds = getenv("DM_MEMSTAT_DUMP"); int dump_at = ds ? atoi(ds) : -1;
    char dp[1100]; snprintf(dp, sizeof dp, "%s.regions", path);
    for (int elapsed = 0, dumped = 0;;) {
        sample(f, (now_ns() - t0) / 1e9, dev);
        if (!dumped && dump_at >= 0 && elapsed >= dump_at) { dump_regions(dp); dumped = 1; }
        sleep(iv); elapsed += iv;
    }
    return NULL;
}

static _Atomic int g_memstat_started;
void dm_memstat_start_configured(void) {
    const char *p = getenv("DM_MEMSTAT");
    if (!p || !*p) return;
    int expected = 0; if (!atomic_compare_exchange_strong(&g_memstat_started, &expected, 1)) return;
    char *path = strdup(p);
#if TARGET_OS_IPHONE
    if (*p != '/') {
        const char *home = getenv("HOME"); if (!home) home = "";
        const char *comma = strchr(p, ','); size_t base_len = comma ? (size_t)(comma - p) : strlen(p);
        size_t n = strlen(home) + base_len + (comma ? strlen(comma) : 0) + 16; char *full = malloc(n);
        if (full) { snprintf(full, n, "%s/Documents/%.*s%s", home, (int)base_len, p, comma ? comma : ""); free(path); path = full; }
        else { free(path); path = NULL; }
    }
#endif
    if (!path) { atomic_store(&g_memstat_started, 0); return; }
    pthread_t th; if (pthread_create(&th, NULL, memstat_thread, path)) { free(path); atomic_store(&g_memstat_started, 0); return; }
    pthread_detach(th);
}
__attribute__((constructor)) static void memstat_start(void) { dm_memstat_start_configured(); }

// ---------- 按线程 CPU：DM_THRCPU=<tsv 路径>[,间隔秒（缺省 10）]（Mac / iOS 通用；iOS 相对名 → 容器 Documents）----------
// 每个间隔遍历本进程全部线程（task_threads），THREAD_EXTENDED_INFO 取线程名与用户 + 系统 CPU 时间（ns），按线程号差分：
// 每行「秒 线程号 线程名 CPU%（100 = 一个核）未命名高占用线程的 PC」；末行「秒 - 合计 CPU% -」。PC 只对未命名且 CPU ≥5% 的线程做一次尽力读取。
// ---------- Per-thread CPU: DM_THRCPU=<tsv path>[,interval in seconds (default 10)] (common to Mac / iOS; on iOS a relative name → the container's Documents) ----------
// Every interval, walk all threads of this process (task_threads), take the thread name and user + system CPU time (ns) from THREAD_EXTENDED_INFO, and difference them by thread id:
// each row is "seconds, thread id, thread name, CPU% (100 = one core), PC for unnamed hot threads"; the total row has "seconds, -, total, CPU%, -". The PC is a best-effort single sample only for unnamed threads at >=5% CPU.
#include <mach/thread_info.h>
#define THR_MAX 512
// Best-effort PC sample for a hot unnamed thread; does not explicitly suspend the sampled thread.
static void thrcpu_pc(thread_act_t th, char *out, size_t cap) {
    if (!cap) return;
    snprintf(out, cap, "?");
#if defined(__arm64__)
    arm_thread_state64_t st; mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(th, ARM_THREAD_STATE64, (thread_state_t)&st, &count) != KERN_SUCCESS) return;
    uint64_t pc = __darwin_arm_thread_state64_get_pc(st);
    module_t *m = module_of((const void *)(uintptr_t)pc);
    if (m) { snprintf(out, cap, "%s+%#llx", m->name, (unsigned long long)(pc - (uint64_t)m->base)); return; }
    Dl_info info;
    if (dladdr((const void *)(uintptr_t)pc, &info) && info.dli_fname) {
        const char *base = strrchr(info.dli_fname, '/'); base = base ? base + 1 : info.dli_fname;
        if (info.dli_sname && info.dli_saddr)
            snprintf(out, cap, "%s!%s+%#llx", base, info.dli_sname, (unsigned long long)(pc - (uintptr_t)info.dli_saddr));
        else if (info.dli_fbase)
            snprintf(out, cap, "%s+%#llx", base, (unsigned long long)(pc - (uintptr_t)info.dli_fbase));
        else snprintf(out, cap, "%s@%#llx", base, (unsigned long long)pc);
    } else snprintf(out, cap, "%#llx", (unsigned long long)pc);
#else
    (void)th;
    snprintf(out, cap, "unsupported");
#endif
}
static void *thrcpu_thread(void *p) {
    pthread_setname_np("dm-thrcpu");
    char path[1024]; int iv = 10; { const char *c = strchr((const char *)p, ','); snprintf(path, sizeof path, "%.*s", c ? (int)(c - (const char *)p) : (int)strlen(p), (const char *)p); if (c) iv = atoi(c + 1); }
    free(p);
    if (iv < 1) iv = 1; if (iv > 300) iv = 300;
    FILE *f = fopen(path, "w"); if (!f) return NULL;
    fprintf(f, "秒\t线程号\t线程名\tCPU%%\t高占用未命名线程PC\n"); fflush(f);
    static uint64_t ids[THR_MAX], last[THR_MAX]; int n = 0; uint64_t t0 = now_ns(), tl = t0;
    for (;;) {
        sleep(iv); uint64_t t = now_ns(); double dt = (t - tl) / 1e9, tot = 0; tl = t;
        thread_act_array_t th; mach_msg_type_number_t nt = 0;
        if (task_threads(mach_task_self(), &th, &nt) != KERN_SUCCESS) continue;
        for (mach_msg_type_number_t i = 0; i < nt; i++) {
            thread_extended_info_data_t ei; mach_msg_type_number_t c1 = THREAD_EXTENDED_INFO_COUNT;
            thread_identifier_info_data_t ii; mach_msg_type_number_t c2 = THREAD_IDENTIFIER_INFO_COUNT;
            if (thread_info(th[i], THREAD_EXTENDED_INFO, (thread_info_t)&ei, &c1) == KERN_SUCCESS && thread_info(th[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&ii, &c2) == KERN_SUCCESS) {
                uint64_t cpu = ei.pth_user_time + ei.pth_system_time; int k = 0; while (k < n && ids[k] != ii.thread_id) k++;
                if (k == n && n < THR_MAX) { ids[n] = ii.thread_id; last[n] = cpu; n++; }   // 新线程：本轮只记基线 | New thread: only record the baseline this round
                else if (k < n) { double pct = (cpu - last[k]) / 1e9 / dt * 100; last[k] = cpu; tot += pct;
                    if (pct >= 0.5) { char gn[96], pc[192] = "-"; int thr_name_of(pthread_t, char *, size_t); pthread_t pt = pthread_from_mach_thread_np(th[i]);
                        int guest_named = pt && thr_name_of(pt, gn, sizeof gn); const char *nm = guest_named ? gn : ei.pth_name[0] ? ei.pth_name : "-";   // 客体线程：句柄 + 客体名；宿主线程：pthread 名 | Guest thread: handle + guest name; host thread: pthread name
                        if (!guest_named && !ei.pth_name[0] && pct >= 5.0) {
                            thrcpu_pc(th[i], pc, sizeof pc);
                            // 单个 PC 易碰巧停在 mach_msg；对 CPU>20% 的无名线程再隔 2ms 取两次，诊断模式才开启。
                            if (pct >= 20.0) {
                                char a[96], b[96]; usleep(2000); thrcpu_pc(th[i], a, sizeof a);
                                usleep(2000); thrcpu_pc(th[i], b, sizeof b);
                                size_t used = strlen(pc);
                                if (used < sizeof pc) snprintf(pc + used, sizeof pc - used, " | %s | %s", a, b);
                            }
                        }
                        fprintf(f, "%.0f\t%llu\t%s\t%.1f\t%s\n", (t - t0) / 1e9, ii.thread_id, nm, pct, pc); } }
            }
            mach_port_deallocate(mach_task_self(), th[i]);
        }
        vm_deallocate(mach_task_self(), (vm_address_t)th, nt * sizeof *th);
        fprintf(f, "%.0f\t-\t合计\t%.1f\t-\n", (t - t0) / 1e9, tot); fflush(f);
    }
    return NULL;
}
static _Atomic int g_thrcpu_started;
void dm_thrcpu_start_configured(void) {
    const char *p = getenv("DM_THRCPU");
    if (!p || !*p) return;
    int expected = 0; if (!atomic_compare_exchange_strong(&g_thrcpu_started, &expected, 1)) return;
    char *spec = strdup(p);
#if TARGET_OS_IPHONE
    if (*p != '/') {
        const char *home = getenv("HOME"); if (!home) home = "";
        size_t n = strlen(home) + strlen(p) + 16; char *full = malloc(n);
        if (full) { snprintf(full, n, "%s/Documents/%s", home, p); free(spec); spec = full; }
        else { free(spec); spec = NULL; }
    }
#endif
    if (!spec) { atomic_store(&g_thrcpu_started, 0); return; }
    pthread_t th; if (pthread_create(&th, NULL, thrcpu_thread, spec)) { free(spec); atomic_store(&g_thrcpu_started, 0); return; }
    pthread_detach(th);
}
__attribute__((constructor)) static void thrcpu_start(void) { dm_thrcpu_start_configured(); }
