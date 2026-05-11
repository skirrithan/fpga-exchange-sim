module stage_transform (
    input logic clk, // Clock signal
    input logic rst_n, // reset signal

    input logic in_valid, // data valid signal
    output logic in_ready, // data ready signal
    input logic [31:0] in_payload, // input data payload
    input logic [31:0] in_packet_id, // input packet ID, mirrors uint32 defined packet id

    output logic out_valid,
    input logic out_ready, // downstream ready signal
    output logic [31:0] out_payload,
    output logic [31:0] out_packet_id
);

    logic full;
    logic [31:0] payload_reg;
    logic [31:0] packet_id_reg;

    assign in_ready = !full || (out_valid && out_ready); // in ready when not full / downstream ready
    assign out_valid = full; 
    assign out_payload = payload_reg;
    assign out_packet_id = packet_id_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            full <= 1'b0
            payload_reg <= 32'b0;
            packet_id_reg <= 32'b0;
        end else begin
            if (in_valid && in_ready) begin
                payload_reg <= in_payload + 32'd1;
                packet_id_reg <= in_packet_id;
                full <= 1'b1;
            end else if (out_valid && out_ready) begin
                full <= 1'b0;
            end
        end 
    end
    
endmodule