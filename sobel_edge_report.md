# Báo Cáo Module Sobel Edge Detection

## 1. Giới Thiệu

Module `sobel_edge.v` được sử dụng để phát hiện biên trên ảnh xám 8-bit. Đầu vào của module là từng pixel mức xám `gray8_in`, đi kèm tín hiệu hợp lệ `gray_valid_in`. Dữ liệu ảnh được đưa vào theo thứ tự pixel raster.

Trong hệ thống này, thuật toán Sobel được triển khai bằng phần cứng theo dạng pipeline. Mỗi chu kỳ clock, module có thể nhận một pixel mới, trong khi các pixel trước đó đang được xử lý ở các tầng pipeline.

## 2. Cơ Sở Lý Thuyết Thuật Toán Sobel

Thuật toán Sobel là một phương pháp phát hiện biên dựa trên sự thay đổi cường độ sáng của các pixel lân cận. Trong ảnh số, biên thường xuất hiện tại những vị trí mà mức xám thay đổi đột ngột. Vì vậy, bằng cách tính toán đạo hàm của mức xám, ta có thể phát hiện được biên.

Xét một cửa sổ ảnh kích thước 3x3 quanh pixel trung tâm:

```text
P00  P01  P02
P10  P11  P12
P20  P21  P22
```

Trong đó `P11` là pixel trung tâm cần tính biên. Thuật toán Sobel sử dụng hai mặt nạ chập:

```text
Gx kernel:
-1   0   1
-2   0   2
-1   0   1
```

```text
Gy kernel:
 1   2   1
 0   0   0
-1  -2  -1
```

Gradient theo phương X được tính như sau:

```text
Gx = -P00 + P02 - 2P10 + 2P12 - P20 + P22
```

Có thể viết lại thành:

```text
Gx = (P02 - P00) + 2(P12 - P10) + (P22 - P20)
```

Gradient theo phương Y được tính như sau:

```text
Gy = P00 + 2P01 + P02 - P20 - 2P21 - P22
```

Giá trị `Gx` biểu diễn sự thay đổi cường độ sáng theo phương ngang, giúp phát hiện biên đứng. Giá trị `Gy` biểu diễn sự thay đổi cường độ sáng theo phương đứng, giúp phát hiện biên ngang.

Về mặt lý thuyết, độ lớn gradient có thể tính bằng:

```text
G = sqrt(Gx^2 + Gy^2)
```

Tuy nhiên, công thức này cần phép nhân và phép căn bậc hai, gây tốn tài nguyên khi triển khai trên FPGA. Do đó, trong thiết kế phần cứng, độ lớn biên được xấp xỉ bằng:

```text
G ≈ |Gx| + |Gy|
```

Nếu `G` lớn hơn ngưỡng `THRESHOLD`, pixel được xem là pixel biên. Nếu `G` nhỏ hơn hoặc bằng ngưỡng, pixel được xem là nền.

```text
G > THRESHOLD   -> pixel biên
G <= THRESHOLD  -> pixel không phải biên
```

Trong module này, pixel biên được xuất ra giá trị trắng `16'hFFFF`, còn pixel không phải biên được xuất ra giá trị đen `16'h0000`.

## 3. Kiến Trúc Phần Cứng Của Module sobel_edge

Module `sobel_edge.v` gồm các khối chính sau:

- Bộ đếm tọa độ `x`, `y`
- Hai line buffer: `line_buffer_1`, `line_buffer_2`
- Tầng tạo cột pixel đọc
- Hệ thanh ghi dịch tạo cửa sổ 3x3
- Khối tính `Gx`, `Gy`
- Khối lấy trị tuyệt đối
- Khối tính độ lớn biên
- Khối so sánh ngưỡng và tạo output
- Pipeline cho tín hiệu `valid`, `x`, `y`

Dữ liệu ảnh đi vào từng pixel một. Do Sobel cần cửa sổ 3x3, module không thể chỉ dùng pixel hiện tại mà phải lưu lại các pixel của hai dòng trước đó. Vì vậy, hai line buffer được sử dụng để lưu trữ lịch sử hai dòng ảnh gần nhất.

## 4. Stage 1: Đọc Line Buffer Và Tạo Cột Pixel

Ở Stage 1, module lấy ba pixel cùng một cột `x` nhưng nằm trên ba dòng khác nhau:

```verilog
top_s1 <= line_buffer_2[x];
mid_s1 <= line_buffer_1[x];
bot_s1 <= gray8_in;
```

Ý nghĩa của ba tín hiệu này là:

```text
top_s1 = pixel ở dòng y-2, cột x
mid_s1 = pixel ở dòng y-1, cột x
bot_s1 = pixel ở dòng y,   cột x
```

Ví dụ với ảnh:

```text
row0: 10  11  12  13
row1: 20  21  22  23
row2: 30  31  32  33
```

Khi đang đọc pixel `row2[2] = 32`, tức là `x = 2`, `y = 2`, line buffer có giá trị:

```text
line_buffer_2[2] = 12
line_buffer_1[2] = 22
gray8_in         = 32
```

Do đó Stage 1 lấy được cột đọc:

```text
12
22
32
```

Sau khi đọc dữ liệu, line buffer được cập nhật:

```verilog
line_buffer_2[x] <= line_buffer_1[x];
line_buffer_1[x] <= gray8_in;
```

Việc cập nhật này dùng để chuẩn bị cho các dòng tiếp theo. Do trong Verilog các phép gán trong mạch tuần tự sử dụng non-blocking assignment `<=`, giá trị cũ của line buffer được đọc trước, sau đó line buffer được cập nhật giá trị mới.

## 5. Stage 2: Tạo Cửa Sổ 3x3

Sau khi Stage 1 tạo ra một cột gồm ba pixel `top_s1`, `mid_s1`, `bot_s1`, Stage 2 sử dụng các thanh ghi dịch để giữ lại ba cột gần nhất. Các thanh ghi này có tên:

```text
p00 p01 p02
p10 p11 p12
p20 p21 p22
```

Mỗi khi có một cột mới đi vào, các cột cũ được dịch sang trái và cột mới được đưa vào bên phải. Sau đó cửa sổ 3x3 được chốt vào các thanh ghi:

```text
w00_s2  w01_s2  w02_s2
w10_s2  w11_s2  w12_s2
w20_s2  w21_s2  w22_s2
```

Các giá trị này tương ứng với `P00` đến `P22` trong công thức Sobel.

Khi ảnh đầu vào có kích thước 320x240, tọa độ `x` chạy từ `0` đến `319`. Sau khi `x` chạy hết 320 pixel, `x` về 0 và `y` tăng lên 1. Cửa sổ 3x3 hợp lệ đầu tiên chỉ xuất hiện khi đã có đủ ba dòng và ba cột dữ liệu.

Tại thời điểm đó, cửa sổ đầu tiên là:

```text
row0[0]  row0[1]  row0[2]
row1[0]  row1[1]  row1[2]
row2[0]  row2[1]  row2[2]
```

Kết quả Sobel của cửa sổ này không thuộc về pixel hiện tại `row2[2]`, mà thuộc về pixel trung tâm `row1[1]`. Vì vậy, địa chỉ output phải được tính theo tọa độ trung tâm của cửa sổ.

## 6. Stage 3: Tính Gradient Gx Và Gy

Stage 3 thực hiện tính hai gradient `Gx` và `Gy` dựa trên cửa sổ 3x3 đã được tạo ở Stage 2.

Trong code, `Gx` được tính như sau:

```verilog
gx_s3 <=
    $signed({1'b0, w02_s2}) - $signed({1'b0, w00_s2}) +
    (($signed({1'b0, w12_s2}) - $signed({1'b0, w10_s2})) <<< 1) +
    $signed({1'b0, w22_s2}) - $signed({1'b0, w20_s2});
```

Công thức này tương ứng với:

```text
Gx = (P02 - P00) + 2(P12 - P10) + (P22 - P20)
```

Trong code, phép nhân với 2 được thực hiện bằng dịch trái một bit `<<< 1`. Cách này tiết kiệm tài nguyên phần cứng hơn so với sử dụng bộ nhân.

Tương tự, `Gy` được tính như sau:

```verilog
gy_s3 <=
    $signed({1'b0, w00_s2}) +
    ($signed({1'b0, w01_s2}) <<< 1) +
    $signed({1'b0, w02_s2}) -
    $signed({1'b0, w20_s2}) -
    ($signed({1'b0, w21_s2}) <<< 1) -
    $signed({1'b0, w22_s2});
```

Công thức này tương ứng với:

```text
Gy = P00 + 2P01 + P02 - P20 - 2P21 - P22
```

