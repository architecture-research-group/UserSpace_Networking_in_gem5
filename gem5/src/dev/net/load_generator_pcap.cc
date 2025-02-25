#include "dev/net/load_generator_pcap.hh"

#include <inttypes.h>
#include <net/ethernet.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/udp.h>

#include <base/stats/types.hh>
#include "base/trace.hh"
#include "debug/LoadgenDebug.hh"
#include "debug/LoadgenLatency.hh"
#include "sim/sim_exit.hh"

static constexpr size_t kLatencyHistSize = 100;
static constexpr unsigned kEtherHeaderSize = 14;
static constexpr unsigned kCheckLossInterval = 100;
static constexpr size_t kLossCheckWaitCycles = 100000000;
static constexpr uint16_t CheckLossInterval = 1000;

namespace gem5 {
LoadGeneratorPcap::LoadGeneratorPcapStats::LoadGeneratorPcapStats(
    statistics::Group *parent)
    : statistics::Group(parent, "LoadGeneratorPcap"),
      ADD_STAT(sentPackets, statistics::units::Count::get(),
               "Number of Generated Packets"),
      ADD_STAT(recvPackets, statistics::units::Count::get(),
               "Number of Recieved Packets"),
      ADD_STAT(latency, statistics::units::Second::get(),
               "Distribution of Latency in ms") {
  sentPackets.precision(0);
  recvPackets.precision(0);
  latency.init(kLatencyHistSize);
}

LoadGeneratorPcap::LoadGeneratorPcap(const LoadGeneratorPcapParams &p)
    : SimObject(p),
      loadgenId(p.loadgen_id),
      startTick(p.start_tick),
      stopTick(p.stop_tick),
      maxPcktSize(p.max_packetsize),
      portFilter(p.port_filter),
      srcIP(p.replace_src_ip),
      destIP(p.replace_dest_ip),
      packetRate(p.packet_rate),
      incrementInterval(p.increment_interval),
      lastRxCount(0),
      lastTxCount(0),
      count_packets(0),
      pcapFilename(p.pcap_filename),
      sendPacketEvent([this] { sendPacket(); }, name()),
      checkLossEvent([this] { checkLoss(); }, name()),
      loadGeneratorPcapStats(this) {
  LoadGeneratorPcap::interface = new LoadGenPcapInt("interface", this);

  // Setup the packet send times.
  packetSendTimes = std::queue<Tick>();
  // Setup pcap trace file.
  char errbuff[PCAP_ERRBUF_SIZE];
  pcap_h = pcap_open_offline(pcapFilename.c_str(), errbuff);
  if (pcap_h == nullptr) {
    fatal("Failed to open %s pcap trace file, error: %s", pcapFilename.c_str(),
          errbuff);
  } else {
    inform("Pcap trace file is loaded: %s", pcapFilename.c_str());
  }

  // Stack mode.
  if (p.stack_mode == "KernelStack") {
    stackMode = StackMode::Kernel;
    DPRINTF(LoadgenDebug, "Running Pcap load generator in Kernel stack mode\n");
  } else if (p.stack_mode == "DPDKStack") {
    stackMode = StackMode::DPDK;
    DPRINTF(LoadgenDebug, "Running Pcap load generator in DPDK stack mode\n");
  } else
    fatal("Unknown stack mode");

  // Other params.
  if (p.replay_mode == "SimpleReplay") {
    replayMode = ReplayMode::SimpleReplay;
    DPRINTF(LoadgenDebug, "Running Pcap load generator in SimpleReplay mode\n");
  } else if (p.replay_mode == "ReplayAndAdjustThroughput") {
    replayMode = ReplayMode::ReplayAndAdjustThroughput;
    DPRINTF(LoadgenDebug,
            "Running Pcap load generator in ReplayAndAdjustThroughput mode, "
            "base packet rate: %d pps, interval: %d\n",
            packetRate, incrementInterval);
  } else if (p.replay_mode == "ConstThroughput") {
    replayMode = ReplayMode::ConstThroughput;
    DPRINTF(LoadgenDebug,
            "Running Pcap load generator in ConstThroughput mode, target "
            "packet rate: %d pps\n",
            packetRate);
  } else
    fatal("Unknown replay mode");
}

LoadGeneratorPcap::~LoadGeneratorPcap() {
  if (pcap_h != nullptr) 
    pcap_close(pcap_h);
}
Tick LoadGeneratorPcap::frequency()
    {
        return (1e12/packetRate);
    }
void LoadGeneratorPcap::startup() {
  if (curTick() > stopTick) 
    return;

  if (curTick() > startTick) {
    DPRINTF(LoadgenDebug, "Starting LoadGenPcap, 1\n");
    schedule(sendPacketEvent, curTick() + 1);
  } else {
    DPRINTF(LoadgenDebug, "Starting LoadGenPcap, 2\n");
    schedule(sendPacketEvent, startTick + 1);
  }
}

Port &LoadGeneratorPcap::getPort(const std::string &if_name, PortID idx) {
  return *interface;
}

void LoadGeneratorPcap::buildEthernetHeader(EthPacketPtr ethpacket) const {
  // Build Packet header
  // DSTMAC 6 | SRCMAC 6 | TYPE | DATA
  uint8_t dst_mac[6] = {
      0x00, 0x90,
      0x00, 0x00,
      0x00, static_cast<uint8_t>(0x01 + loadgenId)};  // Use paired NIC's MAC
  // uint8_t dst_mac[6] = {
      // 0x08, 0xc0,
      // 0xeb, 0xbf,
      // 0xee, static_cast<uint8_t>(0xb6 + loadgenId)};  // Use paired NIC's MAC
  uint8_t src_mac[6] = {0x00, 0x80, 0x00,
                        0x00, 0x00, static_cast<uint8_t>(0x01 + loadgenId)};
// 08:c0:eb:bf:ee:aa
  uint16_t size = ethpacket->length;

  if (1 != htons(1)) 
    size = htons(size);

  uint8_t head[kEtherHeaderSize];
  memcpy(head, dst_mac, 6);
  memcpy(head + 6, src_mac, 6);

  // This is Ethernet II frame, so the protocol type is next.
  const uint16_t id = htons(ETHERTYPE_IP);
  memcpy(head + 12, &id, 2);

  memcpy(ethpacket->data, head, kEtherHeaderSize);
}

void LoadGeneratorPcap::sendPacket() {
  DPRINTF(LoadgenDebug, "LoadGenPcap::sendPacket executed\n");
  // Read a packet from pcap file.
  pcap_pkthdr *pcap_header;
  const u_char *pcap_data;
  if (pcap_h != nullptr) {
    int ret = pcap_next_ex(pcap_h, &pcap_header, &pcap_data);
    if (ret < 0) { // || count_packets >= 500) {
      // Perhaps EOF.
      DPRINTF(LoadgenDebug, "End of pcap trace is reached!\n");
      DPRINTF(LoadgenDebug, "Nothing will be scheduled in the loadgen, exiting here.\n");
      DPRINTF(LoadgenDebug, "Bye!\n");
      exitSimLoop("END OF PCAP TRACE" "\nSIM TERMINATED BY LOADGEN"); 
      // schedule(checkLossEvent, curTick() + kLossCheckWaitCycles);
      return;
      // TODO: can start over...
    }
  } else {
    warn("No pcap file loaded, nothing will be scheduled next!");
    return;
  }

  // Check we have the full packet here.
  if (pcap_header->len != pcap_header->caplen) {
    DPRINTF(LoadgenDebug, "Broken pcap trace detected, skip it...\n");
    schedule(sendPacketEvent, curTick() + 1);
    return;
  }

  // Skip large packets.
  if (pcap_header->len > maxPcktSize) {
    DPRINTF(LoadgenDebug, "Large packet detected, skip it...\n");
    schedule(sendPacketEvent, curTick() + 1);
    return;
  }

  // Create packet depending on the stack type.
  EthPacketPtr txPacket = std::make_shared<EthPacketData>(pcap_header->len);
  txPacket->length = pcap_header->len;
  if (stackMode == StackMode::Kernel) {
    // Check it is an IPv4 packet.
    const ether_header *eth_hdr =
        reinterpret_cast<const ether_header *>(pcap_data);
    uint16_t ether_type = ntohs(eth_hdr->ether_type);
    if (ether_type != ETHERTYPE_IP) {
      DPRINTF(LoadgenDebug, "Not an IP packet in trace detected, skip it...\n");
      schedule(sendPacketEvent, curTick() + 1);
      return;
    }

    pcap_data += sizeof(ether_header);
    const ip *iph = reinterpret_cast<const ip *>(pcap_data);
    if (iph->ip_v != 0x04) {
      DPRINTF(LoadgenDebug,
              "Not an IPv4 packet in trace detected, skip it...\n");
      schedule(sendPacketEvent, curTick() + 1);
      return;
    }

    // Check if it is a UDP packet.
    if (iph->ip_p != IPPROTO_UDP) {
      DPRINTF(LoadgenDebug,
              "Not an UDP packet in trace detected, skip it...\n");
      schedule(sendPacketEvent, curTick() + 1);
      return;
    }

    // If needed - filter by dest port.
    pcap_data += (iph->ip_hl << 2);
    const udphdr *udp = reinterpret_cast<const udphdr *>(pcap_data);
    if (ntohs(udp->uh_dport) != portFilter) {
      DPRINTF(LoadgenDebug, "Packet was filter-out by port...\n");
      schedule(sendPacketEvent, curTick() + 1);
      return;
    }

    // Replace the source and destination IP address by the one in configuration
    // (to match with the OS ifconfig).
    // TODO: disabling for now as this does not work, perhaps the checksum needs
    // to be hacked as well.
    // ip *iph_mutable = const_cast<ip *>(iph);
    // inet_aton(destIP.c_str(), &iph_mutable->ip_dst);
    // inet_aton(srcIP.c_str(), &iph_mutable->ip_src);

    // Merge with our own Ethernet header.
    assert(pcap_header->len == ntohs(iph->ip_len) + kEtherHeaderSize);
    // DPRINTF(LoadgenDebug, "Pcap header len size is %d\n", pcap_header->len);
    buildEthernetHeader(txPacket);
    // Copy our payload.
    memcpy(txPacket->data + kEtherHeaderSize, iph, ntohs(iph->ip_len));
  } else {
    // For DPDK stack, just change the Ethernet header and copy the rest.
    // DPRINTF(LoadgenDebug, "Pcap header len size is %d\n", pcap_header->len);
    // count_packets++;
    buildEthernetHeader(txPacket);
    pcap_data += sizeof(ether_header);
    memcpy(txPacket->data + kEtherHeaderSize, pcap_data,
           pcap_header->len - kEtherHeaderSize);
  }

  // Send packet.
  interface->sendPacket(txPacket);
  DPRINTF(LoadgenDebug, "Packet was sent!\n");

  Tick currentTick = curTick();
  packetSendTimes.push(currentTick);
  // Increment stats.
  loadGeneratorPcapStats.sentPackets++;
  lastTxCount++;

  if (curTick() < stopTick) {
    if (replayMode == ReplayMode::ConstThroughput) {
      schedule(sendPacketEvent, curTick() + frequency());
    } else if (replayMode == ReplayMode::ReplayAndAdjustThroughput) {
      if (lastTxCount == kCheckLossInterval) {
        schedule(checkLossEvent, curTick() + kLossCheckWaitCycles);
      } else {
        schedule(sendPacketEvent, curTick() + frequency());
      }
    } else {
      warn("Weird replay mode detected, nothing will be scheduled next!");
      return;
    }
  }

  // Tick currentTick = curTick();
  // packetSendTimes.push(currentTick);
  // // Increment stats.
  // loadGeneratorPcapStats.sentPackets++;
  // lastTxCount++;
  return;
}

void LoadGeneratorPcap::checkLoss() {
  if (lastTxCount - lastRxCount < 5) {
    // No loss - incrrement packet rate.
    packetRate = packetRate + incrementInterval;
    schedule(sendPacketEvent, curTick() + frequency());
    DPRINTF(LoadgenDebug, "Rate Incremented, now sending packets at %u \n",
            packetRate);
    DPRINTF(LoadgenDebug, "Rx %lu, Tx %lu \n", lastRxCount, lastTxCount);
  } else {
    // Loss deteceted - dectement rate.
    if ((packetRate - incrementInterval) < packetRate)
      packetRate = packetRate - incrementInterval;
    

    // add extra delay to prevent previouse loss from affecting results
    schedule(sendPacketEvent, curTick() + frequency() + kLossCheckWaitCycles);
    DPRINTF(LoadgenDebug, "Loss Detected, now sending packets at %u \n ",
            packetRate);
    DPRINTF(LoadgenDebug, "Rx %lu, Tx %lu \n", lastRxCount, lastTxCount);
    // exitSimLoop("LOSS DETECTED" "SIM TERMINATED BY LOADGEN");
    if (packetRate==0)
      exitSimLoop("PACKET RATE DROPPED TO ZERO" "SIM TERMINATED BY LOADGEN");
  }

  lastTxCount = 0;
  lastRxCount = 0;
}

void LoadGeneratorPcap::endTest() const {
  exitSimLoop("m5_exit by loadgen End Simulator.", 0, curTick(), 0, true);
}

bool LoadGeneratorPcap::processRxPkt(EthPacketPtr pkt) {
  loadGeneratorPcapStats.recvPackets++;
  lastRxCount++;

  // assuming FIFO ordering of responses which is not necessierly true
  uint64_t sendTick = packetSendTimes.front();
  if (packetSendTimes.size() > 0)
    packetSendTimes.pop();
  // uint64_t sendTick;
  // memcpy(&sendTick, &(pkt->data[8]), sizeof(uint64_t));
  float delta = float((gem5::curTick() - sendTick)) / 10.0e8;
  loadGeneratorPcapStats.latency.sample(delta);
  DPRINTF(LoadgenLatency, "Latency %f \n", delta);
  return true;
}
}  // namespace gem5
