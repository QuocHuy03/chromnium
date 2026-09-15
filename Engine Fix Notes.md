# Note sửa engine chronium — sau Leak Test 15/09/2026

Tài liệu cho người sửa **source engine** (Chromium 148.0.7778.217). Mọi kết luận dưới đây đều **đo trên engine thật và so với Chrome 152 gốc trên cùng máy**, bằng các cách:
- Đổi từng trường trong file vân tay JSON rồi đo bằng [`fp-probe.js`](fp-probe.js).
- Kiểm trên trang thật: BrowserLeaks, CreepJS, Pixelscan, BrowserScan.

Báo cáo đầy đủ: [`Leaktest Report.md`](Leaktest%20Report.md).

**Chia việc:**
- **Phần A:** lỗi phải sửa trong source engine.
- **Phần B:** việc trên dữ liệu mẫu vân tay (170 file `.json.enc`).
- **Phần C:** những gì backend SOAFF đã tự sửa, không cần đụng engine.

## Trạng thái sửa (cập nhật 15/09/2026)

Mã sửa engine nằm trong [`patches/0022-chronium-render-time-noise-v2-per-context-WebGL-exte.patch`](patches/0022-chronium-render-time-noise-v2-per-context-WebGL-exte.patch) và `patches/post-patched/`, trên nhánh `fix/engine-a1-a2-readpixels-audio`. **Chưa build vào engine.** Các phần mới đã được thử trên Chrome for Testing 148 thật (GTX 1060, D3D11), nhưng chưa thử trên engine.

| Mục | Trạng thái | Đã kiểm trên Chrome 148 thật |
|---|---|---|
| A7 — extension WebGL1 | 🔧 Sửa trong 0022, chờ build | Chrome 148: WebGL1 35 tên / WebGL2 32 tên, `listed_but_null = []`, `getExtension` không phân biệt hoa thường |
| A6 — nhiễu canvas | 🔧 Sửa trong 0022 (`noise.version = 2`), chờ build | Dịch + phóng chữ: mọi chuỗi và emoji đều đổi pixel; dịch nguyên 1 px không lộ |
| A2 — nhiễu audio | 🔧 Sửa trong 0022, chờ build | — |
| A1 — WebGL `readPixels` | 🔧 Sửa trong 0022 (`noise.version = 2`), chờ build | Viết lại shader: 14 ca compile/link/log lỗi y như gốc; gradient đổi 1.8k–4.7k px, quad đồng màu đổi 0 px |
| A3 — tên múi giờ | ✅ **Đã kết luận:** engine hiện tại (bản Windows) đúng; đã bỏ remap V8 khỏi `post-patched` | Chrome 148/152 gốc trả `Asia/Saigon`, `Europe/Kiev`, … |
| A4 — Chromium 152 | ❌ Chưa làm (rebase cả bộ patch, cần máy có `C:\cr\src`) | — |
| A5 — 25% like headless | ❌ Chưa điều tra trên engine | — |
| Backend `noise.version` | ✅ Đã làm ở repo `antidetect` (chưa commit), test 36/36 đạt | — |

**Lưu ý khi build:**
- File `.patch` của 0019–0021 không áp được sau 0018 (xem `patches/README.md`).
- Build Windows: chép `patches/post-patched/` vào `C:\cr\src`, chạy `rebuild-patch.bat` rồi `package.bat`.

## Thứ tự ưu tiên

| Ưu tiên | Mục | Trang bắt được | Mức sửa |
|---|---|---|---|
| 1 | **A7** — WebGL1 liệt kê sai extension | BrowserScan "WebGL exception" −5% | Dễ |
| 2 | **A6** — Nhiễu canvas bị phát hiện | BrowserScan "Canvas Tampering" −5% | Trung bình–khó |
| 3 | **A2** — Nhiễu audio bị phát hiện (backend đang tắt) | CreepJS Audio `data ≠ copy`, `trap` sai | Trung bình |
| 4 | **A1** — Nhiễu WebGL `readPixels` không có tác dụng | BrowserLeaks / CreepJS: WebGL image trùng giữa hồ sơ | Trung bình |
| 5 | **A4** — Nâng lên Chromium 152 | EFF / AmIUnique: UA hiếm | Khó |
| 6 | **A3** — Tên múi giờ | Cần kiểm chứng | Dễ |
| 7 | **A5** — CreepJS 25% like headless | CreepJS | Cần điều tra |

**Kết quả BrowserScan hiện tại** (hồ sơ mới, proxy Arizona):
- Authenticity **90%**: bị trừ WebGL exception −5% và Canvas Tampering −5%.
- Mọi mục khác đạt: múi giờ khớp IP, Proxy "No", Bot Detection toàn "Normal", WebRTC không lộ, DNS không lộ.
- Chrome 152 gốc trên cùng máy **không** bị hai lỗi này. Nó chỉ bị trừ "Different time zones" do mạng của máy thật.
- Sửa xong A6 và A7, BrowserScan dự kiến đạt 100%.

---

## A. Lỗi trong engine — cần sửa source

### A7. WebGL1 liệt kê sai danh sách extension — **ưu tiên 1**

