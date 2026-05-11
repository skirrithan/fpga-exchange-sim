from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
PB_SCRIPTS_DIR = ROOT / "pb_scripts"
if str(PB_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(PB_SCRIPTS_DIR))

import packet_pb2

TRACES_DIR = ROOT / "binary_traces"
TRACES_DIR.mkdir(exist_ok=True)

trace = packet_pb2.PacketTrace()

packets = [ #id, cycle, msg_type, symb_id, seq, side, price, qty
    (0, 0, packet_pb2.Market_Data, 101, 1, packet_pb2.Buy, 1000, 10),
    (1, 1, packet_pb2.Market_Data, 101, 2, packet_pb2.Sell, 1001, 20),
    (2, 2, packet_pb2.Market_Data, 202, 3, packet_pb2.Buy, 999, 5),
    (3, 3, packet_pb2.Market_Data, 101, 5, packet_pb2.Sell, 1002, 10),
    (4, 4, packet_pb2.Order, 101, 6, packet_pb2.Buy, 1005, 50),
    (5, 5, packet_pb2.Order, 101, 7, packet_pb2.Buy, 1005, 500),
]

for p in packets:
    pkt = trace.packets.add()
    pkt.packet_id = p[0]
    pkt.created_cycle = p[1]
    pkt.msg_type = p[2]
    pkt.symbol_id = p[3]
    pkt.seq = p[4]
    pkt.side = p[5]
    pkt.price = p[6]
    pkt.qty = p[7]

output_file = TRACES_DIR / "packets.pb"
with output_file.open("wb") as f:
    f.write(trace.SerializeToString())

print(f"Generated {output_file}")