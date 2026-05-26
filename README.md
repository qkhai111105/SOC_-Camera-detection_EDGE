# Sobel Edge Detection Pipeline - Hướng Dẫn Chi Tiết

## 📋 Mục Lục
1. [Giới Thiệu Chung](#giới-thiệu-chung)
2. [Kiến Trúc Hệ Thống](#kiến-trúc-hệ-thống)
3. [Thuật Toán Sobel](#thuật-toán-sobel)
4. [Pipeline Chi Tiết](#pipeline-chi-tiết)
5. [Input/Output](#inputoutput)
6. [Cách Sử Dụng](#cách-sử-dụng)
7. [Các Tham Số Cấu Hình](#các-tham-số-cấu-hình)
8. [Ví Dụ Thực Tế](#ví-dụ-thực-tế)

---

## 🎯 Giới Thiệu Chung

Đây là một hệ thống **phát hiện cạnh (Edge Detection) sử dụng Sobel Operator** được thiết kế cho FPGA. Hệ thống nhận vào dữ liệu ảnh RGB565, chuyển đổi sang grayscale, sau đó phát hiện các cạnh trong ảnh.

**Các đặc điểm chính:**
- 📸 Hỗ trợ ảnh RGB565 16-bit
- ⚡ Thiết kế pipeline 5 giai đoạn cho throughput cao
- 🔄 Xử lý streaming (pixel nhập/xuất tuần tự)
- ⚙️ Tham số hóa kích thước ảnh và threshold
- 🎓 Phù hợp với thiết kế image processing trên FPGA

---

## 🏗️ Kiến Trúc Hệ Thống

```
┌─────────────────┐
│   RGB565 Input  │ (16-bit)
│   (Pixel Data)  │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ RGB565 to Grayscale Module  │
│ (rgb565_to_gray_pipe)       │
├─────────────────────────────┤
│ - Trích xuất R, G, B        │
│ - Tính toán Gray = f(R,G,B)│
│ - Chuyển lại sang RGB565    │
└────────┬────────────────────┘
         │
         ├─► Gray8 (8-bit)   ◄─ Có sẵn để lấy
         │
         ▼
┌──────────────────────────────┐
│ Sobel Edge Detection Module  │
│ (sobel_edge_gray_pipe)       │
├──────────────────────────────┤
│ Stage 1: Tạo window 3×3     │
│ Stage 2: Shift register      │
│ Stage 3: Tính Gx, Gy         │
│ Stage 4: Lấy giá trị tuyệt   │
│ Stage 5: So sánh Threshold   │
└────────┬─────────────────────┘
         │
         ▼
┌────────────────────┐
│  Binary Edge Map   │
│ (0=No edge/1=Edge) │
│ (RGB565 format)    │
└────────────────────┘
```

**Mô Tả Các Module:**

| Module           |         Chức Năng             | Input |                    Output                 |
|------------------|-------------------------------|-------|-------------------------------------------|
| `rgb565_to_gray` | Chuyển đổi RGB565 → Grayscale | 16-bit| Gray8 (8-bit) + Gray565 (16-bit)          |
| `sobel_edge`     | Phát hiện cạnh Sobel          | 8-bit | 16-bit Binary (0xFFFF=edge, 0x0000=none)  |
| `sobel_top`      | Module cấp cao tích hợp       | 16-bit| Gray565 + Edge565                         |

### **❓ Tại Sao Chuyển Lại sang Gray565?**

**Lý do quan trọng:**

1. **Định dạng thống nhất (Format consistency)**
   - Input: RGB565 (16-bit)
   - Output: Gray565 + Edge565 (cả 16-bit)
   - Advantage: Dễ xử lý tiếp theo, có thể xuất trực tiếp sang display/DAC

2. **Hiệu suất xử lý (Processing efficiency)**
   - Gray8 chỉ 8-bit, nhưng bus ngoài là 16-bit
   - Lãng phí bandwidth nếu xuất Gray8
   - Gray565 tận dụng toàn bộ 16-bit bus → Hiệu quả cao hơn
   - Tốc độ truyền: 1 pixel/clock (không chậm hơn)

3. **Tương thích hiển thị (Display compatibility)**
   ```
   Gray565 = {Gray[7:3], Gray[7:2], Gray[7:3]}
          = {R5 bits  ,  G6 bits  , B5 bits}
   
   Khi hiển thị: R=G=B = Gray → Ảnh grayscale trắng đen
   Có thể xuất trực tiếp sang:
   - RGB565 DAC/LCD
   - HDMI/VGA converter
   - Frame buffer (không cần convert lại)
   ```

---

## 🔬 Thuật Toán Sobel

### Khái Niệm Cơ Bản

Sobel Operator là một thuật toán phát hiện cạnh dựa trên **tính đạo hàm** của hình ảnh:
- **Gx**: Đạo hàm theo phương ngang (phát hiện cạnh dọc)
- **Gy**: Đạo hàm theo phương dọc (phát hiện cạnh ngang)

### Sobel Kernel (Mặt nạ 3×3)

**Kernel Gx (Gradient X - cạnh dọc):**
```
┌─────┬─────┬─────┐
│ -1  │  0  │ +1  │
├─────┼─────┼─────┤
│ -2  │  0  │ +2  │
├─────┼─────┼─────┤
│ -1  │  0  │ +1  │
└─────┴─────┴─────┘
```

**Kernel Gy (Gradient Y - cạnh ngang):**
```
┌──────┬──────┬──────┐
│ +1   │ +2   │ +1   │
├──────┼──────┼──────┤
│  0   │  0   │  0   │
├──────┼──────┼──────┤
│ -1   │ -2   │ -1   │
└──────┴──────┴──────┘
```

### Công Thức Tính Toán

Với cửa sổ 3×3:
```
┌────┬────┬────┐
│ w00│ w01│ w02│
├────┼────┼────┤
│ w10│ w11│ w12│
├────┼────┼────┤
│ w20│ w21│ w22│
└────┴────┴────┘
```

**Gx = (-1)×w00 + (0)×w01 + (+1)×w02 + (-2)×w10 + (0)×w11 + (+2)×w12 + (-1)×w20 + (0)×w21 + (+1)×w22**

Đơn giản hóa:
```
Gx = (w02 - w00) + 2×(w12 - w10) + (w22 - w20)
Gy = (w00 + 2×w01 + w02) - (w20 + 2×w21 + w22)
```

**Edge Magnitude:**
$$M = |Gx| + |Gy|$$

Nếu $M > THRESHOLD$ → Cạnh (Edge) → Xuất 0xFFFF (trắng)

Nếu $M ≤ THRESHOLD$ → Không cạnh → Xuất 0x0000 (đen)

---

## 🔄 Pipeline Chi Tiết

Hệ thống sử dụng **5 giai đoạn pipeline** để đạt throughput cao (1 pixel/clock):

### **Stage 1: Tạo Cửa Sổ 3×3 - Phần 1**

**Mục đích:** Lấy 3 pixel theo cột (top, middle, bottom)

**Cách thực hiện:**
- Dùng 2 line buffers: `line_buffer_1`, `line_buffer_2`
- Mỗi line buffer chứa WIDTH pixels
- Khi pixel mới đến:
  - `top_s1` = pixel 2 hàng phía trên (từ line_buffer_2)
  - `mid_s1` = pixel 1 hàng phía trên (từ line_buffer_1)
  - `bot_s1` = pixel hiện tại (gray8_in)

**Tại sao dùng line buffers?**
- Không thể lưu toàn bộ ảnh (quá nhiều memory)
- Chỉ cần lưu 2 hàng trước để tạo cửa sổ 3×3
- Cơ chế FIFO ẩn: khi ghi pixel mới, pixel cũ tự động shift

**Công thức:**
```verilog
line_buffer_2[x] <= line_buffer_1[x];  // Shift cũ xuống
line_buffer_1[x] <= gray8_in;          // Ghi mới
```

### **Stage 2: Tạo Cửa Sổ 3×3 - Phần 2**

**Mục đích:** Shift register 3×3 hoàn chỉnh

**Cách thực hiện:**
- Sử dụng shift registers: `p00-p02`, `p10-p12`, `p20-p22`
- Kết hợp dữ liệu từ stage 1 để tạo window hoàn chỉnh
- Xây dựng cửa sổ 3×3:
  ```
  w00 = p01    w01 = p02    w02 = top_s1
  w10 = p11    w11 = p12    w12 = mid_s1
  w20 = p21    w21 = p22    w22 = bot_s1
  ```

**Sơ đồ shift:**
```
Stage 2 - Register shift:

Trước:
p00  p01  p02
p10  p11  p12
p20  p21  p22

Sau (pixel mới từ stage 1):
p01  p02  top_s1
p11  p12  mid_s1
p21  p22  bot_s1

Khi điểm ảnh x=1, y=1, tạo window:
w00=p01  w01=p02  w02=top_s1  (hàng 0)
w10=p11  w11=p12  w12=mid_s1  (hàng 1)
w20=p21  w21=p22  w22=bot_s1  (hàng 2)
```

### **Stage 3: Tính Gradient Gx, Gy**

**Mục đích:** Tính đạo hàm hình ảnh

**Công thức trong code:**
```verilog
gx_s3 = (0 - w00_s2) + w02_s2 
        - (w10_s2 * 2) + (w12_s2 * 2) 
        - w20_s2 + w22_s2;

gy_s3 = w00_s2 + (w01_s2 * 2) + w02_s2 
        - w20_s2 - (w21_s2 * 2) - w22_s2;
```

**Kết quả:** Signed 16-bit values (có thể âm)

### **Stage 4: Lấy Giá Trị Tuyệt Đối**

**Mục đích:** Tính |Gx| và |Gy|

```verilog
abs_gx_s4 = (gx_s3 < 0) ? (0 - gx_s3) : gx_s3;
abs_gy_s4 = (gy_s3 < 0) ? (0 - gy_s3) : gy_s3;
```

### **Stage 5: Tính Magnitude & Threshold**

**Mục đích:** Quyết định pixel có phải cạnh không

```verilog
// Tính magnitude
edge_mag_s5 = abs_gx_s4 + abs_gy_s4;

// Áp dụng threshold
if (edge_mag_s5 > THRESHOLD)
    edge_pixel_out = 16'hFFFF;  // Trắng = cạnh
else
    edge_pixel_out = 16'h0000;  // Đen = không cạnh

// Xử lý biên (2 pixel lề không xử lý)
if (x_s5 < 2 || y_s5 < 2 || 
    x_s5 >= IMG_WIDTH-1 || y_s5 >= IMG_HEIGHT-1)
    edge_pixel_out = 16'h0000;  // Biên luôn là đen
```

### **Biểu Đồ Timing Pipeline**

```
       ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
CLOCK  │ 0   │ 1   │ 2   │ 3   │ 4   │ 5   │ 6   │ 7   │
       ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
Pixel0 │ ST1 │ ST2 │ ST3 │ ST4 │ ST5 │ OUT │ OUT │ OUT │
Pixel1 │     │ ST1 │ ST2 │ ST3 │ ST4 │ ST5 │ OUT │ OUT │
Pixel2 │     │     │ ST1 │ ST2 │ ST3 │ ST4 │ ST5 │ OUT │
Pixel3 │     │     │     │ ST1 │ ST2 │ ST3 │ ST4 │ ST5 │
Pixel4 │     │     │     │     │ ST1 │ ST2 │ ST3 │ ST4 │
       └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘

   ST1 = Stage 1: Lấy 3 pixels (top/mid/bot)
   ST2 = Stage 2: Tạo window 3×3
   ST3 = Stage 3: Tính Gx, Gy
   ST4 = Stage 4: Lấy giá trị tuyệt đối |Gx|, |Gy|
   ST5 = Stage 5: Tính magnitude & so sánh threshold
   OUT = Output được phát hành (valid)

   ⏱️  Độ trễ (Latency):  5 clock cycles
   🚀 Throughput:        1 pixel/clock (sau khi đầy pipeline)
   📊 Utilization:       Pixel 0-4 = fill, Pixel 5+ = 100% output
```

---

## 📥📤 Input/Output

### **Sobel Top Module (sobel_top.v)**

#### **Input Ports:**
| Port             | Bits    | Ý Nghĩa             |
|------------------|---------|-------------------  |
| `clk`            | 1 bit   | Xung clock          |
| `rst`            | 1 bit   | Reset (active high) |
| `pixel_valid_in` | 1 bit   | Có pixel hợp lệ vào |
| `rgb565_in`      | 16 bits |  [R5bits:G6bits:B5bits] |

#### **Output Ports:**
| Port              | Bít   | Ý Nghĩa                       |
|------------       |-------  |---------------------------  |
| `gray_valid_out`  | 1 bit   | Có pixel gray hợp lệ ra     |
| `gray565_out`     | 16 bits | Grayscale dưới dạng RGB565  |
| `edge_valid_out`  | 1 bit   | Có pixel edge hợp lệ ra     |
| `edge565_out`     | 16 bits | Edge map: 0xFFFF=edge, 0x0000=no edge |

### **Định Dạng RGB565**

```
┌───────────────────────────────────────────────────────────┐
│ 15  14  13  12  11  │ 10  9  8  7  6  5  │ 4  3  2  1  0  │
│      Red (5 bits)   │   Green (6 bits)  │ Blue (5 bits)   │
└───────────────────────────────────────────────────────────┘

Ví dụ:
- Đỏ thuần:      1111100000000000 = 0xF800
- Xanh thuần:    0000011111100000 = 0x07E0
- Xanh dương:    0000000000011111 = 0x001F
- Trắng:         1111111111111111 = 0xFFFF
- Đen:           0000000000000000 = 0x0000
```

### **RGB to Gray Conversion**

**Công thức:**
```
R8 = Extend(R5) = {R5, R5[4:2]}
G8 = Extend(G6) = {G6, G6[5:4]}
B8 = Extend(B5) = {B5, B5[4:2]}

Gray8 = (R8 >> 2) + (G8 >> 1) + (B8 >> 2)
      = (R8/4) + (G8/2) + (B8/4)  ✓ Approximate ITU-R BT.601
```

**Gray565 Output:**
```
Gray565 = {Gray8[7:3], Gray8[7:2], Gray8[7:3]}
        = {R5=Gray[7:3], G6=Gray[7:2], B5=Gray[7:3]}
```

### **Timing Input/Output - Waveform Diagram**

```
Time (ns)    0     80    160   240   320   400   480   560   640   720   800
             │     │     │     │     │     │     │     │     │     │     │
clk          │  ╭─────╮ ╭─────╮ ╭─────╮ ╭─────╮ ╭─────╮ ╭─────╮ ╭─────╮ ╭─────╮
             ╰──┴─────┴─┴─────┴─┴─────┴─┴─────┴─┴─────┴─┴─────┴─┴─────┴─┴─────┴──
             T0    T1    T2    T3    T4    T5    T6    T7    T8

pixel_       │
valid_in     │  ╭──────╮ ╭──────╮ ╭──────╮ ╭──────╮ ╰──────────────────────
             ╰──┴──────┴─┴──────┴─┴──────┴─┴──────┴────────────────────────
                P0/1  │ P1/1  │ P2/1  │ P3/1  │ 0
                      
rgb565_in    │  
(data)       │  ╭──────────╮ ╭──────────╮ ╭──────────╮ ╭──────────╮ ╰──────
             ╰──┴──────────┴─┴──────────┴─┴──────────┴─┴──────────┴────────
                 P0     P1     P2     P3   (--/--/--/--)

gray_valid_  │     
out          │     ╭──────╮ ╭──────╮ ╭──────╮ ╭──────╮ ╰──────────────
             ╰─────┴──────┴─┴──────┴─┴──────┴─┴──────┴─────────────
             (--)  1     1     1     1   (0)
                  [1 clk delay]

gray565_out  │     
(data)       │     ╭──────────╮ ╭──────────╮ ╭──────────╮ ╭──────────╮ ╰
             ╰─────┴──────────┴─┴──────────┴─┴──────────┴─┴──────────┴────
                  G0    G1     G2    G3   (--)
                  [1 clk delay from input]

edge_valid_  │
out          │                                ╭──────╮ ╭──────╮ ╭──────╮
             ╰────────────────────────────────┴──────┴─┴──────┴─┴──────┴─
             (--/--/--/--/--) 1     1     1
                           [5 clk delay]

edge565_out  │
(data)       │                                ╭──────────╮ ╭──────────╮ ╭──
             ╰────────────────────────────────┴──────────┴─┴──────────┴─┴──
             (--/--/--/--/--) E0    E1     E2
                           [5 clk delay from input]
```

**Giải Thích Chi Tiết:**

| Tín Hiệu | Trạng Thái | Mô Tả |
|----------|-----------|-------|
| **clk** | Sóng vuông 50MHz | Period = 80ns, Frequency = 12.5MHz |
| **pixel_valid_in** | 1 → 0 | Mức cao (1) cho 4 clock, rồi mức thấp (0) |
| **rgb565_in** | P0→P1→P2→P3→-- | Dữ liệu thay đổi tại cạnh lên của clock |
| **gray_valid_out** | Trễ 1 CLK | Output xuất hiện sau input 1 chu kỳ |
| **gray565_out** | G0→G1→G2→G3 | Gray data trễ 1 clock so với input |
| **edge_valid_out** | Trễ 5 CLK | Xuất hiện sau 5 chu kỳ xử lý |
| **edge565_out** | E0→E1→E2 | Edge data trễ 5 clocks |

**Timeline (Clock Cycle):**
- **T0:** Input nhận P0, `pixel_valid_in = 1`
- **T1:** Input nhận P1, Gray output xuất G0
- **T2:** Input nhận P2, Gray output xuất G1
- **T3:** Input nhận P3, Gray output xuất G2
- **T4:** Input dừng (`pixel_valid_in = 0`), Gray output xuất G3
- **T5:** Edge output xuất E0 (P0 đã xử lý xong 5 stages)
- **T6:** Edge output xuất E1
- **T7:** Edge output xuất E2
```

---

## 🚀 Cách Sử Dụng

### **1. Instantiation (Sử Dụng Module)**

```verilog
sobel_top #(
    .IMG_WIDTH(320),
    .IMG_HEIGHT(240),
    .THRESHOLD(100)
) u_sobel (
    .clk(clk),
    .rst(rst),
    
    .pixel_valid_in(pixel_valid),
    .rgb565_in(pixel_data),
    
    .gray_valid_out(gray_valid),
    .gray565_out(gray_data),
    
    .edge_valid_out(edge_valid),
    .edge565_out(edge_data)
);
```

### **2. Reset Sequence**

```verilog
// Tuần tự khởi động:
initial begin
    clk = 1'b0;
    rst = 1'b1;           // Assert reset
    pixel_valid_in = 1'b0;
    
    #30;                  // Chờ vài clock
    rst = 1'b0;           // Release reset
    
    #10;                  // Chờ thêm
    // Bây giờ có thể bắt đầu gửi pixel
end
```

### **3. Input Pixel Stream (Gửi Ảnh)**

```verilog
// Gửi ảnh kích thước IMG_WIDTH x IMG_HEIGHT
for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
    for (x = 0; x < IMG_WIDTH; x = x + 1) begin
        @(posedge clk);
        pixel_valid_in = 1'b1;
        rgb565_in = get_pixel_data(y, x);  // Pixel hàng y, cột x
    end
end

// Kết thúc stream
@(posedge clk);
pixel_valid_in = 1'b0;
rgb565_in = 16'h0000;

// Chờ output hoàn thành (tối thiểu IMG_WIDTH*IMG_HEIGHT + 5 clocks)
#(IMG_WIDTH * IMG_HEIGHT * 10 + 100);
```

### **4. Đọc Output (Nhận Kết Quả)**

```verilog
always @(posedge clk) begin
    if (edge_valid_out) begin
        // Pixel cạnh được phát hiện
        if (edge565_out == 16'hFFFF) begin
            $display("Edge detected at output");
        end else begin
            $display("No edge at output");
        end
    end
end
```

### **5. Quy Trình Chi Tiết (Step-by-step)**

```
Step 1: Reset hệ thống
├─ Đặt rst = 1'b1
├─ Chờ ≥2 clock cycles
└─ Đặt rst = 1'b0

Step 2: Gửi ảnh RGB565 (stream)
├─ Tuần tự hàng 0, cột 0 → cột WIDTH-1
├─ Rồi hàng 1, cột 0 → cột WIDTH-1
├─ ... tiếp tục đến hàng HEIGHT-1
└─ pixel_valid_in = 1 khi gửi, 0 khi xong

Step 3: Nhận grayscale (optional)
├─ gray_valid_out = 1 khi có gray pixel
├─ Delay từ input: 1 clock
└─ Xuất thứ tự tương tự như input

Step 4: Nhận edge map
├─ edge_valid_out = 1 khi có edge pixel
├─ Delay từ input: 5 clocks
├─ 0xFFFF = cạnh (trắng), 0x0000 = không cạnh (đen)
└─ 2 pixel biên luôn = 0 (không xử lý biên)

Step 5: Lưu/hiển thị kết quả
├─ Lưu edge pixels vào memory/file
└─ Xử lý tiếp (optional)
```

---

## ⚙️ Các Tham Số Cấu Hình

### **Parameters**

| Tham Số | Mặc Định | Giải Thích |
|---------|----------|-----------|
| `IMG_WIDTH` | 320 | Chiều rộng ảnh (pixels) |
| `IMG_HEIGHT` | 240 | Chiều cao ảnh (pixels) |
| `THRESHOLD` | 100 | Ngưỡng phát hiện cạnh (0-1023) |

### **Cách Thay Đổi Tham Số**

```verilog
// Option 1: Trong module top level
sobel_top #(
    .IMG_WIDTH(640),      // 640 pixels chiều rộng
    .IMG_HEIGHT(480),     // 480 pixels chiều cao
    .THRESHOLD(150)       // Threshold cao hơn = ít cạnh hơn
) u_sobel (...);

// Option 2: Trong file .qsf (Quartus)
set_parameter -name IMG_WIDTH 640
set_parameter -name IMG_HEIGHT 480
set_parameter -name THRESHOLD 150
```

### **Hướng Dẫn Chọn THRESHOLD**

| Giá Trị     |         Hiệu Ứng          |           Sử Dụng           |
|------------ |---------------------------|-----------------------------|
| **< 50**    | Quá nhạy cảm, nhiều nhiễu | Ảnh tối, cần phát hiện yếu  |
| **50-100**  | Phù hợp mặc định          | Hầu hết ảnh bình thường     |
| **100-150** | Trung bình                | Ảnh rõ nét, cần ít nhiễu    |
| **> 150**   | Ít nhạy cảm, chỉ cạnh mạnh| Ảnh sáng, chỉ cạnh lớn      |

### **Yêu Cầu Memory**

Với các tham số cho trước, memory cần thiết:

```
Line Buffers: 2 × IMG_WIDTH × 8 bits
            = 2 × 320 × 8 = 5,120 bits ≈ 640 bytes (VẬY NHỎ!)

Ví dụ với IMG_WIDTH = 640:
            = 2 × 640 × 8 = 10,240 bits ≈ 1.28 KB

Ví dụ với IMG_WIDTH = 1920:
            = 2 × 1920 × 8 = 30,720 bits ≈ 3.84 KB
```

---

## 📋 Ví Dụ Thực Tế

### **Ví Dụ 1: Phát Hiện Cạnh Đơn Giản (9×9 pixels)**

```verilog
module tb_example;
    reg clk, rst;
    reg pixel_valid;
    reg [15:0] rgb565;
    wire edge_valid;
    wire [15:0] edge_out;

    sobel_top #(
        .IMG_WIDTH(9),
        .IMG_HEIGHT(9),
        .THRESHOLD(100)
    ) dut (
        .clk(clk),
        .rst(rst),
        .pixel_valid_in(pixel_valid),
        .rgb565_in(rgb565),
        .edge_valid_out(edge_valid),
        .edge565_out(edge_out)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        pixel_valid = 0;
        
        #30;
        rst = 0;
        #10;

        // Gửi ảnh 9×9
        for (int y = 0; y < 9; y++) begin
            for (int x = 0; x < 9; x++) begin
                @(posedge clk);
                pixel_valid = 1;
                
                // Tạo pattern: trái đen, phải sáng
                if (x < 4)
                    rgb565 = 16'h0000;  // Đen
                else
                    rgb565 = 16'hFFFF;  // Trắng
            end
        end

        @(posedge clk);
        pixel_valid = 0;
        
        #500;
        $finish;
    end

    // Monitor output
    always @(posedge clk) begin
        if (edge_valid) begin
            $display("Edge output: %h", edge_out);
        end
    end
endmodule
```

**Kết quả dự kiến:**
- Biên (2 pixel lề): all 0x0000
- Giữa ảnh (có cạnh dọc): 0xFFFF
- Phần không có cạnh: 0x0000

---

### **Ví Dụ 2: Điều Chỉnh Threshold**

```verilog
// THRESHOLD quá thấp = nhiều nhiễu
sobel_top #(.THRESHOLD(30)) u_low_threshold (...);
// ✓ Phát hiện cạnh nhỏ/yếu
// ✗ Nhiều false positive

// THRESHOLD phù hợp = cân bằng
sobel_top #(.THRESHOLD(100)) u_normal_threshold (...);
// ✓ Phát hiện cạnh chính
// ✓ Ít nhiễu

// THRESHOLD quá cao = bỏ lỡ cạnh
sobel_top #(.THRESHOLD(200)) u_high_threshold (...);
// ✗ Bỏ lỡ cạnh yếu
// ✓ Rất ít nhiễu
```

---

### **Ví Dụ 3: Xử Lý Ảnh VGA (640×480)**

```verilog
sobel_top #(
    .IMG_WIDTH(640),
    .IMG_HEIGHT(480),
    .THRESHOLD(120)
) u_vga_edge (
    .clk(vga_clk),        // 25 MHz cho VGA
    .rst(~vga_reset_n),   // Active low → active high
    .pixel_valid_in(vga_de),  // Data enable
    .rgb565_in(vga_rgb565),
    .edge_valid_out(edge_de),
    .edge565_out(edge_rgb565)
);

// Kết nối output cạnh trực tiếp sang DAC/display
```

---

### **Ví Dụ 4: Pipeline Xử Lý Ảnh**

```
Luồng xử lý:
┌──────────────┐
│ Camera/Input │ RGB565 stream
└────────┬─────┘
         │
         ▼
┌──────────────────────┐
│ Sobel Edge Detection │ (module này)
│                      │
│ RGB565 → Gray → Edge │
└────────┬─────────────┘
         │
         ├─► Output 1: Gray image
         │   Sử dụng để contrast enhancement
         │
         └─► Output 2: Edge map
             Sử dụng để:
             - Feature extraction
             - Object recognition
             - Line detection
             - Corner detection (FAST, ORB)

┌──────────────────┐
│ Post-processing  │
└──────────────────┘
```

---

## 🔧 Troubleshooting

### **Vấn Đề 1: Output toàn 0x0000 (Không Phát Hiện Cạnh)**

**Nguyên nhân:**
- Threshold quá cao
- Input ảnh quá tối/sáng

**Giải pháp:**
```verilog
// Giảm threshold
sobel_top #(.THRESHOLD(50)) u_sobel (...);

// Hoặc chuẩn hóa input
// Đảm bảo ảnh có độ contrast đủ
```

### **Vấn Đề 2: Output quá nhiều nhiễu**

**Nguyên nhân:**
- Threshold quá thấp
- Input có nhiễu

**Giải pháp:**
```verilog
// Tăng threshold
sobel_top #(.THRESHOLD(200)) u_sobel (...);

// Hoặc thêm blur filter trước
```

### **Vấn Đề 3: Output lệch so với input**

**Nguyên nhân:**
- Đây là bình thường! Delay = 5 clocks + 1 clock RGB→Gray = 6 tổng cộng

**Giải pháp:**
- Đồng bộ hóa input/output bằng cách lưu timestamp hoặc x,y coordinates

---

## 📚 Tóm Tắt

| Khía Cạnh         |                 Chi Tiết                  |
|-------------------|-------------------------------------------|
| **Input**         | RGB565 pixels (16-bit)                    |
| **Output**        | Edge map (binary 0/0xFFFF) + Gray option  |
| **Latency**       | 6 clocks (1 gray + 5 edge)                |
| **Throughput**    | 1 pixel/clock                             |
| **Algorithm**     | Sobel Operator 3×3 kernel                 |
| **THRESHOLD**     | Điều chỉnh độ nhạy cảm (0-1023)           |
| **Memory**        | ~640B cho 320×240 (chỉ line buffers)      |
| **FPGA Friendly** | ✓ Pipeline, ✓ Streaming, ✓ Low memory    |

---

**Tác giả:** qkhai111105
**Ngày:** 2024-2025  
**Phiên bản:** 1.0

