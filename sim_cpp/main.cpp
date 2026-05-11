#include "Vstage_transform.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include "cpp_pb/packet.pb.h"

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <unordered_map>

struct PacketMeta {
    uint64_t created_cycle;
    uint64_t submitted_cycle;
};

static uint64_t sim_time = 0;

static void tick(Vstage_transform* top, VerilatedVcdC* tfp) {
    top->clk = 0;
    top->eval();
    tfp->dump(sim_time++);

    top->clk = 1;
    top->eval();
    tfp->dump(sim_time++);
}

static void log_handshake(const char* phase, uint64_t cycle, const Vstage_transform* top) {
    std::cout << "cycle=" << cycle
              << " " << phase
              << " in_valid=" << static_cast<uint32_t>(top->in_valid)
              << " in_ready=" << static_cast<uint32_t>(top->in_ready)
              << " out_valid=" << static_cast<uint32_t>(top->out_valid)
              << " out_ready=" << static_cast<uint32_t>(top->out_ready)
              << "\n";
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    std::system("mkdir -p results");
    std::system("mkdir -p build/waves");

    std::ifstream input("binary_traces/sim_input.pb", std::ios::binary);
    if (!input.is_open()) {
        std::cerr << "ERROR: could not open binary_traces/sim_input.pb\n";
        return 1;
    }

    fpga_exchange::DmaTrace dma_trace;
    if (!dma_trace.ParseFromIstream(&input)) {
        std::cerr << "ERROR: failed to parse DmaTrace protobuf\n";
        return 1;
    }

    std::cout << "Loaded " << dma_trace.descriptors_size()
              << " DMA descriptors\n";

    std::ofstream output("results/output.csv");
    output << "packet_id,created_cycle,submitted_cycle,output_cycle,action,flags,latency_from_created,latency_from_submitted\n";

    std::unordered_map<uint32_t, PacketMeta> packet_meta;

    for (const auto& desc : dma_trace.descriptors()) {
        if (!desc.has_packet()) {
            std::cerr << "WARNING: descriptor " << desc.desc_id()
                      << " has no packet\n";
            continue;
        }

        const auto& pkt = desc.packet();

        packet_meta[pkt.packet_id()] = PacketMeta{
            pkt.created_cycle(),
            desc.sub_cycle()
        };
    }

    Vstage_transform* top = new Vstage_transform;

    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("sim_cpp/build/waves/stage_transform.vcd");

    top->rst = 1;
    top->in_valid = 0;
    top->out_ready = 1;

    tick(top, tfp);
    tick(top, tfp);

    top->rst = 0;

    int next_desc = 0;
    const uint64_t max_cycles = 200;

    for (uint64_t cycle = 0; cycle < max_cycles; cycle++) {
        bool submitted_this_cycle = false;
        uint32_t submitted_packet_id = 0;

        top->in_valid = 0;

        // Artificial downstream stalls to demonstrate backpressure.
        top->out_ready = (cycle % 5 != 0); //every 5th cycle, downstream is not ready

        // Refresh combinational outputs (including in_ready) after changing inputs.
        top->eval();

        if (next_desc < dma_trace.descriptors_size()) {
            const auto& desc = dma_trace.descriptors(next_desc);

            if (!desc.has_packet()) {
                next_desc++;
            } else {
                const auto& pkt = desc.packet();

                bool descriptor_ready = desc.sub_cycle() <= cycle;

                if (descriptor_ready && top->in_ready) {
                    log_handshake("before_submit", cycle, top);

                    top->in_valid = 1;

                    top->in_packet_id = pkt.packet_id();
                    top->in_msg_type  = pkt.msg_type();
                    top->in_symbol_id = pkt.symbol_id();
                    top->in_seq       = pkt.seq();
                    top->in_side      = pkt.side();
                    top->in_price     = pkt.price();
                    top->in_qty       = pkt.qty();

                    submitted_this_cycle = true;
                    submitted_packet_id = pkt.packet_id();

                    std::cout << "cycle=" << cycle
                              << " submitted packet=" << pkt.packet_id()
                              << " msg_type=" << pkt.msg_type()
                              << " symbol=" << pkt.symbol_id()
                              << " seq=" << pkt.seq()
                              << " price=" << pkt.price()
                              << " qty=" << pkt.qty()
                              << "\n";

                    next_desc++;
                }
            }
        }

        tick(top, tfp);

        if (submitted_this_cycle) {
            log_handshake("after_submit", cycle, top);
            std::cout << "cycle=" << cycle
                      << " after_submit packet=" << submitted_packet_id
                      << "\n";
        }

        if (top->out_valid && top->out_ready) {
            uint32_t packet_id = top->out_packet_id;
            uint32_t action = top->out_action;
            uint32_t flags = top->out_flags;

            auto it = packet_meta.find(packet_id);

            uint64_t created_cycle = 0;
            uint64_t submitted_cycle = 0;

            if (it != packet_meta.end()) {
                created_cycle = it->second.created_cycle;
                submitted_cycle = it->second.submitted_cycle;
            }

            uint64_t latency_from_created = cycle - created_cycle;
            uint64_t latency_from_submitted = cycle - submitted_cycle;

            output << packet_id << ","
                   << created_cycle << ","
                   << submitted_cycle << ","
                   << cycle << ","
                   << action << ","
                   << flags << ","
                   << latency_from_created << ","
                   << latency_from_submitted << "\n";

            std::cout << "cycle=" << cycle
                      << " output packet=" << packet_id
                      << " action=" << action
                      << " flags=" << flags
                      << " latency_from_created=" << latency_from_created
                      << " latency_from_submitted=" << latency_from_submitted
                      << "\n";
        }
    }

    output.close();

    tfp->close();
    delete tfp;
    delete top;

    google::protobuf::ShutdownProtobufLibrary();

    std::cout << "Wrote results/output.csv\n";
    std::cout << "Wrote sim_cpp/build/waves/stage_transform.vcd\n";

    return 0;
}