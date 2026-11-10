/* Ask the CDSP what it is, through FastRPC's capability query. Read-only.
 *   gcc -o npu-caps npu-caps.c -I/usr/include/fastrpc -lcdsprpc
 *   sudo ./npu-caps
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <remote.h>

static const char *const names[] = {
    "DOMAIN_SUPPORT", "UNSIGNED_PD_SUPPORT", "HVX_SUPPORT_64B",
    "HVX_SUPPORT_128B", "VTCM_PAGE", "VTCM_COUNT", "ARCH_VER",
    "HMX_SUPPORT_DEPTH", "HMX_SUPPORT_SPATIAL", "ASYNC_FASTRPC_SUPPORT",
    "STATUS_NOTIFICATION_SUPPORT", "MCID_MULTICAST",
};

int main(void)
{
    int fail = 0;

    for (unsigned int i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        struct remote_dsp_capability cap;

        memset(&cap, 0, sizeof(cap));
        cap.domain = CDSP_DOMAIN_ID;
        cap.attribute_ID = i;
        int rc = remote_handle_control(DSPRPC_GET_DSP_INFO, &cap, sizeof(cap));
        if (rc)
            fail++;
        printf("%-28s %s%u (rc=%d)\n", names[i], rc ? "? " : "", cap.capability, rc);
    }
    return fail ? 1 : 0;
}
