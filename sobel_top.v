module sobel_top (
    clk,
    rst,

    pixel_valid_in,
    rgb565_in,

    gray_valid_out,
    gray565_out,

    edge_valid_out,
    edge565_out
);

    parameter IMG_WIDTH  = 320;
    parameter IMG_HEIGHT = 240;
    parameter THRESHOLD  = 100;

    input clk;
    input rst;

    input pixel_valid_in;
    input [15:0] rgb565_in;

    output gray_valid_out;
    output [15:0] gray565_out;

    output edge_valid_out;
    output [15:0] edge565_out;

    wire gray_valid;
    wire [7:0] gray8;
    wire [15:0] gray565;

    rgb565_to_gray u_gray (
        .clk(clk),
        .rst(rst),
        .valid_in(pixel_valid_in),
        .rgb565_in(rgb565_in),
        .valid_out(gray_valid),
        .gray8_out(gray8),
        .gray565_out(gray565)
    );

    sobel_edge #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .THRESHOLD(THRESHOLD)
    ) u_sobel (
        .clk(clk),
        .rst(rst),
        .gray_valid_in(gray_valid),
        .gray8_in(gray8),
        .edge_valid_out(edge_valid_out),
        .edge_pixel_out(edge565_out)
    );

    assign gray_valid_out = gray_valid;
    assign gray565_out = gray565;

endmodule