> **Đã sửa trong 0022, chờ build.**
> - `getSupportedExtensions()` lấy danh sách thật của ngữ cảnh rồi lọc qua danh sách cho phép theo loại ngữ cảnh: `webgl.extensions` cho WebGL2, trường mới `webgl.extensions_webgl1` cho WebGL1. Mẫu không có danh sách cho loại ngữ cảnh đó thì trả danh sách thật.
> - `getExtension(name)` áp **cùng** danh sách cho phép (không phân biệt hoa thường), nên "liệt kê" luôn bằng "dùng được". Tên mà GPU thật không hỗ trợ bị loại khỏi danh sách.
> - Thứ tự giữ nguyên thứ tự đăng ký như Chrome gốc.
> - Dùng chung cho OffscreenCanvas và Worker.
> - Switch mới: `--fingerprint-webgl1-extensions`.

**Nguyên nhân:** mẫu vân tay chỉ có **một** danh sách `webgl.extensions` (32 tên, là danh sách của **WebGL2**). Engine trả danh sách này từ `getSupportedExtensions()` cho **cả WebGL1 lẫn WebGL2**. Cả 170 mẫu còn dùng chung đúng một danh sách, không theo GPU.

**Bằng chứng** (cùng máy):

| | Chrome 152 gốc | Engine |
|---|---|---|
| WebGL2 `getSupportedExtensions()` | 32 tên | 32 tên — **khớp y hệt** |
| WebGL1 `getSupportedExtensions()` | 35 tên | 32 tên (danh sách của WebGL2) |
| WebGL1: liệt kê nhưng `getExtension()` trả `null` | 0 | **13** |
| WebGL1: không liệt kê nhưng `getExtension()` vẫn dùng được | 0 | **16** |
| BrowserScan | Không có "WebGL exception" | **WebGL exception −5%**, kể cả khi mẫu trùng GPU thật (`win-gtx1060`) |

- **13 tên liệt kê nhưng null** trong WebGL1: `EXT_color_buffer_float`, `EXT_conservative_depth`, `EXT_disjoint_timer_query_webgl2`, `EXT_render_snorm`, `EXT_texture_norm16`, `NV_shader_noperspective_interpolation`, `OES_draw_buffers_indexed`, `OES_sample_variables`, `OES_shader_multisample_interpolation`, `OVR_multiview2`, `WEBGL_clip_cull_distance`, `WEBGL_provoking_vertex`, `WEBGL_stencil_texturing`.
- **16 tên bị giấu nhưng dùng được** trong WebGL1: `ANGLE_instanced_arrays`, `EXT_blend_minmax`, `EXT_disjoint_timer_query`, `EXT_frag_depth`, `EXT_shader_texture_lod`, `EXT_sRGB`, `OES_element_index_uint`, `OES_fbo_render_mipmap`, `OES_standard_derivatives`, `OES_texture_float`, `OES_texture_half_float`, `OES_texture_half_float_linear`, `OES_vertex_array_object`, `WEBGL_color_buffer_float`, `WEBGL_depth_texture`, `WEBGL_draw_buffers`.
- **Danh sách WebGL1 của Chrome 152 gốc** (NVIDIA, D3D11), để tham chiếu: `ANGLE_instanced_arrays`, `EXT_blend_minmax`, `EXT_clip_control`, `EXT_color_buffer_half_float`, `EXT_depth_clamp`, `EXT_disjoint_timer_query`, `EXT_float_blend`, `EXT_frag_depth`, `EXT_polygon_offset_clamp`, `EXT_shader_texture_lod`, `EXT_texture_compression_bptc`, `EXT_texture_compression_rgtc`, `EXT_texture_filter_anisotropic`, `EXT_texture_mirror_clamp_to_edge`, `EXT_sRGB`, `KHR_parallel_shader_compile`, `OES_element_index_uint`, `OES_fbo_render_mipmap`, `OES_standard_derivatives`, `OES_texture_float`, `OES_texture_float_linear`, `OES_texture_half_float`, `OES_texture_half_float_linear`, `OES_vertex_array_object`, `WEBGL_blend_func_extended`, `WEBGL_color_buffer_float`, `WEBGL_compressed_texture_s3tc`, `WEBGL_compressed_texture_s3tc_srgb`, `WEBGL_debug_renderer_info`, `WEBGL_debug_shaders`, `WEBGL_depth_texture`, `WEBGL_draw_buffers`, `WEBGL_lose_context`, `WEBGL_multi_draw`, `WEBGL_polygon_mode`. Chrome for Testing 148.0.7778.178 trên cùng GPU trả **đúng danh sách này** (35 tên) và 32 tên cho WebGL2, giống hệt ở canvas thường và OffscreenCanvas.

**Cần sửa** (`third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc` — `getSupportedExtensions`, `getExtension`):
- Chọn danh sách **theo loại ngữ cảnh**: WebGL2 dùng danh sách WebGL2; WebGL1 dùng danh sách WebGL1 (trường mới trong mẫu, xem B6). Nếu mẫu không có danh sách WebGL1 thì trả danh sách thật của ngữ cảnh.
- **Bất biến bắt buộc** cho mọi ngữ cảnh: tập tên trả từ `getSupportedExtensions()` phải **đúng bằng** tập tên mà `getExtension(name)` trả khác `null`. Tên nào bị giấu khỏi danh sách thì `getExtension` cũng phải trả `null`; tên nào được liệt kê mà ngữ cảnh không hỗ trợ thật thì phải loại khỏi danh sách.
- Kiểm cả `OffscreenCanvas.getContext('webgl')` và WebGL trong Worker.

