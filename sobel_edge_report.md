# Bao Cao Module Sobel Edge Detection

## 1. Gioi thieu

Module `sobel_edge.v` duoc su dung de phat hien bien tren anh xam 8-bit. Dau vao cua module la tung pixel muc xam `gray8_in`, di kem tin hieu hop le `gray_valid_in`. Du lieu anh duoc dua vao theo thu tu raster, nghia la quet tu trai sang phai tren tung dong, sau do chuyen xuong dong tiep theo.

Trong he thong nay, thuat toan Sobel duoc trien khai bang phan cung theo dang pipeline. Moi chu ky clock, module co the nhan mot pixel moi, trong khi cac pixel truoc do dang duoc xu ly o cac tang pipeline tiep theo. Cach thiet ke nay phu hop voi FPGA vi co thong luong cao va tan dung duoc tinh song song cua phan cung.

## 2. Co so ly thuyet thuat toan Sobel

Thuat toan Sobel la mot phuong phap phat hien bien dua tren su thay doi cuong do sang cua cac pixel lan can. Trong anh so, bien thuong xuat hien tai nhung vi tri ma muc xam thay doi dot ngot. Vi vay, Sobel su dung dao ham roi rac theo hai phuong ngang va doc de uoc luong do lon bien tai moi pixel.

Xet mot cua so anh kich thuoc 3x3 quanh pixel trung tam:

```text
P00  P01  P02
P10  P11  P12
P20  P21  P22
```

Trong do `P11` la pixel trung tam can tinh bien. Thuat toan Sobel su dung hai mat na chap:

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

Gradient theo phuong X duoc tinh nhu sau:

```text
Gx = -P00 + P02 - 2P10 + 2P12 - P20 + P22
```

Co the viet lai thanh:

```text
Gx = (P02 - P00) + 2(P12 - P10) + (P22 - P20)
```

Gradient theo phuong Y duoc tinh nhu sau:

```text
Gy = P00 + 2P01 + P02 - P20 - 2P21 - P22
```

Gia tri `Gx` bieu dien su thay doi cuong do sang theo phuong ngang, giup phat hien bien doc. Gia tri `Gy` bieu dien su thay doi cuong do sang theo phuong doc, giup phat hien bien ngang.

Ve mat ly thuyet, do lon gradient co the tinh bang:

```text
G = sqrt(Gx^2 + Gy^2)
```

Tuy nhien, cong thuc nay can phep nhan va phep can bac hai, gay ton tai nguyen khi trien khai tren FPGA. Do do, trong thiet ke phan cung, do lon bien duoc xap xi bang:

```text
G ≈ |Gx| + |Gy|
```

Neu `G` lon hon nguong `THRESHOLD`, pixel duoc xem la pixel bien. Neu `G` nho hon hoac bang nguong, pixel duoc xem la nen.

```text
G > THRESHOLD   -> pixel bien
G <= THRESHOLD  -> pixel khong phai bien
```

Trong module nay, pixel bien duoc xuat ra gia tri trang `16'hFFFF`, con pixel khong phai bien duoc xuat ra gia tri den `16'h0000`.

## 3. Kien truc phan cung cua module sobel_edge

Module `sobel_edge.v` gom cac khoi chinh sau:

- Bo dem toa do `x`, `y`
- Hai line buffer: `line_buffer_1`, `line_buffer_2`
- Tang tao cot pixel doc
- He thanh ghi dich tao cua so 3x3
- Khoi tinh `Gx`, `Gy`
- Khoi lay tri tuyet doi
- Khoi tinh do lon bien
- Khoi so sanh nguong va tao output
- Pipeline cho tin hieu `valid`, `x`, `y`

Du lieu anh di vao tung pixel mot. Do Sobel can cua so 3x3, module khong the chi dung pixel hien tai ma phai luu lai cac pixel cua hai dong truoc do. Vi vay, hai line buffer duoc su dung de luu tru lich su hai dong anh gan nhat.

## 4. Stage 1: Doc line buffer va tao cot pixel

O Stage 1, module lay ba pixel cung mot cot `x` nhung nam tren ba dong khac nhau:

```verilog
top_s1 <= line_buffer_2[x];
mid_s1 <= line_buffer_1[x];
bot_s1 <= gray8_in;
```

