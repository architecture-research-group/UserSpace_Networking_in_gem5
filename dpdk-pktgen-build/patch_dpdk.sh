diff --git a/dpdk/app/test-pmd/cmdline.c b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/cmdline.c
index 6e10afee..cddca9d3 100644
--- a/dpdk/app/test-pmd/cmdline.c
+++ b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/cmdline.c
@@ -1835,7 +1835,16 @@ cmd_config_rx_tx_parsed(void *parsed_result,
 			return;
 
 		nb_txd = res->value;
-	} else {
+	} // else if ( !strcmp(res->name, "proc_cycles")) {
+	  //      if(check_proc_cycles(res->value) != 0)
+	  //              return;
+	  //      proc_cycles = res->value;
+	  // } 
+	else if ( !strcmp(res->name, "proc_times")) {
+		if(check_proc_cycles(res->value) != 0)
+			return;
+		proc_cycles = res->value/10;                                                                                                        }
+	else {
 		fprintf(stderr, "Unknown parameter\n");
 		return;
 	}
diff --git a/dpdk/app/test-pmd/meson.build b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/meson.build
index 43130c88..2d47ce21 100644
--- a/dpdk/app/test-pmd/meson.build
+++ b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/meson.build
@@ -22,6 +22,8 @@ sources = files(
         'noisy_vnf.c',
         'parameters.c',
         'rxonly.c',
+        'touchfwd.c',
+        'rxptx.c',
         'shared_rxq_fwd.c',
         'testpmd.c',
         'txonly.c',
diff --git a/dpdk/app/test-pmd/parameters.c b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/parameters.c
index f9185065..67dc0347 100644
--- a/dpdk/app/test-pmd/parameters.c
+++ b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/parameters.c
@@ -141,6 +141,8 @@ usage(char* progname)
 	printf("  --txd=N: set the number of descriptors in TX rings to N.\n");
 	printf("  --hairpinq=N: set the number of hairpin queues per port to "
 	       "N.\n");
+	// printf("  --proc_cycles=N: set the number of processing cycles to N.\n");
+	printf("  --proc_times=N: set the number of processing time to N ns.\n");
 	printf("  --burst=N: set the number of packets per burst to N.\n");
 	printf("  --flowgen-clones=N: set the number of single packet clones to send in flowgen mode. Should be less than burst value.\n");
 	printf("  --flowgen-flows=N: set the number of flows in flowgen mode to N (1 <= N <= INT32_MAX).\n");
@@ -654,6 +656,8 @@ launch_args_parse(int argc, char** argv)
 		{ "txq",			1, 0, 0 },
 		{ "rxd",			1, 0, 0 },
 		{ "txd",			1, 0, 0 },
+		// { "proc_cycles",		1, 0, 0 },
+		{ "proc_times",		1, 0, 0 },
 		{ "hairpinq",			1, 0, 0 },
 		{ "hairpin-mode",		1, 0, 0 },
 		{ "burst",			1, 0, 0 },
@@ -1262,6 +1266,22 @@ launch_args_parse(int argc, char** argv)
 				else
 					rte_exit(EXIT_FAILURE, "txd must be in > 0\n");
 			}
