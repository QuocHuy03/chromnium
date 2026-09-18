# Chronium 153.0.8010.36 — Báo cáo build & release

🔗 **Release:** https://github.com/QuocHuy03/chromnium/releases/tag/v153.0.8010.36

---

## 1. Build

| Bước | Kết quả |
|---|---|
| Cài môi trường (VS Build Tools, SDK 28000, depot_tools, Debugging Tools, ATL) | ✅ |
| Fetch Chromium 153 (~65GB + DEPS) | ✅ |
| Apply 20 patch | ✅ sạch, verify lại từ tag gốc pass ngay lần đầu |
| Build `chrome.exe` / `chrome.dll` | ✅ |
| Package `chronium.exe` | ✅ |

**5 lỗi thật phát hiện qua build thực tế** (đã vá vào `patches/*.patch`, không phải sửa tạm — build lại từ đầu vẫn ổn định):

1. `element.cc` — revert rename sai (`UpdateStyleAndLayoutForNode` không đổi tên trong 153 thật)
2. `html_canvas_element.cc` — `StaticBitmapImage::Create()` thiếu tham số `HDRMetadata` bắt buộc
3. `permissions.cc` — sửa xử lý sai kiểu `PermissionStatusWithDetailsPtr` (move-only struct)
4. `chrome/browser/BUILD.gn` — thêm `license_gate.cc/h` vào sources (thiếu gây lỗi link)
5. `scripts/package.bat` — thêm `*.manifest` vào robocopy filter (thiếu gây lỗi khởi động SxS)

## 2. Branding

- **Icon**: logo cam, nền trong suốt, patch vào cả `chrome.exe` lẫn `chrome.dll` (nơi Chromium thật sự nạp icon lúc chạy)
- **Badge `--account-label`**: pill nền đỏ + chữ trắng
- Cả 2 đã bake vào `scripts/package.bat`, tự động áp dụng mỗi lần đóng gói

## 3. Test chống fingerprint (8/8 mục)

| Vector | Kết quả |
|---|---|
| WebRTC | ✅ Không leak IP nội bộ |
| Canvas / WebGL | ✅ Noise + GPU spoof đúng theo profile |
| Fonts | ✅ Allowlist hoạt động đúng (verify bằng đo `canvas.measureText`, đối chiếu 100% khớp allowlist) |
| TLS / JA3 / JA4 | ✅ Khớp Chrome thật |
| CreepJS | ✅ Headless 0%, Stealth 0%, không bị coi là bot |
| Pixelscan | ⚠️ Báo "Timezone spoofed" — không phải bug, do thiếu proxy khớp vùng (đã có sẵn `-Proxy` flag để xử lý) |
| EFF Cover Your Tracks / amiunique | ⚠️ Báo "fingerprint unique" — chủ đích thiết kế (seed riêng mỗi profile để chống liên kết profile) |

## 4. Đóng gói & Release

- Bản phân phối chính thức qua `make-package.ps1`: 170 profile mã hóa AES-GCM (`.json.enc`), launcher `chronium.ps1`/`chronium.bat`, không cần cài đặt/admin/Python
- File: `chronium-v153.0.8010.36.zip` (~524 MB)
- Code đã push lên `QuocHuy03/chromnium` nhánh `rebase/chromium-153`

---

**Tình trạng cuối cùng:** build ổn định, tái lập được từ patch gốc, toàn bộ vector fingerprint chính đều hoạt động đúng thiết kế, đã có bản release công khai sẵn sàng tải dùng.
