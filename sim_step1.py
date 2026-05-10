from dataclasses import dataclass #structured objects 
from collections import deque #fifo behaviour

@dataclass
class Packet:
    packet_id: int #id of packet
    created_cycle: int #cycle it was created
    payload: int #packet payload

class PipelineStage:
    def __init__(self, latency_cycles: int = 1): #constructor , accepts cycle value default 1
        self.latency_cycles = latency_cycles #latency attribute assigned latency value
        self.inflight = deque() #inflight attribute , empty deque created

    def tick(self, cycle: int, input_queue: deque, output_queue: deque): #tick method within the class
        # First: complete packets whose latency has elapsed
        if self.inflight and self.inflight[0][0] <= cycle: #check if any packets are still in queue , corresponding to cycle value
            _, packet = self.inflight.popleft() 
            packet.payload += 1 #increment payload of packet by 1
            output_queue.append((cycle, packet))

        # Second: accept one new packet if available
        if input_queue:
            packet = input_queue.popleft()
            ready_cycle = cycle + self.latency_cycles
            self.inflight.append((ready_cycle, packet))
    
def main():
    input_queue = deque() #input queue created
    output_queue = deque() #output queue created
    stage = PipelineStage(latency_cycles=1) #pipeline object created 

    total_packets = 5
    max_cycles = 10

    for cycle in range(max_cycles):
        print(f"Cycle {cycle}:")

        #create one packet per cycle 
        if cycle < total_packets:
            packet = Packet(packet_id=cycle, created_cycle=cycle, payload=0 + cycle) 
            input_queue.append(packet)
            print(f"  Created packet {packet.packet_id} with payload {packet.payload}, input_queue: {input_queue}")
        
        stage.tick(cycle, input_queue, output_queue) #advance one cycle 

        #read completed packets from output queue
        while output_queue:
            output_cycle, packet = output_queue.popleft()
            latency = output_cycle - packet.created_cycle
            print(f"  Completed packet {packet.packet_id} with payload {packet.payload}, latency: {latency} cycles")

if __name__ == "__main__":
    main()