**Nghiệm thu:**
- `fp-probe.js`: `webgl_ext.webgl.listed_but_null = []`, `webgl_ext.webgl.unlisted_but_available = []`; tương tự cho `webgl2`.
- BrowserScan: hết "WebGL exception".

### A6. Nhiễu canvas bị phát hiện — **ưu tiên 2**

> **Đã sửa trong 0022, chờ build.** Sửa theo "cách nên làm": nhiễu lúc **vẽ**, chỉ bật khi `noise.version = 2`.
> - Chữ (`fillText`/`strokeText`, dùng chung cho OffscreenCanvas) được vẽ với độ dịch ngang **0,25–0,45 px** và phóng/thu **0,15–0,4%** quanh điểm neo, theo seed.
> - Đo trên Chrome 148: chữ canvas bị làm tròn về pixel nguyên theo chiều dọc và về 1/4 pixel theo chiều ngang. Vì vậy độ dịch ≥ 0,25 px luôn đổi pixel, kể cả "Hi" và emoji. Phóng/thu làm chuỗi dài khác nhau liên tục giữa các hồ sơ: 6 hồ sơ thử khác nhau 15/15 cặp với chuỗi dài và emoji, 13–14/15 với chuỗi rất ngắn. Dịch neo nguyên 1 px cho cùng pixel (diff 0).
> - `noise.version = 2` **không** nhiễu lúc đọc: `getImageData`/`toDataURL`/`toBlob` đọc nguyên bitmap. Vùng đồng màu và `putImageData` giữ nguyên tuyệt đối, mọi đường đọc khớp nhau.
> - `noise.version` không có hoặc = 1: giữ cách cũ (nhiễu LSB lúc đọc) để hồ sơ đang đăng nhập không đổi hash.
> - `noise.canvas_threshold = 0` giờ **tắt** nhiễu canvas ở cả hai cách.
> - Còn lại: hình học không phải chữ (path, arc) chưa có lệch. Hash canvas vẫn khác nhau vì mọi bài test canvas phổ biến đều vẽ chữ.

**Bằng chứng:**

| Phép kiểm (`fp-probe.js`, phần tamper) | Chrome 152 gốc | Engine (mẫu rtx5070ti) | Engine (mẫu gtx1060) |
|---|---|---|---|
| Tô kín 1 màu → `getImageData`: số pixel bị đổi | 0 | **2** | **1** |
| Tô kín 1 màu → `toDataURL` → giải mã: số pixel bị đổi | 0 | 0 | 0 |
| Trang tự ghi `putImageData` → `getImageData`: số byte lệch | 0 | **3** | **4** |
| Canvas chữ: `getImageData` so với `toDataURL` đã giải mã: số byte lệch | 0 | **3** | **6** |
| OffscreenCanvas tô kín 1 màu → `getImageData`: số pixel bị đổi | 0 | **2** | **1** |
| `toDataURL` / `getImageData` `.toString()` | `[native code]` | `[native code]` | `[native code]` |

Lần đo thứ ba bằng chính [`fp-probe.js`](fp-probe.js) (mẫu rtx5070ti, hồ sơ khác) cho kết quả tô kín 3 pixel, `putImageData` lệch 8 byte, `getImageData` so với `toDataURL` lệch 6 byte, OffscreenCanvas 3 pixel. Chrome gốc vẫn 0 ở mọi phép kiểm. Mức lệch thay đổi theo seed nhưng **không bao giờ bằng 0**.

BrowserScan "Canvas Tampering −5%" **vẫn còn** ở cả 4 biến thể đã thử, trong khi Chrome gốc không bị:

| Biến thể | BrowserScan |
|---|---|
| Seed riêng từng hồ sơ (hiện tại) | Canvas Tampering −5% |
| Seed của mẫu (hồ sơ cũ) | Canvas Tampering −5% |
| `noise.canvas_threshold = 0` | Canvas Tampering −5% |
| `canvas_threshold`, `clientrects_subpixel`, `measure_text_subpixel` đều = 0 | Canvas Tampering −5% |

Thêm một lỗi phụ: **đặt `canvas_threshold = 0` không tắt được nhiễu**. Hai hồ sơ với các trường nhiễu = 0 vẫn cho hash canvas khác nhau (`CC15CAFE` và `3370DD3E`), tức engine không đọc trường này.

**Ba lỗi cụ thể:**
1. Nhiễu đánh vào **vùng đồng màu**. Chrome thật tô kín một màu thì đọc lại đúng từng pixel.
2. Nhiễu đánh vào **dữ liệu do trang tự ghi** (`putImageData` rồi đọc lại bị lệch). Đây là phép "trap" kinh điển, giống lỗi audio ở A2.
3. **Hai đường đọc không khớp nhau:** `getImageData` và `toDataURL` của cùng một canvas ra pixel khác nhau.

