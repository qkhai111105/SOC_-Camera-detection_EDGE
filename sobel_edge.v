module sobel_edge (
    clk,
    rst,
    gray_valid_in,
    gray8_in,
    edge_valid_out,
    edge_pixel_out
);

    parameter IMG_WIDTH  = 320;
    parameter IMG_HEIGHT = 240;
    parameter THRESHOLD  = 100;

    input clk;
    input rst;

    input gray_valid_in;
    input [7:0] gray8_in;

    output edge_valid_out;
    output [15:0] edge_pixel_out;

    reg edge_valid_out;
    reg [15:0] edge_pixel_out;

    // =========================================================
    // Line buffers
    // =========================================================

    reg [7:0] line_buffer_1 [0:IMG_WIDTH-1];
    reg [7:0] line_buffer_2 [0:IMG_WIDTH-1];

    reg [15:0] x;
    reg [15:0] y;

    integer i;

    // =========================================================
    // Stage 1: lấy top/mid/bot pixel
    // =========================================================

    reg valid_s1;
    reg [15:0] x_s1;
    reg [15:0] y_s1;

    reg [7:0] top_s1;
    reg [7:0] mid_s1;
    reg [7:0] bot_s1;

    // =========================================================
    // Window shift registers
    // =========================================================

    reg [7:0] p00;
    reg [7:0] p01;
    reg [7:0] p02;

    reg [7:0] p10;
    reg [7:0] p11;
    reg [7:0] p12;

    reg [7:0] p20;
    reg [7:0] p21;
    reg [7:0] p22;

    // =========================================================
    // Stage 2: register window 3x3
    // =========================================================

    reg valid_s2;
    reg [15:0] x_s2;
    reg [15:0] y_s2;

    reg [7:0] w00_s2;
    reg [7:0] w01_s2;
    reg [7:0] w02_s2;

    reg [7:0] w10_s2;
    reg [7:0] w11_s2;
    reg [7:0] w12_s2;

    reg [7:0] w20_s2;
    reg [7:0] w21_s2;
    reg [7:0] w22_s2;

    // =========================================================
    // Stage 3: Gx, Gy
    // =========================================================

    reg valid_s3;
    reg [15:0] x_s3;
    reg [15:0] y_s3;

    reg signed [15:0] gx_s3;
    reg signed [15:0] gy_s3;

    // =========================================================
    // Stage 4: abs
    // =========================================================

    reg valid_s4;
    reg [15:0] x_s4;
    reg [15:0] y_s4;

    reg [15:0] abs_gx_s4;
    reg [15:0] abs_gy_s4;

    // =========================================================
    // Stage 5: edge magnitude
    // =========================================================

    reg valid_s5;
    reg [15:0] x_s5;
    reg [15:0] y_s5;

    reg [16:0] edge_mag_s5;

    // =========================================================
    // Main pipeline
    // =========================================================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x <= 16'd0;
            y <= 16'd0;

            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_s3 <= 1'b0;
            valid_s4 <= 1'b0;
            valid_s5 <= 1'b0;

            edge_valid_out <= 1'b0;
            edge_pixel_out <= 16'h0000;

            x_s1 <= 16'd0;
            y_s1 <= 16'd0;
            x_s2 <= 16'd0;
            y_s2 <= 16'd0;
            x_s3 <= 16'd0;
            y_s3 <= 16'd0;
            x_s4 <= 16'd0;
            y_s4 <= 16'd0;
            x_s5 <= 16'd0;
            y_s5 <= 16'd0;

            top_s1 <= 8'd0;
            mid_s1 <= 8'd0;
            bot_s1 <= 8'd0;

            p00 <= 8'd0;
            p01 <= 8'd0;
            p02 <= 8'd0;

            p10 <= 8'd0;
            p11 <= 8'd0;
            p12 <= 8'd0;

            p20 <= 8'd0;
            p21 <= 8'd0;
            p22 <= 8'd0;

            w00_s2 <= 8'd0;
            w01_s2 <= 8'd0;
            w02_s2 <= 8'd0;

            w10_s2 <= 8'd0;
            w11_s2 <= 8'd0;
            w12_s2 <= 8'd0;

            w20_s2 <= 8'd0;
            w21_s2 <= 8'd0;
            w22_s2 <= 8'd0;

            gx_s3 <= 16'sd0;
            gy_s3 <= 16'sd0;

            abs_gx_s4 <= 16'd0;
            abs_gy_s4 <= 16'd0;
            edge_mag_s5 <= 17'd0;

            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
                line_buffer_1[i] <= 8'd0;
                line_buffer_2[i] <= 8'd0;
            end

        end else begin

            // valid pipeline
            valid_s1 <= gray_valid_in;
            valid_s2 <= valid_s1;
            valid_s3 <= valid_s2;
            valid_s4 <= valid_s3;
            valid_s5 <= valid_s4;

            edge_valid_out <= valid_s5;

            // =================================================
            // Stage 1: lấy 3 pixel theo cột hiện tại
            // =================================================

            if (gray_valid_in) begin
                top_s1 <= line_buffer_2[x];
                mid_s1 <= line_buffer_1[x];
                bot_s1 <= gray8_in;

                x_s1 <= x;
                y_s1 <= y;

                line_buffer_2[x] <= line_buffer_1[x];
                line_buffer_1[x] <= gray8_in;

                if (x == IMG_WIDTH - 1) begin
                    x <= 16'd0;

                    if (y == IMG_HEIGHT - 1)
                        y <= 16'd0;
                    else
                        y <= y + 16'd1;
                end else begin
                    x <= x + 16'd1;
                end
            end

            // =================================================
            // Stage 2: tạo cửa sổ 3x3
            // =================================================

            if (valid_s1) begin
                x_s2 <= x_s1;
                y_s2 <= y_s1;

                w00_s2 <= p01;
                w01_s2 <= p02;
                w02_s2 <= top_s1;

                w10_s2 <= p11;
                w11_s2 <= p12;
                w12_s2 <= mid_s1;

                w20_s2 <= p21;
                w21_s2 <= p22;
                w22_s2 <= bot_s1;

                p00 <= p01;
                p01 <= p02;
                p02 <= top_s1;

                p10 <= p11;
                p11 <= p12;
                p12 <= mid_s1;

                p20 <= p21;
                p21 <= p22;
                p22 <= bot_s1;
            end

            // =================================================
            // Stage 3: tính Gx, Gy
            // =================================================

            if (valid_s2) begin
                x_s3 <= x_s2;
                y_s3 <= y_s2;

                gx_s3 <=
                    (0 - w00_s2) + w02_s2
                    - (w10_s2 * 2) + (w12_s2 * 2)
                    - w20_s2 + w22_s2;

                gy_s3 <=
                    w00_s2 + (w01_s2 * 2) + w02_s2
                    - w20_s2 - (w21_s2 * 2) - w22_s2;
            end

            // =================================================
            // Stage 4: trị tuyệt đối
            // =================================================

            if (valid_s3) begin
                x_s4 <= x_s3;
                y_s4 <= y_s3;

                if (gx_s3 < 0)
                    abs_gx_s4 <= 0 - gx_s3;
                else
                    abs_gx_s4 <= gx_s3;

                if (gy_s3 < 0)
                    abs_gy_s4 <= 0 - gy_s3;
                else
                    abs_gy_s4 <= gy_s3;
            end

            // =================================================
            // Stage 5: edge magnitude
            // =================================================

            if (valid_s4) begin
                x_s5 <= x_s4;
                y_s5 <= y_s4;

                edge_mag_s5 <= abs_gx_s4 + abs_gy_s4;
            end

            // =================================================
            // Output
            // =================================================

            if (valid_s5) begin
                if ((x_s5 < 16'd2) ||
                    (y_s5 < 16'd2) ||
                    (x_s5 >= IMG_WIDTH - 1) ||
                    (y_s5 >= IMG_HEIGHT - 1)) begin

                    edge_pixel_out <= 16'h0000;

                end else begin

                    if (edge_mag_s5 > THRESHOLD)
                        edge_pixel_out <= 16'hFFFF;
                    else
                        edge_pixel_out <= 16'h0000;

                end
            end else begin
                edge_pixel_out <= 16'h0000;
            end
        end
    end

endmodule