Y nghia cua ba tin hieu nay la:

```text
top_s1 = pixel o dong y-2, cot x
mid_s1 = pixel o dong y-1, cot x
bot_s1 = pixel o dong y,   cot x
```

Vi du voi anh:

```text
row0: 10  11  12  13
row1: 20  21  22  23
row2: 30  31  32  33
```

Khi dang doc pixel `row2[2] = 32`, tuc la `x = 2`, `y = 2`, line buffer co gia tri:

```text
line_buffer_2[2] = 12
line_buffer_1[2] = 22
gray8_in         = 32
```

Do do Stage 1 lay duoc cot doc:

```text
12
22
32
```

Sau khi doc du lieu, line buffer duoc cap nhat:

```verilog
line_buffer_2[x] <= line_buffer_1[x];
line_buffer_1[x] <= gray8_in;
```

Viec cap nhat nay dung de chuan bi cho cac dong tiep theo. Do trong Verilog cac phep gan trong mach tuan tu su dung non-blocking assignment `<=`, gia tri cu cua line buffer duoc doc truoc, sau do line buffer moi duoc cap nhat o cuoi chu ky clock. Vi vay, viec doc va ghi cung mot dia chi line buffer trong cung mot chu ky khong lam mat du lieu.

## 5. Stage 2: Tao cua so 3x3

Sau khi Stage 1 tao ra mot cot gom ba pixel `top_s1`, `mid_s1`, `bot_s1`, Stage 2 su dung cac thanh ghi dich de giu lai ba cot gan nhat. Cac thanh ghi nay co ten:

```text
p00 p01 p02
p10 p11 p12
p20 p21 p22
```

Moi khi co mot cot moi di vao, cac cot cu duoc dich sang trai va cot moi duoc dua vao ben phai. Sau do cua so 3x3 duoc chot vao cac thanh ghi:

```text
w00_s2  w01_s2  w02_s2
w10_s2  w11_s2  w12_s2
w20_s2  w21_s2  w22_s2
```

Cac gia tri nay tuong ung voi `P00` den `P22` trong cong thuc Sobel.

Khi anh dau vao co kich thuoc 320x240, toa do `x` chay tu `0` den `319`. Sau khi `x` chay het 320 pixel, `x` ve 0 va `y` tang len 1. Cua so 3x3 hop le dau tien chi xuat hien khi da co du ba dong va ba cot, tuc la tai thoi diem dang doc den `x = 2`, `y = 2`.

Tai thoi diem do, cua so dau tien la:

```text
row0[0]  row0[1]  row0[2]
row1[0]  row1[1]  row1[2]
row2[0]  row2[1]  row2[2]
```

Ket qua Sobel cua cua so nay khong thuoc ve pixel hien tai `row2[2]`, ma thuoc ve pixel trung tam `row1[1]`. Vi vay, dia chi output phai duoc tinh theo toa do trung tam cua cua so.

## 6. Stage 3: Tinh gradient Gx va Gy

Stage 3 thuc hien tinh hai gradient `Gx` va `Gy` dua tren cua so 3x3 da duoc tao o Stage 2.

Trong code, `Gx` duoc tinh nhu sau:

```verilog
gx_s3 <=
    $signed({1'b0, w02_s2}) - $signed({1'b0, w00_s2}) +
    (($signed({1'b0, w12_s2}) - $signed({1'b0, w10_s2})) <<< 1) +
    $signed({1'b0, w22_s2}) - $signed({1'b0, w20_s2});
```

Cong thuc nay tuong ung voi:

```text
Gx = (P02 - P00) + 2(P12 - P10) + (P22 - P20)
```

Trong code, phep nhan voi 2 duoc thuc hien bang dich trai mot bit `<<< 1`. Cach nay tiet kiem tai nguyen phan cung hon so voi su dung bo nhan.

Tuong tu, `Gy` duoc tinh nhu sau:

```verilog
gy_s3 <=
    $signed({1'b0, w00_s2}) +
    ($signed({1'b0, w01_s2}) <<< 1) +
    $signed({1'b0, w02_s2}) -
    $signed({1'b0, w20_s2}) -
    ($signed({1'b0, w21_s2}) <<< 1) -
    $signed({1'b0, w22_s2});
```