**Cần sửa** (tìm patch hiện tại quanh `getImageData` / `toDataURL` / `toBlob`: `third_party/blink/renderer/modules/canvas/canvas2d/base_rendering_context_2d.cc`, `third_party/blink/renderer/core/html/canvas/html_canvas_element.cc`, `third_party/blink/renderer/core/offscreencanvas/offscreen_canvas.cc`, `third_party/blink/renderer/modules/canvas/offscreencanvas2d/`):
- **Cách nên làm:** nhiễu lúc **vẽ**, không nhiễu lúc **đọc**. Engine đã có sẵn `measure_text_subpixel` / `clientrects_subpixel`; mở rộng sang lệch hình học dưới pixel theo seed cho glyph, path và cạnh khử răng cưa. Như vậy:
  - vùng đồng màu tự nhiên không đổi;
  - `putImageData` → `getImageData` khớp tuyệt đối;
  - `getImageData`, `toDataURL`, `toBlob` đọc cùng một bitmap nên luôn khớp nhau;
  - hash canvas vẫn khác nhau theo seed hồ sơ.
- **Nếu vẫn giữ nhiễu lúc đọc:**
  - Chỉ nhiễu pixel **không đồng màu với các pixel lân cận**.
  - **Không** nhiễu vùng do `putImageData` / `ImageData` / `ImageBitmap` từ dữ liệu trang tạo ra.
  - Áp **cùng một** phép biến đổi tất định cho `getImageData`, `toDataURL`, `toBlob`, `convertToBlob`, và cho cả `drawImage(canvas)` sang canvas khác, để mọi đường đọc cho cùng pixel.
- Đọc đúng `noise.canvas_threshold = 0` là **tắt**.

**Nghiệm thu:**
- `fp-probe.js` phần `tamper`: mọi giá trị `*_altered_px` và `*_diff_bytes` = **0**, giống Chrome gốc.
- `canvas_url`, `canvas_px` vẫn **khác nhau** giữa 2 hồ sơ cùng mẫu và giống nhau khi mở lại cùng hồ sơ.
- BrowserScan: hết "Canvas Tampering". BrowserLeaks Canvas: 2 hồ sơ cùng mẫu vẫn khác chữ ký.

### A1. Nhiễu WebGL `readPixels` không có tác dụng — **ưu tiên 4**

