#include "../Sources/dm_thermal_policy.h"
#include <assert.h>
int main(void) {
    dm_thermal_policy p = { .last_state = -1, .since = -1 };
    dm_thermal_policy_update(&p, 0, 0); assert(!p.cap30);
    dm_thermal_policy_update(&p, 1, 1); dm_thermal_policy_update(&p, 1, 45); assert(!p.cap30);
    dm_thermal_policy_update(&p, 1, 46); assert(p.cap30);
    dm_thermal_policy_update(&p, 0, 47); dm_thermal_policy_update(&p, 0, 106); assert(p.cap30);
    dm_thermal_policy_update(&p, 0, 107); assert(!p.cap30);
    dm_thermal_policy_update(&p, 2, 108); assert(p.cap30);
    dm_thermal_policy_update(&p, 3, 109); assert(p.cap30);
    dm_thermal_policy_update(&p, 0, 110); dm_thermal_policy_update(&p, 0, 170); assert(!p.cap30);
    return 0;
}
