#ifndef DM_THERMAL_POLICY_H
#define DM_THERMAL_POLICY_H
// Pure transition logic for the iPhone 15 Pro Max auto cooling cap.
// A fair state must persist before throttling; restore only after sustained nominal.
typedef struct { int cap30; int last_state; double since; } dm_thermal_policy;
static inline void dm_thermal_policy_update(dm_thermal_policy *p, int state, double now) {
    if (state != p->last_state || p->since < 0) {
        p->last_state = state;
        p->since = now;
    }
    if (state >= 2 || (state == 1 && now - p->since >= 45.0)) p->cap30 = 1;
    else if (state == 0 && now - p->since >= 60.0) p->cap30 = 0;
}
#endif