Cong thuc nay tuong ung voi:

```text
Gy = P00 + 2P01 + P02 - P20 - 2P21 - P22
```

Sau Stage 3, hai gia tri `gx_s3` va `gy_s3` bieu dien muc thay doi cuong do sang theo hai phuong X va Y.

## 7. Stage 4: Lay tri tuyet doi

Gia tri `Gx` va `Gy` co the am hoac duong, tuy thuoc vao chieu thay doi muc xam. Tuy nhien, khi phat hien bien, ta chi quan tam do lon thay doi, khong quan tam dau am hay duong. Vi vay, Stage 4 lay tri tuyet doi:

```text
abs_gx_s4 = |Gx|
abs_gy_s4 = |Gy|
```

Trong phan cung, neu gradient nho hon 0 thi module lay `0 - gradient`, nguoc lai giu nguyen gia tri gradient.

## 8. Stage 5: Tinh do lon bien

Stage 5 tinh do lon bien xap xi bang tong hai tri tuyet doi:

```text
edge_mag_s5 = abs_gx_s4 + abs_gy_s4
```

Day la cach xap xi cua cong thuc ly thuyet:

```text
G = sqrt(Gx^2 + Gy^2)
```

Viec su dung `|Gx| + |Gy|` giup mach don gian hon, chi can cac bo cong va mach lay tri tuyet doi, khong can bo nhan binh phuong hoac mach can bac hai. Dieu nay rat phu hop voi FPGA.

## 9. Output Stage: So sanh nguong va tao pixel dau ra

O tang cuoi, module so sanh `edge_mag_s5` voi nguong `THRESHOLD`.

Neu do lon bien lon hon nguong:

```verilog
edge_pixel_out <= 16'hFFFF;
```

Pixel dau ra co mau trang, bieu thi co bien.

Neu do lon bien nho hon hoac bang nguong:

```verilog
edge_pixel_out <= 16'h0000;
```

Pixel dau ra co mau den, bieu thi khong co bien.

Dia chi pixel dau ra duoc tinh bang:

```verilog
edge_addr_out <= pixel_addr(y_s5 - 1, x_s5 - 1);
```

Ly do tru 1 o ca `x` va `y` la vi khi pixel hien tai nam o goc duoi ben phai cua cua so 3x3, ket qua Sobel thuc su thuoc ve pixel trung tam cua cua so, tuc la toa do `(x-1, y-1)`.

Doi voi cac pixel bien anh nhu `x = 0`, `x = 1`, `y = 0`, hoac `y = 1`, cua so 3x3 chua hop le day du. Vi vay, module gan pixel dau ra bang den.

## 10. Pipeline valid va toa do

Do module duoc thiet ke theo dang pipeline, du lieu pixel di qua nhieu tang xu ly. De dam bao output dung voi du lieu dang xu ly, cac tin hieu `valid`, `x`, va `y` cung duoc delay qua tung tang pipeline:

```text
valid_s1 -> valid_s2 -> valid_s3 -> valid_s4 -> valid_s5
x_s1     -> x_s2     -> x_s3     -> x_s4     -> x_s5
y_s1     -> y_s2     -> y_s3     -> y_s4     -> y_s5
```

Nho do, khi `edge_mag_s5` di den tang output, toa do `x_s5`, `y_s5` va tin hieu `valid_s5` cung den dung thoi diem. Dieu nay dam bao `edge_addr_out`, `edge_pixel_out`, va `edge_valid_out` khop voi nhau.

## 11. Ket luan

Module `sobel_edge.v` la mot thiet ke phat hien bien theo thuat toan Sobel duoc toi uu cho xu ly phan cung. Thiet ke su dung hai line buffer de luu hai dong anh truoc, cac thanh ghi dich de tao cua so 3x3, va pipeline de chia nho qua trinh tinh toan thanh nhieu tang. Cac phep tinh toan trong ly thuyet Sobel duoc anh xa thanh cac phep cong, tru, dich trai va so sanh nguong trong phan cung.

Nho kien truc pipeline, module co kha nang nhan mot pixel moi moi chu ky clock, giup tang toc do xu ly va phu hop voi cac he thong xu ly anh thoi gian thuc tren FPGA.