> **Đã sửa trong 0022, chờ build.** Nhiễu lúc **rasterize**, chỉ bật khi `noise.version = 2` và `noise.webgl_readpixels` không tắt.
> - Mỗi vertex shader được viết lại để `gl_Position.xy` lệch **2e-4 … 6e-4** clip space theo seed, tức khoảng 0,03–0,09 px trên canvas 300 px. Cách làm: `#define main main_vs0` + `#line` + một `main()` bọc ngoài.
> - `getShaderSource()` vẫn trả mã gốc. `#line` giữ đúng số dòng trong log lỗi.
> - Thử trên ANGLE của Chrome 148 với 14 ca (ESSL 1.00/3.00, shader một dòng, CRLF, `#ifdef`/`#extension`, nối dòng `\`, `__LINE__`, không có `main`, cố tình lỗi): trạng thái compile/link và log lỗi y như bản gốc.
> - Không nhiễu lúc đọc, nên `readPixels`, `toDataURL`, `toBlob`, `drawImage` cùng đọc một ảnh. `clearColor` và quad đồng màu phủ kín đổi **0 pixel**; tam giác gradient đổi 1.820–4.694 pixel theo seed, ổn định giữa các lần vẽ.
> - Áp cho WebGL1/WebGL2, OffscreenCanvas, Worker, cả PBO, vì lệch xảy ra trước khi ghi pixel.
> - Bản 0022 đầu tiên (lật bit `readPixels` theo vị trí) đã bị thay, vì nó làm đổi pixel nền `clearColor`.
> - **Còn lộ:** `WEBGL_debug_shaders.getTranslatedShaderSource()` sẽ thấy hàm bọc; và nếu trang ghi `gl_Position` vào transform feedback thì đọc lại sẽ thấy lệch rất nhỏ.

**Bằng chứng:**

| Biến thể (cùng máy) | `readPixels` hash | `toDataURL` của canvas WebGL |
|---|---|---|
| Mẫu rtx5070ti, seed gốc | `2038d9fb` | `b0e101e6` |
| Mẫu rtx5070ti, seed khác | `2038d9fb` | `2d4d4d6e` |
| Mẫu rtx5070ti, `noise.webgl_readpixels = false` | `2038d9fb` | `b0e101e6` |
| Mẫu rtx2070super | `2038d9fb` | `dc081a71` |
| Hồ sơ A / A2 / B với seed riêng từng hồ sơ (sau khi sửa backend) | `2038d9fb` cả ba | khác nhau cả ba |

Trên trang thật, sau khi backend đã cho mỗi hồ sơ một seed riêng:

| Trang | Hồ sơ A | Hồ sơ A2 (cùng mẫu) |
|---|---|---|
| BrowserLeaks WebGL Image Hash | `31512603D8157A55323D306CC161FB49` | **`31512603D8157A55323D306CC161FB49`** |
| CreepJS WebGL `pixels` | `5e8463b8` | **`5e8463b8`** |
| CreepJS WebGL `images` (xuất ảnh) | `20ecfc58` | `d80db8e1` ← đã khác |

**Kết luận:** đường xuất ảnh (`toDataURL`/`toBlob`) đã có nhiễu theo seed. Nhưng `readPixels` trả **pixel thật chưa qua nhiễu**, và cờ `noise.webgl_readpixels` hoàn toàn không được đọc. Hai đường đọc vì vậy **không khớp nhau** — cùng loại lỗi với A6.

**Cần sửa** (`third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc` — `readPixels` / `ReadPixelsHelper`; các overload WebGL2 trong `webgl2_rendering_context_base.cc`):
- Làm **theo cùng nguyên tắc với A6**: ưu tiên lệch lúc rasterize; nếu nhiễu lúc đọc thì `readPixels` và `toDataURL`/`toBlob` của cùng canvas phải cho cùng pixel.
- Không nhiễu vùng đồng màu. Hiện `clearColor` đọc lại vẫn đúng (0 pixel bị đổi) — giữ nguyên như vậy.
- Áp cho cả WebGL2 (PBO, overload có offset), `OffscreenCanvas` và Worker.
- Đọc đúng cờ `noise.webgl_readpixels`.

**Nghiệm thu:**
- `fp-probe.js`: `webgl_readpixels` khác nhau giữa 2 hồ sơ, giống nhau khi mở lại cùng hồ sơ; `webgl_readpixels_stable = true`; `tamper.webgl1_solid_readpixels_altered_px = 0`.
- BrowserLeaks WebGL Image Hash và CreepJS `pixels` khác nhau giữa 2 hồ sơ cùng mẫu; CreepJS không "lies" ở WebGL.

### A2. Nhiễu audio bị phát hiện — **ưu tiên 3** (backend đang phải TẮT)

> **Đã sửa trong 0022, chờ build.** Áp cho mọi phiên bản nhiễu, vì audio đang tắt ở mọi hồ sơ nên không hồ sơ nào bị đổi hash.
> - Bỏ nhiễu lúc đọc trong `AudioBuffer::getChannelData`. Nhiễu áp **một lần** lên buffer đã render trong `OfflineAudioContext::FireCompletionEvent`, trước `oncomplete` và trước khi resolve promise. Kết quả: `data` = `copy`; buffer JS tự tạo không bị đụng nên `trap` đúng.
> - `audio_amplitude` giờ là độ lớn thật (kẹp vào [0, 1e-2]). Nên dùng 1e-6 … 1e-4; dưới ~2e-7 float32 làm tròn mất.
> - `AnalyserNode`: nhân theo amplitude, tắt khi = 0, không đụng im lặng.
> - Backend **vẫn để tắt** cho tới khi nghiệm thu đạt trên engine đã build.

**Bằng chứng trên CreepJS**, mục Audio, hồ sơ mẫu `win-rtx5070ti`:

| Chỉ số | Nhiễu tắt (`audio_amplitude = 0`) | Nhiễu bật (hồ sơ A) | Nhiễu bật (hồ sơ A2) |
|---|---|---|---|
| `sum` | `124.04347527516074` | `124.04346469801385` | `124.04347885827883` |
| `data` (`getChannelData`) | `3d5e3923` | **`57d6594c`** | **`69feb705`** |
| `copy` (`copyFromChannel`) | `3d5e3923` | **`3d5e3923`** | **`3d5e3923`** |
| `trap` | `0.7284930725495119` | **`972.3414127174644`** | **`990.5785494430844`** |

Lỗi thứ hai là **độ lớn** (cùng seed):

| `audio_amplitude` | Audio sum |
|---|---|
| 0 | `124.04347527516074` |
| 1e-6 | `124.04346707577497` |
| 1e-3 | `124.04346707577497` ← **giống hệt 1e-6** |

**Ba lỗi cụ thể:**
1. **`getChannelData` bị nhiễu nhưng `copyFromChannel` thì không.** Hash `data` khác `copy` là bằng chứng giả mạo rõ ràng. Khi nhiễu tắt, hai hash này bằng nhau.
2. **Nhiễu bị áp lên cả buffer do trang tự tạo và tự ghi.** Phép "trap" của CreepJS ghi giá trị đã biết vào `AudioBuffer` rồi đọc lại; kết quả đúng là `0.728`, còn engine trả `972`/`990`.
3. **`audio_amplitude` chỉ là bật/tắt**, độ lớn không có tác dụng.

**Cần sửa** (`third_party/blink/renderer/modules/webaudio/audio_buffer.cc` và nơi render `OfflineAudioContext`):
- Chỉ nhiễu **dữ liệu do engine render ra** (đầu ra `OfflineAudioContext.startRendering`, `AnalyserNode`), **áp một lần lúc render xong**, rồi mọi đường đọc (`getChannelData`, `copyFromChannel`, `AnalyserNode.getFloat/ByteFrequencyData`, `getFloat/ByteTimeDomainData`) đều đọc cùng dữ liệu đã nhiễu.
- **Không** nhiễu khi đọc (read-time); **không** nhiễu `AudioBuffer` do JS tạo bằng `new AudioBuffer`/`createBuffer` rồi ghi bằng `copyToChannel` hay `getChannelData()[i] = …`.
- Nhân độ lệch với `audio_amplitude`.

**Nghiệm thu:**
- CreepJS Audio: `data` = `copy`; `trap` = `0.7284930725495119` (bằng giá trị khi tắt nhiễu); `sum` khác nhau giữa 2 hồ sơ, giống nhau khi mở lại cùng hồ sơ.
- `fp-probe.js`: `audio_copy_matches = true`, `audio_stable = true`.
- **Sau khi đạt**, bật lại nhiễu audio ở backend: trong `chronium_engine._materialize_patched_profile` đặt `noise.audio_amplitude` khác 0 khi có `profile_id`.

### A3. Tên múi giờ trả về cho JS — **đã kiểm chứng**

> **Kết luận: engine Windows hiện tại đúng, không cần sửa.** Đã bỏ hai remap V8 khỏi `post-patched`, vì chính chúng làm lệch khỏi Chrome thật.
>
> Đo bằng Chrome for Testing **148.0.7778.178** (CfT không có bản .217) và Chrome **152.0.7977.83** gốc, qua CDP `Emulation.setTimezoneOverride` (cùng đường với patch 0010). Hai bản cho kết quả **giống hệt nhau**:
>
> | Đầu vào | `resolvedOptions().timeZone` |
> |---|---|
> | Asia/Ho_Chi_Minh | **Asia/Saigon** |
> | Asia/Kolkata | **Asia/Calcutta** |
> | Europe/Kyiv | **Europe/Kiev** |
> | America/Argentina/Buenos_Aires | **America/Buenos_Aires** |
> | Asia/Yangon | **Asia/Rangoon** |
> | Asia/Kathmandu | **Asia/Katmandu** |
> | America/Phoenix, America/New_York, Asia/Bangkok | giữ nguyên |
>
> - Chrome thật trả **tên cũ**. Commit V8 `34972cf` (đổi sang tên mới) và `0e989a2` (`vi` → `vi-VN` cho `Intl`) chỉ nằm trong `post-patched`, chưa từng vào bản build Windows. Cả hai làm engine **khác** Chrome thật, nên đã xoá khỏi `post-patched`.
> - Locale: Chrome 148 với `--lang=vi-VN` cho `navigator.language = vi-VN` nhưng `Intl` locale = **`vi`**, giống bản Windows hiện tại.
> - Múi "SE Asia Standard Time" ra `Asia/Bangkok` là cách ICU chọn tên khi vị trí địa lý của Windows không phải Việt Nam. Theo bảng `windowsZones` của CLDR, Windows đặt vị trí VN sẽ ra `Asia/Saigon`, tức khớp với hồ sơ proxy VN hiện tại (điểm này là suy luận từ cách ICU hoạt động, chưa đo trên máy đặt vị trí VN). Vì vậy **không nên** ép backend đổi sang `Asia/Bangkok`.

- **Hiện tượng:** cấu hình `timezone = "Asia/Ho_Chi_Minh"` thì `Intl.DateTimeFormat().resolvedOptions().timeZone` trả `"Asia/Saigon"` (tên cũ theo chuẩn ICU). Múi `America/Phoenix` trả đúng như cấu hình.
- Chrome 152 gốc trên Windows đặt múi "SE Asia Standard Time" trả `"Asia/Bangkok"` (tên CLDR chính của múi Windows đó).
- **Cần kiểm tra:**
  1. Chrome 148 gốc trả `Asia/Saigon` hay `Asia/Ho_Chi_Minh`. Engine phải trả **y như Chrome gốc cùng phiên bản**. → **Đã kiểm: `Asia/Saigon`.**
  2. Với vân tay Windows: Chrome thật trên Windows chỉ trả tên IANA chính của **múi Windows** (người dùng ở Việt Nam trên Windows → `Asia/Bangkok`). Việc chuẩn hóa này có thể làm ở backend (bảng IANA → múi Windows → IANA chính); ghi ở đây để engine không chuẩn hóa chồng lên. → **Xem kết luận ở trên: tên còn phụ thuộc vị trí địa lý của Windows.**

### A4. Phiên bản Chromium cũ

> **Chưa làm.** Phải rebase cả bộ patch trên máy có `C:\cr\src`: 0001–0018 dạng `.patch`, còn 0019–0021 và 0022 lấy từ `post-patched`. Lấy lại danh sách extension WebGL1/WebGL2 từ Chrome 152 gốc sau khi rebase.

- Engine là **148.0.7778.217**, trong khi Chrome ổn định trên cùng máy đã là **152.0.7977.83**.
- UA 148 hiếm nên dễ nhận ra: EFF 9,44 bit (1/696 trình duyệt), AmIUnique 0,42%.
- **Cần làm:** rebase patch lên Chromium 152 ổn định. Sau khi build, kiểm tra các trường phiên bản trong mẫu (`user_agent`, `user_agent_data`, full version list) **khớp với binary**. Nếu mẫu vẫn ghi 148 trong khi binary là 152, bộ dò tính năng JS (CreepJS "Features") sẽ thấy lệch.
- Khi rebase: danh sách extension WebGL1/WebGL2 của Chrome 152 (A7) có thể khác 148 — lấy lại từ Chrome gốc cùng phiên bản. (Trên GTX 1060 / D3D11, Chrome 148.0.7778.178 và 152.0.7977.83 cho danh sách giống hệt nhau.)

### A5. CreepJS "25% like headless" — nên điều tra

> **Chưa điều tra trên engine.** Cần mở mục Headless của CreepJS trên engine và trên Chrome gốc cùng máy rồi so. Một nghi vấn từ dữ liệu mẫu: `screen.avail_height = height` (không có taskbar).

- Không lỗi nặng: 0% headless, 0% stealth; BrowserScan Bot Detection toàn "Normal".
- CreepJS vẫn chấm 25% "like headless" ở mọi hồ sơ, trước và sau khi sửa.
- Nên mở mục Headless của CreepJS xem tín hiệu nào bị bật (quyền notification, `chrome` object, plugins, …), so với Chrome gốc cùng máy, rồi vá cho giống.

---

## B. Dữ liệu mẫu vân tay (không phải lỗi engine, nên làm lại khi build mẫu)

Engine **đọc đúng** các trường dưới đây. Đã kiểm: `speech.voices[].is_default`, `languages`, `seed` và `fonts` đều có tác dụng; engine chỉ để lộ font nằm trong danh sách, ví dụ Candara có trên máy nhưng bị ẩn. Vấn đề nằm ở **nội dung** dữ liệu:

| # | Vấn đề trong 170 mẫu | Đề xuất khi làm lại mẫu |
|---|---|---|
| B1 | 120 mẫu Windows **dùng chung 1 danh sách 18 font** (Mac 1 danh sách, Linux 1 danh sách) | Nhiều bộ font Windows thực tế: bản sạch, có Office, có gói ngôn ngữ Á… Chỉ dùng font thường có trên Windows thật |
| B2 | 120 mẫu Windows mang **giọng đọc của Windows tiếng Nga** (Irina, Pavel, mặc định ru-RU) | Để voices trung tính; backend đã tự thay theo ngôn ngữ hồ sơ (C4) |
| B3 | Mọi mẫu `locale = pl-PL`, `timezone = Europe/Warsaw` | Không ảnh hưởng (backend ghi đè), nhưng nên để trung tính |
| B4 | Mọi tham số `noise` giống hệt nhau ở 170 mẫu; `audio_amplitude = 0` | Giữ 0 cho tới khi xong A2 |
| B5 | Tên mẫu `win-gt*`, `win-vega*`, `win-arc` không khớp bảng tiền tố GPU | Backend đã sửa (C5); khi thêm mẫu mới giữ tiền tố `win-rtx / win-gt / win-rx / win-vega / win-radeon / win-amd / win-intel / win-hd / win-uhd / win-iris / win-arc` |
| B6 | **Chỉ có 1 danh sách `webgl.extensions`** (của WebGL2), và **giống hệt nhau ở cả 170 mẫu** | Thêm danh sách riêng cho WebGL1 — engine 0022 đọc trường **`webgl.extensions_webgl1`** — và lấy danh sách thật **theo từng dòng GPU / backend (D3D11, Metal, Vulkan)** từ Chrome gốc cùng phiên bản engine (A7). Chưa có trường này thì WebGL1 trả danh sách thật của GPU máy chạy: khớp nhau, nhưng là của GPU thật chứ không phải GPU trong mẫu |
| B7 | `screen.avail_height` = `height` (ví dụ `win-rtx5070ti`: 1440 / 1440) → "không có taskbar", nghi là một tín hiệu "like headless" (A5) | Windows thật: `avail_height` nhỏ hơn `height` đúng chiều cao taskbar (thường 40–48 px CSS) |

---

## C. Backend SOAFF đã tự sửa (repo `antidetect`, không cần đụng engine)

| # | Sửa | File | Kiểm chứng trên engine thật |
|---|---|---|---|
| C1 | **Múi giờ và tọa độ theo IP thật** (trường `timezone`, `lat`, `lon` của ip-api) thay vì mỗi nước một thành phố | `routes/handlers_profile.py` — `_detect_geo`, `_resolve_regional_overrides` | Proxy Arizona: trước `America/New_York` (Pixelscan "Timezone spoofed"); sau **`America/Phoenix`**, giờ JS = giờ IP → **hết lỗi** (Pixelscan, BrowserScan) |
| C2 | `navigator.languages` không lặp; `Accept-Language` sinh từ cùng danh sách, đúng cách Chrome làm | `engine/chronium_engine.py` — `_navigator_languages`, `_accept_language` | `["en-US","en"]` + `en-US,en;q=0.9` |
| C3 | **Seed nhiễu riêng từng hồ sơ** = sha256(seed mẫu : id hồ sơ) | `chronium_engine._materialize_patched_profile` | BrowserLeaks Canvas A `BCC98406…` ≠ A2 `0C7EE0B8…`; CreepJS FP A ≠ A2; mở lại ra giống hệt |
| C4 | Giọng đọc theo ngôn ngữ: vân tay Windows dùng giọng Microsoft của ngôn ngữ hồ sơ | `chronium_engine._localize_voices` | CreepJS: default Microsoft David (en-US), local (3) |
| C5 | Bảng tiền tố GPU gồm đủ GT / Vega / Arc (NVIDIA 47→51, AMD 29→34, Intel 34→35) | `chronium_engine._PROFILE_VENDOR_PREFIXES` | Unit test |
| C6 | **`noise.version = 2` cho hồ sơ chưa từng mở** (chưa có `Local State`); khi khoá mẫu ghi cờ `shardx_noise_version = 2`, cờ đi theo hồ sơ. Hồ sơ đã dùng giữ cách cũ | `chronium_engine.launch_chronium`, `_materialize_patched_profile`; `handlers_profile._lock_fingerprint` | Unit test 36/36 (`backend/tests/test_fingerprint_consistency.py`); **chưa commit** |
| — | Nhiễu audio: **tạm để tắt** vì engine bị phát hiện (A2) | `chronium_engine._materialize_patched_profile` (comment) | CreepJS `trap` về đúng `0.728` |

**Lưu ý C3 — không làm hỏng tài khoản đang đăng nhập:**
- Seed riêng **chỉ bật cho hồ sơ chưa từng mở** (thư mục hồ sơ chưa có `Local State`).
- Khi khóa mẫu, backend ghi thêm cờ `shardx_noise_per_profile` vào cấu hình; cờ đi theo hồ sơ lên cloud và sang máy khác.
- Hồ sơ đã dùng giữ nguyên seed của mẫu, nên Gmail không thấy "thiết bị đổi".
- Đổi lại, các hồ sơ **cũ** trùng mẫu vẫn còn trùng canvas với nhau.
- **Khi sửa A6/A1:** đổi cách nhiễu sẽ làm hash canvas / WebGL của **mọi** hồ sơ đổi một lần, kể cả hồ sơ đang đăng nhập. Nếu muốn giữ hồ sơ cũ ổn định, cho engine một cờ phiên bản nhiễu trong JSON (ví dụ `noise.version`) để backend chỉ bật cách mới cho hồ sơ mới, giống cờ `shardx_noise_per_profile`. → **Đã làm (C6).** Riêng A7 (danh sách extension WebGL) không đi theo phiên bản: hồ sơ cũ cũng sẽ thấy danh sách WebGL1 mới sau khi cập nhật engine.

---

## D. Cách kiểm lại sau khi build engine mới

1. Tạo 2 hồ sơ mới **cùng mẫu** (ví dụ `win-rtx5070ti`) và 1 hồ sơ mẫu khác; tất cả dùng cùng proxy.
2. Trên mỗi hồ sơ, mở `https://example.com`, dán [`fp-probe.js`](fp-probe.js) vào Console. Mở lại hồ sơ đầu tiên và chạy thêm một lần. Chạy cả trên Chrome gốc cùng máy để có mốc so.
3. Kỳ vọng:

| Trường | Cùng hồ sơ, mở lại | 2 hồ sơ cùng mẫu | Trạng thái hiện tại |
|---|---|---|---|
| `canvas_url`, `canvas_px` | Giống | **Khác** | ✅ Đạt |
| `tamper.*_altered_px`, `tamper.*_diff_bytes` | = 0 | = 0 | 🔧 **A6** — 0022 (`noise.version = 2`), chờ build |
| `webgl_ext.webgl.listed_but_null`, `unlisted_but_available` | `[]` | `[]` | 🔧 **A7** — 0022, chờ build |
| `webgl_ext.webgl2.*` | `[]` | `[]` | ✅ Đạt |
| `webgl_url` | Giống | **Khác** | ✅ Đạt |
| `webgl_readpixels` | Giống | **Khác** | 🔧 **A1** — 0022 (`noise.version = 2`), chờ build |
| `audio_sum` | Giống | **Khác** | 🔧 **A2** — 0022, chờ build; đạt thì bật lại ở backend |
| `*_stable`, `audio_copy_matches` | `true` | `true` | ✅ |
| `languages` | Không lặp | | ✅ Đạt |
| `voice_default` | Theo ngôn ngữ hồ sơ | | ✅ Đạt |
| `timezone` | Khớp IP proxy | | ✅ Đạt; A3 đã kết luận đúng như Chrome gốc |
| `ua_full_version` | Khớp binary | | A4 |

**Chú ý:** A6 và A1 chỉ có tác dụng với hồ sơ **tạo mới sau khi cập nhật backend** (có `noise.version = 2`). Hồ sơ cũ vẫn dùng cách cũ, nên vẫn bị "Canvas Tampering".

4. Chạy lại trên trang thật, tối thiểu:
   - **BrowserScan:** authenticity 100%, không "WebGL exception", không "Canvas Tampering".
   - BrowserLeaks Canvas / WebGL: 2 hồ sơ cùng mẫu phải khác nhau.
   - **CreepJS Audio:** `data` = `copy`, `trap` = `0.7284930725495119`.
   - CreepJS: không "lies" ở WebGL / Canvas.
   - Pixelscan: không còn "Timezone spoofed". "Proxy detected" thì phụ thuộc loại proxy.
