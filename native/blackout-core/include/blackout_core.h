/**
 * BlackoutCore — Unified In-House Native VPN & Proxy Engine
 * Clean C-ABI Interface for Android (VpnService) & iOS (PacketTunnelProvider)
 */

#ifndef BLACKOUT_CORE_H
#define BLACKOUT_CORE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Status / Return Codes */
#define BLACKOUT_OK 0
#define BLACKOUT_ERR_INVALID_PARAM -1
#define BLACKOUT_ERR_ALREADY_RUNNING -2
#define BLACKOUT_ERR_NOT_RUNNING -3
#define BLACKOUT_ERR_CONFIG_PARSE -4
#define BLACKOUT_ERR_NETSTACK -5
#define BLACKOUT_ERR_DIAL -6
#define BLACKOUT_ERR_INTERNAL -99

/**
 * Tunnel Statistics
 */
typedef struct {
    uint64_t tx_bytes;
    uint64_t rx_bytes;
    uint64_t tx_packets;
    uint64_t rx_packets;
    uint32_t active_connections;
} blackout_stats_t;

/**
 * Initializes the native engine runtime & logging subscriber.
 * Safe to call multiple times.
 *
 * @param log_level 0=error, 1=warn, 2=info, 3=debug, 4=trace
 * @return BLACKOUT_OK on success
 */
int32_t blackout_init(int32_t log_level);

/**
 * Starts the proxy tunnel on the provided TUN file descriptor.
 *
 * In Android VpnService: pass the fd returned by VpnService.Builder.establish().
 * In iOS PacketTunnelProvider: pass the virtual socket descriptor.
 *
 * @param tun_fd Valid open file descriptor to the TUN interface
 * @param config_json Null-terminated JSON string containing proxy options
 * @return BLACKOUT_OK on success, or negative error code
 */
int32_t blackout_start(int32_t tun_fd, const char* config_json);

/**
 * Gracefully stops the active tunnel and terminates all child connections.
 * Safe to call even if the engine is stopped.
 *
 * @return BLACKOUT_OK on success
 */
int32_t blackout_stop(void);

/**
 * Checks if the engine is currently active and processing packets.
 *
 * @return true if running, false otherwise
 */
bool blackout_is_running(void);

/**
 * Copies the current tunnel stats into the provided buffer.
 *
 * @param stats Pointer to blackout_stats_t buffer
 * @return BLACKOUT_OK on success
 */
int32_t blackout_get_stats(blackout_stats_t* stats);

/**
 * Retrieves the last error message recorded by the engine.
 *
 * @param buffer Output char buffer
 * @param max_len Maximum bytes to copy (including null terminator)
 * @return Length of copied error message
 */
int32_t blackout_get_last_error(char* buffer, int32_t max_len);

/**
 * Returns a static string representing the engine version.
 */
const char* blackout_version(void);

#ifdef __cplusplus
}
#endif

#endif /* BLACKOUT_CORE_H */
