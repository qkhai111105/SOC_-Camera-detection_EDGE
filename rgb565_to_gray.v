module rgb565_to_gray (
    clk,
    rst,
    valid_in,
    rgb565_in,
    valid_out,
    gray8_out,
    gray565_out
);

    input clk;
    input rst;
    input valid_in;
    input [15:0] rgb565_in;

    output valid_out;
    output [7:0] gray8_out;
    output [15:0] gray565_out;

    reg valid_out;
    reg [7:0] gray8_out;
    reg [15:0] gray565_out;

    wire [4:0] r5;
    wire [5:0] g6;
    wire [4:0] b5;

    wire [7:0] r8;
    wire [7:0] g8;
    wire [7:0] b8;

    wire [7:0] gray_fast;

    assign r5 = rgb565_in[15:11];
    assign g6 = rgb565_in[10:5];
    assign b5 = rgb565_in[4:0];

    assign r8 = {r5, r5[4:2]};
    assign g8 = {g6, g6[5:4]};
    assign b8 = {b5, b5[4:2]};

    assign gray_fast = (r8 >> 2) + (g8 >> 1) + (b8 >> 2);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 1'b0;
            gray8_out <= 8'd0;
            gray565_out <= 16'h0000;
        end else begin
            valid_out <= valid_in;

            if (valid_in) begin
                gray8_out <= gray_fast;
                gray565_out <= {gray_fast[7:3], gray_fast[7:2], gray_fast[7:3]};
            end
        end
    end

endmodule