+			// if (!strcmp(lgopts[opt_idx].name, "proc_cycles")) {
+			// 	n = atoi(optarg);
+			// 	if (n >= 0)
+			// 		proc_cycles = (uint64_t) n;
+			// 	else
+			// 		rte_exit(EXIT_FAILURE, "proc_cycles must be in >= 0\n");
+			// }
+			if (!strcmp(lgopts[opt_idx].name, "proc_times")) {
+				n = atoi(optarg); // n is proc_times
+				if (n >= 0) {
+					// perform conversion from proc_times to proc_cycles
+					proc_cycles = (uint64_t) n/10;
+				}
+				else
+					rte_exit(EXIT_FAILURE, "proc_times must be in >= 0\n");
+			}
 			if (!strcmp(lgopts[opt_idx].name, "txpt")) {
 				n = atoi(optarg);
 				if (n >= 0)
diff --git a/dpdk/app/test-pmd/rxonly.c b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/rxonly.c
index d1a579d8..8c07ccbc 100644
--- a/dpdk/app/test-pmd/rxonly.c
+++ b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/rxonly.c
@@ -38,6 +38,7 @@
 #include <rte_flow.h>
 
 #include "testpmd.h"
+volatile char flag;
 
 /*
  * Received a burst of packets.
@@ -46,6 +47,7 @@ static void
 pkt_burst_receive(struct fwd_stream *fs)
 {
 	struct rte_mbuf  *pkts_burst[MAX_PKT_BURST];
+	struct rte_mbuf  *mb;	
 	uint16_t nb_rx;
 	uint16_t i;
 	uint64_t start_tsc = 0;
@@ -60,6 +62,23 @@ pkt_burst_receive(struct fwd_stream *fs)
 	inc_rx_burst_stats(fs, nb_rx);
 	if (unlikely(nb_rx == 0))
 		return;
+	
+	for (int i = 0; i < nb_rx; i++) {
+		if (likely(i < nb_rx - 1)) 
+			rte_prefetch0(rte_pktmbuf_mtod(pkts_burst[i + 1], void *));
+				
+		char *pkt_data;
+
+		mb = pkts_burst[i];
+		pkt_data = rte_pktmbuf_mtod(mb, char *);
+												
+		for (uint j = 0; j < mb->pkt_len; j++)
+		{
+			// Do something with data here
+			if (pkt_data[j] == 255)
+			flag = pkt_data[j];
+		}
+	}
 
 	fs->rx_packets += nb_rx;
 	for (i = 0; i < nb_rx; i++)
diff --git a/dpdk/app/test-pmd/rxptx.c b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/rxptx.c
index e69de29b..dc852b97 100644
--- a/dpdk/app/test-pmd/rxptx.c
+++ b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/rxptx.c
@@ -0,0 +1,114 @@
+/* SPDX-License-Identifier: BSD-3-Clause
+ * Copyright 2014-2020 Mellanox Technologies, Ltd
+ */
+
+#include <stdarg.h>
+#include <string.h>
+#include <stdio.h>
+#include <errno.h>
+#include <stdint.h>
+#include <unistd.h>
+#include <inttypes.h>
+
+#include <sys/queue.h>
+#include <sys/stat.h>
+
+#include <rte_common.h>
+#include <rte_byteorder.h>
+#include <rte_log.h>
+#include <rte_debug.h>
+#include <rte_cycles.h>
+#include <rte_memory.h>
+#include <rte_memcpy.h>
+#include <rte_launch.h>
+#include <rte_eal.h>
+#include <rte_per_lcore.h>
+#include <rte_lcore.h>
+#include <rte_atomic.h>
+#include <rte_branch_prediction.h>
+#include <rte_mempool.h>
+#include <rte_mbuf.h>
+#include <rte_interrupts.h>
+#include <rte_pci.h>
+#include <rte_ether.h>
+#include <rte_ethdev.h>
+#include <rte_ip.h>
+#include <rte_string_fns.h>
+#include <rte_flow.h>
+
+#include "testpmd.h"
+#if defined(RTE_ARCH_X86)
+#include "macswap_sse.h"
+#elif defined(__ARM_NEON)
+#include "macswap_neon.h"
+#else
+#include "macswap.h"
+#endif
+
+/*
+ * MAC swap forwarding mode: Swap the source and the destination Ethernet
+ * addresses of packets before forwarding them.
+ */
+
+static void
+pkt_burst_rxptx(struct fwd_stream *fs)
+{
+	struct rte_mbuf  *pkts_burst[MAX_PKT_BURST];
+	struct rte_port  *txp;
+	struct rte_mbuf  *mb;
+	uint16_t nb_rx;
+	uint16_t nb_tx;
+	uint32_t retry;
+	uint64_t start_tsc = 0;
+
+	get_start_cycles(&start_tsc);
+
+	/*
+	 * Receive a burst of packets and forward them.
+	 */
+	nb_rx = rte_eth_rx_burst(fs->rx_port, fs->rx_queue, pkts_burst,
+				 nb_pkt_per_burst);
+	inc_rx_burst_stats(fs, nb_rx);
+	if (unlikely(nb_rx == 0))
+		return;
+
+	/*
+	* wait for PROCESSING_CYCLES, then forward packet
+	*/
+
+	wait_cycles();
+
+	fs->rx_packets += nb_rx;
+	txp = &ports[fs->tx_port];
+
+	do_macswap(pkts_burst, nb_rx, txp);
+
+	nb_tx = rte_eth_tx_burst(fs->tx_port, fs->tx_queue, pkts_burst, nb_rx);
+	/*
+	 * Retry if necessary
+	 */
+	if (unlikely(nb_tx < nb_rx) && fs->retry_enabled) {
+		retry = 0;
+		while (nb_tx < nb_rx && retry++ < burst_tx_retry_num) {
+			rte_delay_us(burst_tx_delay_time);
+			nb_tx += rte_eth_tx_burst(fs->tx_port, fs->tx_queue,
+					&pkts_burst[nb_tx], nb_rx - nb_tx);
+		}
+	}
+	fs->tx_packets += nb_tx;
+	inc_tx_burst_stats(fs, nb_tx);
+	if (unlikely(nb_tx < nb_rx)) {
+		fs->fwd_dropped += (nb_rx - nb_tx);
+		do {
+			rte_pktmbuf_free(pkts_burst[nb_tx]);
+		} while (++nb_tx < nb_rx);
+	}
+	get_end_cycles(fs, start_tsc);
+}
+
+struct fwd_engine recv_proc_txmit_engine = {
+	.fwd_mode_name  = "rxptx",
+	.port_fwd_begin = NULL,
+	.port_fwd_end   = NULL,
+	.packet_fwd     = pkt_burst_rxptx,
+};
diff --git a/dpdk/app/test-pmd/testpmd.c b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/testpmd.c
index 55eb293c..8ad96b11 100644
--- a/dpdk/app/test-pmd/testpmd.c
+++ b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/testpmd.c
@@ -181,6 +181,8 @@ struct fwd_engine * fwd_engines[] = {
 	&mac_swap_engine,
 	&flow_gen_engine,
 	&rx_only_engine,
+	&touch_fwd_engine,
+	&recv_proc_txmit_engine,
 	&tx_only_engine,
 	&csum_fwd_engine,
 	&icmp_echo_engine,
@@ -280,6 +282,12 @@ queueid_t nb_txq = 1; /**< Number of TX queues per port. */
 uint16_t nb_rxd = RTE_TEST_RX_DESC_DEFAULT; /**< Number of RX descriptors. */
 uint16_t nb_txd = RTE_TEST_TX_DESC_DEFAULT; /**< Number of TX descriptors. */
 
+/*
+ * Configurable value of processing number of cycles.
+ */
+#define RTE_TEST_PROC_CYCLES_DEFAULT 0
+uint64_t proc_cycles = RTE_TEST_PROC_CYCLES_DEFAULT;
+
 #define RTE_PMD_PARAM_UNSET -1
 /*
  * Configurable values of RX and TX ring threshold registers.
@@ -1486,6 +1494,25 @@ check_nb_txd(queueid_t txd)
 }
 
 
+/*
+* Check if the processing cycle is valid
+*/
+
+int
+check_proc_cycles(uint64_t cycles){
+	if(cycles < 0)
+		return -1;
+	return 0;
+}
+
+// Function to introduce a delay in terms of CPU cycles
+void wait_cycles(void) {
+    uint64_t start = rte_rdtsc();
+    while (rte_rdtsc() - start < proc_cycles) {
+        // Wait until the required number of cycles has passed
+    }
+}
+
 /*
  * Get the allowed maximum number of hairpin queues.
  * *pid return the port id which has minimal value of
@@ -2130,6 +2157,7 @@ fwd_stats_reset(void)
 static void
 flush_fwd_rx_queues(void)
 {
+	printf("flush_fwd_rx_queues \n");
 	struct rte_mbuf *pkts_burst[MAX_PKT_BURST];
 	portid_t  rxp;
 	portid_t port_id;
@@ -2277,6 +2305,7 @@ launch_packet_forwarding(lcore_function_t *pkt_fwd_on_lcore)
 void
 start_packet_forwarding(int with_tx_first)
 {
+	printf("start_packet_forwarding \n");
 	port_fwd_begin_t port_fwd_begin;
 	port_fwd_end_t  port_fwd_end;
 	unsigned int i;
diff --git a/dpdk/app/test-pmd/testpmd.h b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/testpmd.h
index 2149ecd9..bf3fe3b4 100644
--- a/dpdk/app/test-pmd/testpmd.h
+++ b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/testpmd.h
@@ -337,6 +337,8 @@ extern struct fwd_engine mac_fwd_engine;
 extern struct fwd_engine mac_swap_engine;
 extern struct fwd_engine flow_gen_engine;
 extern struct fwd_engine rx_only_engine;
+extern struct fwd_engine touch_fwd_engine;
+extern struct fwd_engine recv_proc_txmit_engine;
 extern struct fwd_engine tx_only_engine;
 extern struct fwd_engine csum_fwd_engine;
 extern struct fwd_engine icmp_echo_engine;
@@ -463,6 +465,8 @@ extern queueid_t nb_txq;
 extern uint16_t nb_rxd;
 extern uint16_t nb_txd;
 
+extern uint64_t proc_cycles;
+
 extern int16_t rx_free_thresh;
 extern int8_t rx_drop_en;
 extern int16_t tx_free_thresh;
@@ -1063,6 +1067,8 @@ queueid_t get_allowed_max_nb_txq(portid_t *pid);
 int check_nb_txq(queueid_t txq);
 int check_nb_rxd(queueid_t rxd);
 int check_nb_txd(queueid_t txd);
+int check_proc_cycles(uint64_t cycles);
+void wait_cycles(void);
 queueid_t get_allowed_max_nb_hairpinq(portid_t *pid);
 int check_nb_hairpinq(queueid_t hairpinq);
 
diff --git a/dpdk/app/test-pmd/touchfwd.c b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/touchfwd.c
index e69de29b..355b0ac2 100644
--- a/dpdk/app/test-pmd/touchfwd.c
+++ b/home/c834u979/derrick_mlnx/dpdk/app/test-pmd/touchfwd.c
@@ -0,0 +1,125 @@
+/* SPDX-License-Identifier: BSD-3-Clause
+ * Copyright 2014-2020 Mellanox Technologies, Ltd
+ */
+
+#include <stdarg.h>
+#include <string.h>
+#include <stdio.h>
+#include <errno.h>
+#include <stdint.h>
+#include <unistd.h>
+#include <inttypes.h>
+
+#include <sys/queue.h>
+#include <sys/stat.h>
+
+#include <rte_common.h>
+#include <rte_byteorder.h>
+#include <rte_log.h>
+#include <rte_debug.h>
+#include <rte_cycles.h>
+#include <rte_memory.h>
+#include <rte_memcpy.h>
+#include <rte_launch.h>
+#include <rte_eal.h>
+#include <rte_per_lcore.h>
+#include <rte_lcore.h>
+#include <rte_atomic.h>
+#include <rte_branch_prediction.h>
+#include <rte_mempool.h>
+#include <rte_mbuf.h>
+#include <rte_interrupts.h>
+#include <rte_pci.h>
+#include <rte_ether.h>
+#include <rte_ethdev.h>
+#include <rte_ip.h>
+#include <rte_string_fns.h>
+#include <rte_flow.h>
+
+#include "testpmd.h"
+#if defined(RTE_ARCH_X86)
+#include "macswap_sse.h"
+#elif defined(__ARM_NEON)
+#include "macswap_neon.h"
+#else
+#include "macswap.h"
+#endif
+
+volatile char flag_touch;
+/*
+ * MAC swap forwarding mode: Swap the source and the destination Ethernet
+ * addresses of packets before forwarding them.
+ */
+static void
+pkt_burst_touch(struct fwd_stream *fs)
+{
+	struct rte_mbuf  *pkts_burst[MAX_PKT_BURST];
+	struct rte_port  *txp;
+	struct rte_mbuf  *mb;
+	uint16_t nb_rx;
+	uint16_t nb_tx;
+	uint32_t retry;
+	uint64_t start_tsc = 0;
+
+	get_start_cycles(&start_tsc);
+
+	/*
+	 * Receive a burst of packets and forward them.
+	 */
+	nb_rx = rte_eth_rx_burst(fs->rx_port, fs->rx_queue, pkts_burst,
+				 nb_pkt_per_burst);
+	inc_rx_burst_stats(fs, nb_rx);
+	if (unlikely(nb_rx == 0))
+		return;
+
+	for (int i = 0; i < nb_rx; i++) {
+		if (likely(i < nb_rx - 1)) 
+			rte_prefetch0(rte_pktmbuf_mtod(pkts_burst[i + 1], void *));
+	
+		char *pkt_data;
+
+		mb = pkts_burst[i];
+		pkt_data = rte_pktmbuf_mtod(mb, char *);
+		
+		for (uint j = 0; j < mb->pkt_len; j++)
+		{
+			// Do something with data here
+			if (pkt_data[j] == 255)
+				flag_touch = pkt_data[j];
+		}
+	}
+
+	fs->rx_packets += nb_rx;
+	txp = &ports[fs->tx_port];
+
+	do_macswap(pkts_burst, nb_rx, txp);
+
+	nb_tx = rte_eth_tx_burst(fs->tx_port, fs->tx_queue, pkts_burst, nb_rx);
+	/*
+	 * Retry if necessary
+	 */
+	if (unlikely(nb_tx < nb_rx) && fs->retry_enabled) {
+		retry = 0;
+		while (nb_tx < nb_rx && retry++ < burst_tx_retry_num) {
+			rte_delay_us(burst_tx_delay_time);
+			nb_tx += rte_eth_tx_burst(fs->tx_port, fs->tx_queue,
+					&pkts_burst[nb_tx], nb_rx - nb_tx);
+		}
+	}
+	fs->tx_packets += nb_tx;
+	inc_tx_burst_stats(fs, nb_tx);
+	if (unlikely(nb_tx < nb_rx)) {
+		fs->fwd_dropped += (nb_rx - nb_tx);
+		do {
+			rte_pktmbuf_free(pkts_burst[nb_tx]);
+		} while (++nb_tx < nb_rx);
+	}
+	get_end_cycles(fs, start_tsc);
+}
+
+struct fwd_engine touch_fwd_engine = {
+	.fwd_mode_name  = "touchfwd",
+	.port_fwd_begin = NULL,
+	.port_fwd_end   = NULL,
+	.packet_fwd     = pkt_burst_touch,
+};