Sau Stage 3, hai giá trị `gx_s3` và `gy_s3` biểu diễn mức thay đổi cường độ sáng theo hai phương X và Y.

## 7. Stage 4: Lấy Trị Tuyệt Đối

Giá trị `Gx` và `Gy` có thể âm hoặc dương, tùy thuộc vào chiều thay đổi mức xám. Tuy nhiên, khi phát hiện biên, ta chỉ quan tâm độ lớn thay đổi, không quan tâm dấu âm hay dương. Vì vậy, Stage 4 lấy trị tuyệt đối:

```text
abs_gx_s4 = |Gx|
abs_gy_s4 = |Gy|
```

Trong phần cứng, nếu gradient nhỏ hơn 0 thì module lấy `0 - gradient`, ngược lại giữ nguyên giá trị gradient.

## 8. Stage 5: Tính Độ Lớn Biên

Stage 5 tính độ lớn biên xấp xỉ bằng tổng hai trị tuyệt đối:

```text
edge_mag_s5 = abs_gx_s4 + abs_gy_s4
```

Đây là cách xấp xỉ của công thức lý thuyết:

```text
G = sqrt(Gx^2 + Gy^2)
```

Việc sử dụng `|Gx| + |Gy|` giúp mạch đơn giản hơn, chỉ cần các bộ cộng và mạch lấy trị tuyệt đối, không cần bộ nhân bình phương hoặc mạch căn bậc hai. Điều này rất phù hợp với FPGA.

## 9. Output Stage: So Sánh Ngưỡng Và Tạo Pixel Đầu Ra

Ở tầng cuối, module so sánh `edge_mag_s5` với ngưỡng `THRESHOLD`.

Nếu độ lớn biên lớn hơn ngưỡng:

```verilog
edge_pixel_out <= 16'hFFFF;
```

Pixel đầu ra có màu trắng, biểu thị có biên.

Nếu độ lớn biên nhỏ hơn hoặc bằng ngưỡng:

```verilog
edge_pixel_out <= 16'h0000;
```

Pixel đầu ra có màu đen, biểu thị không có biên.

Địa chỉ pixel đầu ra được tính bằng:

```verilog
edge_addr_out <= pixel_addr(y_s5 - 1, x_s5 - 1);
```

Lý do trừ 1 ở cả `x` và `y` là vì khi pixel hiện tại nằm ở góc dưới bên phải của cửa sổ 3x3, kết quả Sobel thực sự thuộc về pixel trung tâm của cửa sổ, tức là tọa độ `(x-1, y-1)`.

Đối với các pixel biên ảnh như `x = 0`, `x = 1`, `y = 0`, hoặc `y = 1`, cửa sổ 3x3 chưa hợp lệ đầy đủ. Vì vậy, module gán pixel đầu ra bằng đen.

## 10. Pipeline Valid Và Tọa Độ

Do module được thiết kế theo dạng pipeline, dữ liệu pixel đi qua nhiều tầng xử lý. Để đảm bảo output đúng với dữ liệu đang xử lý, các tín hiệu `valid`, `x`, và `y` cũng được delay qua từng tầng pipeline:

```text
valid_s1 -> valid_s2 -> valid_s3 -> valid_s4 -> valid_s5
x_s1     -> x_s2     -> x_s3     -> x_s4     -> x_s5
y_s1     -> y_s2     -> y_s3     -> y_s4     -> y_s5
```

Nhờ đó, khi `edge_mag_s5` đi đến tầng output, tọa độ `x_s5`, `y_s5` và tín hiệu `valid_s5` cũng đến đúng thời điểm. Điều này đảm bảo `edge_addr_out`, `edge_pixel_out`, và `edge_valid_out` khớp với nhau.

## 11. Kết Luận

Module `sobel_edge.v` là một thiết kế phát hiện biên theo thuật toán Sobel được tối ưu cho xử lý phần cứng. Thiết kế sử dụng hai line buffer để lưu hai dòng ảnh trước, các thanh ghi dịch để tạo cửa sổ 3x3, và các khối tính toán để xác định biên dựa trên gradient.

Nhờ kiến trúc pipeline, module có khả năng nhận một pixel mới mỗi chu kỳ clock, giúp tăng tốc độ xử lý và phù hợp với các hệ thống xử lý ảnh thời gian thực trên FPGA.
