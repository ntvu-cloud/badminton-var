# 🏸 BadmintonVAR - Trợ Lý VAR Soi Vạch Cầu Lông 240 FPS Cho iPhone

Ứng dụng iOS chuyên dụng hỗ trợ xác định cầu chạm vạch (**IN**) hay ra ngoài (**OUT**) bằng camera tốc độ cao **240 khung hình/giây (240 FPS)** trên **iPhone 15 Pro** và **iPhone 11**.

---

## 🌟 Tính Năng Nổi Bật

* **Camera Siêu Chậm 240 FPS**: Bắt trọn từng mili-giây khoảnh khắc chóp đế cầu tiếp xúc với mặt sàn, không bị mất frame như camera thông thường.
* **Bộ Đệm Vòng Thông Minh (Rolling Buffer 6–8s)**: Quay liên tục nhưng chỉ lưu vài giây gần nhất vào bộ đệm. Không sợ đầy bộ nhớ, không làm nóng máy khi đặt cả buổi trên sân.
* **Nút Bấm CHALLENGE 1 Chạm**: Khi có pha cầu tranh chấp, chỉ cần bấm nút Challenge lớn trên màn hình, app lập tức chốt đoạn video và chuyển sang màn hình phân tích VAR.
* **Bộ Tua Từng Khung Hình (Frame-by-Frame Scrubber)**:
  * Tua tiến/lùi chính xác từng **1 khung hình (1/240 giây = 4.16ms)**.
  * Tùy chọn tốc độ xem lại cực chậm: `0.05x`, `0.1x`, `0.25x`, `0.5x`, `1.0x`.
* **Kính Lúp Kỹ Thuật Số (Zoom Loupe 2x - 12x)**: Phóng to tối đa trực diện vào mép vạch 40mm kèm tâm ngắm chữ thập.
* **Thước Đo Vạch Ảo Tiêu Chuẩn 40mm**: Cho phép căn chỉnh vạch mép trong và mép ngoài của sân để đối chiếu điểm chạm.
* **Đóng Dấu & Lưu Bằng Chứng**: Đóng dấu phán quyết **IN (TRONG SÂN)** hoặc **OUT (NGOÀI SÂN)** và lưu ảnh chụp khoảnh khắc tiếp đất vào Thư viện ảnh iPhone.

---

## 🚀 Hướng Dẫn Build & Cài Lên iPhone Từ Máy Tính Windows

Bạn **KHÔNG CẦN máy Mac**. Dự án đã tích hợp sẵn kịch bản tự động build file `.ipa` qua máy ảo macOS của **GitHub Actions**.

### BƯỚC 1: Đẩy Mã Nguồn Lên GitHub Của Bạn

1. Mở Terminal (PowerShell hoặc Git Bash) tại thư mục `d:\caulong`.
2. Tạo 1 repository mới trên GitHub cá nhân (đặt tên ví dụ: `badminton-var`).
3. Chạy các lệnh sau để đẩy code lên:
   ```bash
   git add .
   git commit -m "Khoi tao ung dung BadmintonVAR 240fps"
   git branch -M main
   git remote add origin https://github.com/<TEN-GITHUB-CUA-BAN>/badminton-var.git
   git push -u origin main
   ```

---

### BƯỚC 2: Tải File Cài Đặt `.ipa` Từ GitHub Actions

1. Sau khi `git push`, vào trang GitHub repo của bạn trên trình duyệt.
2. Bấm vào tab **Actions** ở menu trên cùng.
3. Bạn sẽ thấy tiến trình build **"Build iOS BadmintonVAR (IPA)"** đang chạy tự động bằng máy chủ macOS của GitHub (thường mất khoảng 2 - 3 phút).
4. Khi quá trình hoàn tất (hiện dấu tích xanh ✅):
   * Bấm vào tên lần chạy đó.
   * Kéo xuống mục **Artifacts** ở dưới cùng.
   * Bấm tải file **`BadmintonVAR-iPhone`** về máy tính Windows.
   * Giải nén file `.zip` vừa tải về, bạn sẽ nhận được file **`BadmintonVAR.ipa`**.

---

### BƯỚC 3: Cài App Vào iPhone 15 Pro / iPhone 11 Bằng Sideloadly (Miễn Phí)

**Sideloadly** là công cụ cài app iOS phổ biến nhất trên Windows, sử dụng chính Apple ID miễn phí của bạn.

1. **Tải Sideloadly**: Truy cập [sideloadly.io](https://sideloadly.io) và tải phiên bản cho Windows (cài đặt thêm iTunes/iCloud cho Windows nếu Sideloadly yêu cầu).
2. **Kết nối iPhone**: Cắm cáp sạc nối iPhone với máy tính Windows (Mở khóa màn hình iPhone và chọn **Tin cậy máy tính này / Trust this computer**).
3. **Mở Sideloadly**:
   * Mục **iDevice**: Sẽ tự động hiện tên iPhone của bạn.
   * Kéo thả file **`BadmintonVAR.ipa`** vào khung biểu tượng bên trái của Sideloadly.
   * Mục **Apple ID**: Nhập email tài khoản Apple ID (iCloud) cá nhân của bạn.
   * Bấm nút **Start**.
4. Chờ khoảng 1 phút đến khi hiện chữ **Done**. Ứng dụng **Badminton VAR** sẽ xuất hiện ngay trên màn hình chính của iPhone!

---

### BƯỚC 4: Kích Hoạt Quyền Nhà Phát Triển Trên iPhone (Chỉ Làm 1 Lần Đầu)

Đối với iOS 16, 17, 18 trên iPhone 15 Pro / iPhone 11:
1. Mở **Cài đặt (Settings)** trên iPhone ➔ **Quyền riêng tư & Bảo mật (Privacy & Security)**.
2. Kéo xuống dưới cùng, chọn **Chế độ nhà phát triển (Developer Mode)** ➔ Bật **BẬT (ON)** ➔ iPhone sẽ yêu cầu khởi động lại máy.
3. Sau khi khởi động lại, vào lại **Cài đặt (Settings)** ➔ **Cài đặt chung (General)** ➔ **Quản lý VPN & Thiết bị (VPN & Device Management)**.
4. Bấm vào tài khoản Apple ID của bạn và chọn **Tin cậy (Trust)**.
5. Xong! Bây giờ bạn có thể mở app **Badminton VAR** và sử dụng bình thường.

---

## 🎯 Hướng Dẫn Đặt Máy Thực Chiến Trên Sân Cầu Lông

1. **Chân đế (Tripod)**: Gắn iPhone lên tripod cao khoảng 40cm - 80cm, đặt cách góc sân khoảng 1.5m - 2m.
2. **Góc máy**: Hướng camera chéo góc 30° - 45° vào góc vạch giao cắt giữa vạch biên và vạch đáy.
3. **Lấy nét**: Chạm nhẹ ngón tay vào mép vạch trên màn hình để camera khóa nét (Lock Focus) vào mặt sân.
4. **Chống nhòe (Shutter Speed)**: 
   * Bấm biểu tượng 3 thanh gạt cài đặt ở góc trên.
   * Bật **Khóa màn trập nhanh thủ công**.
   * Kéo lên mức **1/500s** hoặc **1/1000s** (nếu nhà thi đấu đủ sáng). Ở tốc độ này, quả cầu dù đập bay nhanh cỡ nào khi rơi chạm đất cũng sẽ dừng hình sắc nét 100%, không hề bị bóng ma hay nhòe hình.
