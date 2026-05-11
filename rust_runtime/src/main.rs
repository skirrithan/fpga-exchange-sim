use prost::Message;
use std::fs;

pub mod fpga_exchange {
    include!(concat!(env!("OUT_DIR"), "/fpga_exchange.rs"));
}

use fpga_exchange::{DmaDescriptor, DmaTrace, PacketTrace};

fn main() {
    let input_bytes = fs::read("../binary_traces/packets.pb")
        .expect("missing ../binary_traces/packets.pb");

    let packet_trace = PacketTrace::decode(&*input_bytes)
        .expect("failed to decode PacketTrace");

    let mut dma_trace = DmaTrace {
        descriptors: Vec::new(),
    };

    for pkt in packet_trace.packets {
        let desc = DmaDescriptor {
            desc_id: pkt.packet_id,
            sub_cycle: pkt.created_cycle + 1,
            packet: Some(pkt),
        };

        dma_trace.descriptors.push(desc);
    }

    let mut output_bytes = Vec::new();
    dma_trace.encode(&mut output_bytes)
        .expect("failed to encode DmaTrace");

    fs::write("../binary_traces/sim_input.pb", output_bytes)
        .expect("failed to write sim_input.pb");

    println!("Rust runtime emitted binary_traces/sim_input.pb");
}