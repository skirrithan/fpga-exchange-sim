module stage_transform (
    input  logic        clk,          
    input  logic        rst,          

    // Input stream from C++ harness.
    input  logic        in_valid,     
    output logic        in_ready,     

    input  logic [31:0] in_packet_id, 
    input  logic [31:0] in_msg_type,  // Packet kind: market data or order.
    input  logic [31:0] in_symbol_id, 
    input  logic [31:0] in_seq,       // Sequence number used to detect gaps.
    input  logic [31:0] in_side,    
    input  logic [31:0] in_price,    
    input  logic [31:0] in_qty,       

    // Output stream back to C++ harness.
    output logic        out_valid,
    input  logic        out_ready,

    output logic [31:0] out_packet_id, // Packet id for the produced result.
    output logic [31:0] out_action,    // Decision made by this stage.
    output logic [31:0] out_flags      // Extra information about that decision.
);

    // Message type values copied from packet.proto.
    // Using localparams keeps the RTL readable instead of comparing raw numbers.
    localparam logic [31:0] MSG_MARKET_DATA = 32'd0;
    localparam logic [31:0] MSG_ORDER       = 32'd1;

    // Action codes sent to the next stage or test harness.
    localparam logic [31:0] ACTION_DROP   = 32'd0;
    localparam logic [31:0] ACTION_ACCEPT = 32'd1;
    localparam logic [31:0] ACTION_REJECT = 32'd2;

    // Flags explain why a packet was dropped, accepted with warning, or rejected.
    localparam logic [31:0] FLAG_NONE      = 32'h0;
    localparam logic [31:0] FLAG_SEQ_GAP   = 32'h1;
    localparam logic [31:0] FLAG_RISK_FAIL = 32'h2;
    localparam logic [31:0] FLAG_SYMBOL    = 32'h4;

    // Simple policy constants for this example stage.
    // The logic is intentionally small so the handshake behavior is easy to see.
    localparam logic [31:0] TARGET_SYMBOL = 32'd101;
    localparam logic [31:0] MAX_QTY       = 32'd100;
    localparam logic [31:0] MAX_PRICE     = 32'd2000;

    logic        full;          // 1 when this one-entry stage is holding an output result.
    logic [31:0] expected_seq;  // Next market-data sequence number we expect to see.

    // Registers that store the output until downstream accepts it.
    logic [31:0] packet_id_reg;
    logic [31:0] action_reg;
    logic [31:0] flags_reg;

    // Backpressure rule:
    // - If the stage is empty, it can always accept new input.
    // - If the stage is full, it normally blocks the sender.
    // - If the stage is full but downstream is taking the current output now,
    //   the stage can accept a replacement input in the same cycle.
    // This is why in_ready depends on both full and the output handshake.
    assign in_ready = !full || (out_valid && out_ready);

    // When full=1, the stage owns a valid result and drives it on the output bus.
    assign out_valid     = full;
    assign out_packet_id = packet_id_reg;
    assign out_action    = action_reg;
    assign out_flags     = flags_reg;

    // This is a single-stage pipeline register.
    // It was built this way because it is the smallest useful model of:
    // 1) packet classification,
    // 2) stateful checks like sequence tracking, and
    // 3) backpressure through a standard ready/valid handshake.
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset empties the stage and resets sequence tracking.
            full          <= 1'b0;
            expected_seq  <= 32'd1;

            // Reset output registers to harmless defaults.
            packet_id_reg <= 32'd0;
            action_reg    <= ACTION_DROP;
            flags_reg     <= FLAG_NONE;
        end else begin
            // An input transfer happens only when both sides agree:
            // in_valid=1 from upstream and in_ready=1 from this stage.
            if (in_valid && in_ready) begin
                // Always keep the packet id so the output can be traced back.
                packet_id_reg <= in_packet_id;

                // Start from default outputs, then override them in the branches below.
                action_reg    <= ACTION_DROP;
                flags_reg     <= FLAG_NONE;

                // Market data is filtered by symbol and checked for sequence gaps.
                if (in_msg_type == MSG_MARKET_DATA) begin
                    if (in_symbol_id != TARGET_SYMBOL) begin
                        action_reg <= ACTION_DROP;
                        flags_reg  <= FLAG_SYMBOL;
                    end else begin
                        // Matching market data is accepted.
                        action_reg <= ACTION_ACCEPT;

                        // Sequence tracking detects missing or out-of-order updates.
                        if (in_seq != expected_seq) begin
                            // Report a gap and resynchronize to the next number after this one.
                            flags_reg    <= FLAG_SEQ_GAP;
                            expected_seq <= in_seq + 32'd1;
                        end else begin
                            // No gap: clear flags and advance expected_seq normally.
                            flags_reg    <= FLAG_NONE;
                            expected_seq <= expected_seq + 32'd1;
                        end
                    end
                // Orders are checked against simple risk limits.
                end else if (in_msg_type == MSG_ORDER) begin
                    // Reject obviously risky orders.
                    if ((in_qty > MAX_QTY) || (in_price > MAX_PRICE)) begin
                        action_reg <= ACTION_REJECT;
                        flags_reg  <= FLAG_RISK_FAIL;
                    end else begin
                        // Safe orders are accepted.
                        action_reg <= ACTION_ACCEPT;
                        flags_reg  <= FLAG_NONE;
                    end
                end else begin
                    // Unknown message types are dropped.
                    action_reg <= ACTION_DROP;
                    flags_reg  <= FLAG_NONE;
                end

                // Mark the stage as occupied so out_valid goes high.
                full <= 1'b1;

            // If no replacement packet arrives, but downstream consumes the current
            // result, clear the stage so it becomes empty on the next cycle.
            end else if (out_valid && out_ready) begin
                full <= 1'b0;
            end
        end
    end

endmodule