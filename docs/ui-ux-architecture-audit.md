# Audit UI/UX dan Perencanaan Arsitektur Navigasi

**Status dokumen:** Audit dan rekomendasi saja — belum menjadi persetujuan desain atau instruksi implementasi.
**Branch yang diperiksa:** `arena/02828d01-cybersecurity-assistant`
**HEAD saat audit:** `88ad0e1e6745972e81198a8e2c1400746347b2c1`
**Tanggal:** 2026-11-23
**Batas audit:** Membaca kode dan dokumentasi yang ada; tidak mengubah kode aplikasi, database, Tool Registry, atau Orchestrator.

## 1. Ringkasan eksekutif

Aplikasi saat ini adalah fondasi Flutter local-first dengan empat tab utama, satu pintasan Assistant di tengah bottom navigation pada layar sempit, satu area Assessment/Tool Catalog, dan satu layar Reports yang menggabungkan Reports, Findings, serta Activity Timeline. Settings menjadi pintu ke Connections dan Diagnostics. Data nyata yang tersedia mencakup hasil pemeriksaan lokal, findings, activity events, dan status readiness tool/runtime; data itu disimpan atau dimuat melalui repository lokal.

Arah visual saat ini sudah memiliki dasar yang sesuai untuk konsep futuristik: latar ink/navy, panel gelap, aksen mint dan biru, cards, serta splash vector beranimasi. Namun Dashboard **belum** memiliki Digital Earth, Security Score, Risk gauge, Security Radar, atau grafik Analytics. Tidak ada sumber data topologi jaringan yang dapat mendukung globe ber-node; indikator konektivitas yang ada hanya petunjuk Wi-Fi, bukan bukti koneksi internet atau peta jaringan. Karena itu, visual baru harus memiliki keadaan idle yang jujur dan tidak boleh menggambar aktivitas fiktif.

**Kesimpulan navigasi:** pertahankan empat destinasi bottom navigation yang sudah ada sebagai kerangka utama. Rencanakan Floating Edge Panel sebagai lapisan pintasan sekunder di dalam aplikasi, bukan sebagai pengganti tab. Sebelum rancangan disetujui, jangan mengubah implementasi.

## 2. Metode dan bukti kode

Audit dilakukan pada `apps/android/lib/main.dart`, widget di `apps/android/lib/widgets/`, core data/runtime, `pubspec.yaml`, serta blueprint dokumentasi. Aplikasi menggunakan `MainShell` dan `setState` untuk state layar; navigasi tab memakai indeks lokal dan beberapa halaman sekunder dibuka dengan `Navigator.push`.

- `MainShell` memiliki repository hasil, Activity, Findings, dan Market; memuat data setelah frame awal: [main.dart](../apps/android/lib/main.dart#L202-L245).
- Konfigurasi SQLite saat ini adalah versi 4, dengan tabel reports, activity events, dan security findings: [local_result_store.dart](../apps/android/lib/core/local_result_store.dart#L31-L43).
- Ketergantungan Flutter saat ini tidak mencakup library charting atau state-management khusus: [pubspec.yaml](../apps/android/pubspec.yaml#L7-L25). Ini konsisten dengan tidak ditemukannya komponen grafik di halaman yang diaudit.
- Blueprint AI dan Embedded Runtime yang ada secara eksplisit berstatus konseptual, bukan implementasi: [AI blueprint](ai-cybersecurity-expert-engine.md), [Embedded Runtime blueprint](embedded-runtime-implementation.md).

## 3. Halaman dan status fitur

| Halaman/fitur | Status berdasarkan kode | Lokasi dan catatan |
|---|---|---|
| Dashboard | **Tersedia** | `DashboardScreen`; menampilkan metrik jumlah entri Registry, pemeriksaan sesi, jumlah report tersimpan, tiga hasil terbaru, dan kartu Assistant. Data yang ditampilkan bukan skor keamanan. [main.dart](../apps/android/lib/main.dart#L953-L1045) |
| Security Assessment | **Tersedia** | `AssessmentRunner`; memilih pemeriksaan yang ready, meminta target/otorisasi, menjalankan pemeriksaan secara berurutan, dan menampilkan outcome completed/failed/skipped/cancelled. [assessment_runner.dart](../apps/android/lib/widgets/assessment_runner.dart#L12-L100) |
| Tool Catalog / calon “My Tools” | **Tersedia, cakupan terbatas** | Sub-view `Tool catalog` menampilkan empat entri P0 Registry dan status readiness dinamis. Belum ada koleksi/favorit atau halaman “My Tools” terpisah. [main.dart](../apps/android/lib/main.dart#L2187-L2416); [tool_registry.dart](../apps/android/lib/core/tool_registry.dart#L101-L163) |
| Findings | **Tersedia** | Disimpan melalui `FindingRepository`, bisa difilter dan statusnya diperbarui. Ditampilkan sebagai segmen di Reports, bukan halaman utama tersendiri. [main.dart](../apps/android/lib/main.dart#L405-L443), [main.dart](../apps/android/lib/main.dart#L1311-L1376) |
| Reports | **Tersedia** | Hasil sesi dan riwayat tersimpan lokal; ada ekspor JSON serta kontrol hapus. Data tersimpan di app-private SQLite dan UI menyatakan tidak terenkripsi/tidak disinkronkan. [main.dart](../apps/android/lib/main.dart#L1311-L1450) |
| Activity Timeline | **Tersedia** | Memuat hingga 500 event, dengan filter waktu, target, kind, tool, dan status. Berada di segmen Activity dalam Reports. [main.dart](../apps/android/lib/main.dart#L491-L538), [main.dart](../apps/android/lib/main.dart#L1311-L1450) |
| Market | **Tersedia, katalog demonstrasi terbatas** | Dibuka dari Tool Catalog. Katalog berisi contoh data dan preview kategori; package terpasang tidak otomatis menjadi adapter/tool executable. Bukan store dengan ratusan tool. [main.dart](../apps/android/lib/main.dart#L265-L269), [package_manager.dart](../apps/android/lib/core/package_manager.dart#L792-L905), [Market guide](android-market-package-manager.md) |
| Connections | **Tersedia, prototipe** | Layar memiliki uji keterjangkauan endpoint HTTPS serta panduan provider. Konektor provider terautentikasi belum diimplementasikan. [main.dart](../apps/android/lib/main.dart#L2479-L2515), [provider_registry.dart](../apps/android/lib/core/provider_registry.dart) |
| Settings | **Tersedia** | Bahasa, AI & models, Connections, Diagnostics, serta informasi privasi/penyimpanan. [main.dart](../apps/android/lib/main.dart#L1927-L2018) |
| AI Cybersecurity Expert | **Placeholder** | Assistant secara eksplisit menyatakan AI/provider belum terhubung dan tidak mengirim pesan ke provider. Bukan expert engine aktif. [main.dart](../apps/android/lib/main.dart#L2424-L2477) |
| Knowledge Base | **Belum menjadi fitur layar/retrieval** | Ada satu knowledge pack JSON yang dapat dipasang sebagai data melalui Market; tidak ada halaman pencarian/retrieval knowledge base. [package_manager.dart](../apps/android/lib/core/package_manager.dart#L858-L879) |
| Runtime Manager | **Core lifecycle tersedia, UI pengelolaan belum ada** | Ada `RuntimeManager` untuk adapter/runtime yang disetujui. Tidak ditemukan halaman pengguna khusus untuk mengelola runtime. [runtime_manager.dart](../apps/android/lib/core/runtime_manager.dart) |
| Terminal | **Belum diimplementasikan** | Tidak ada halaman terminal atau shell executor. Blueprint menyatakan runtime/terminal masih konseptual. [Embedded Runtime blueprint](embedded-runtime-implementation.md) |
| Diagnostics | **Tersedia sebagai layar sekunder** | Dibuka dari Settings; bukan destinasi utama bottom navigation. [main.dart](../apps/android/lib/main.dart#L271-L275), [diagnostics_screen.dart](../apps/android/lib/widgets/diagnostics_screen.dart) |

## 4. Audit navigasi saat ini

### 4.1 Bottom Navigation — wajib dipertahankan

Pada lebar kurang dari 760 logical pixels, tab saat ini adalah **Home, Assessment, Reports, Settings**; di tengah ada pintasan Assistant. Daftar halaman dan indeks berada di [main.dart](../apps/android/lib/main.dart#L623-L687), implementasi bottom bar di [main.dart](../apps/android/lib/main.dart#L749-L810).

Pada lebar 760 logical pixels atau lebih, `bottomNavigationBar` bernilai `null` dan empat destinasi tampil sebagai `NavigationRail` ([main.dart](../apps/android/lib/main.dart#L722-L745)). Ini masih mempertahankan fungsi empat destinasi, tetapi **bottom bar literal tidak tampil pada layout lebar**. Karena arahan produk meminta Bottom Navigation tetap dipertahankan, rancangan berikutnya harus mempertahankan bottom bar sebagai kontrol primer. Jika kelak ingin menambah rail pada tablet, rail hanya boleh menjadi tambahan yang disetujui, bukan pengganti bottom navigation.

### 4.2 Pengelompokan dan akses fitur

- Assessment dan Tool Catalog berbagi destinasi Assessment melalui segmented control.
- Reports, Findings, dan Activity Timeline berbagi satu layar Reports dengan segmented control tiga bagian.
- Market diakses dari Tool Catalog; Connections dan Diagnostics dari Settings; Assistant dari pintasan tengah, kartu Dashboard, dan Settings.
- Tidak ada halaman “More” atau peta navigasi terpusat; halaman sekunder dibuat lewat callback `Navigator.push` (`_openMarket`, `_openConnections`, `_openAssistantModule`).

Pengelompokan Reports mengurangi jumlah tab, tetapi membuat Findings dan Activity tidak terlihat sebagai destinasi sampai pengguna membuka Reports. Market, Connections, dan Assistant juga berada di jalur sekunder. Ini cocok untuk aplikasi kecil, tetapi akses fitur akan semakin tersembunyi saat fitur bertambah.

### 4.3 Potensi kehilangan state halaman

Halaman terpilih dibungkus dalam `AnimatedSwitcher` dengan `KeyedSubtree` berdasarkan indeks ([main.dart](../apps/android/lib/main.dart#L688-L700)). Karena child halaman yang tidak terpilih dilepas, state lokal seperti filter pencarian/kategori Tool Catalog atau pilihan segmen Reports berpotensi dibuat ulang saat berpindah tab. Ini perlu dikonfirmasi dalam rancangan/perilaku tes; jangan mengubahnya sebelum persetujuan.

## 5. Masalah UI/UX dan rekomendasi

### Prioritas tinggi

1. **Bottom bar hilang pada layout lebar.** Sumber: breakpoint 760 dan `bottomNavigationBar: wideLayout ? null` ([main.dart](../apps/android/lib/main.dart#L623-L630), [main.dart](../apps/android/lib/main.dart#L722-L745)). Pertahankan bottom navigation sesuai persyaratan; evaluasi tablet terpisah tanpa menghilangkan kontrol utama.
2. **Angka “Local tools” adalah jumlah entri Registry, bukan jumlah tool ready.** `registeredTools = toolRegistry.length` dipakai pada Dashboard ([main.dart](../apps/android/lib/main.dart#L974-L1010)). Dengan model status baru, “terdaftar” dan “siap dijalankan” berbeda. Dashboard masa depan sebaiknya memberi label yang tepat atau menampilkan metrik terpisah berdasarkan readiness nyata.
3. **Label “Recent activity” di Dashboard merujuk ke hasil pemeriksaan terbaru.** Sumbernya `recentResults`, bukan event Activity Timeline ([main.dart](../apps/android/lib/main.dart#L1014-L1045)). Rancangan perlu membedakan “hasil pemeriksaan” dari “aktivitas yang benar-benar dicatat”.
4. **Tiga konsep numerik belum memiliki sumber agregasi produk:** Security Score, Risk Level, dan Scan Progress tidak ada sebagai model/UI saat ini. Jangan menampilkan nilai buatan. Definisikan aturan dan sumber data masing-masing sebelum visualisasi.

### Prioritas menengah

5. **Struktur utama akan padat saat Terminal, Runtime, My Tools, dan KB masuk.** Saat ini hanya empat destinasi dan beberapa nested screen. Buat satu arsitektur “Workbench/Records/More shortcuts” yang disetujui sebelum implementasi.
6. **AI shortcut terlihat seperti fitur utama walau layar menyatakan belum terhubung.** Pertahankan status placeholder yang jelas; jangan menggambarkan AI Expert sebagai aktif sebelum ada backend/model dan perilaku yang nyata.
7. **State halaman dan navigasi sekunder belum dimodelkan sebagai route bernama.** Halaman dibuka melalui callback `Navigator.push`; belum terlihat kontrak route/deep-link terpusat. Sebelum fitur bertambah, rancangan harus menentukan route/selected-tab restoration dan rute balik yang konsisten.
8. **Responsiveness masih bertumpu pada satu breakpoint.** Konten dibatasi hingga 960 px (Dashboard/Tools/Reports) atau 760 px (Settings/Assistant), tetapi belum ada bukti dalam audit ini bahwa seluruh halaman sudah diuji pada font scaling besar, landscape, atau ukuran ponsel kecil. Ini menjadi matriks verifikasi desain, bukan alasan refactor sekarang.

## 6. Rekomendasi arsitektur navigasi

Rekomendasi berikut adalah **rancangan untuk dibahas**, bukan keputusan implementasi:

### Bottom Navigation utama (tetap dipertahankan)

Pertahankan empat destinasi sekarang selama fase berikutnya:

1. **Dashboard** — overview data lokal dan status nyata.
2. **Assessment / Workbench** — Assessment dan Tool Catalog/My Tools sebagai sub-view. Terminal masa depan dapat menjadi halaman kerja khusus yang diluncurkan dari Workbench, bukan terminal bebas.
3. **Records / Reports** — Reports, Findings, dan Activity Timeline sebagai tiga sub-view yang jelas.
4. **Settings** — preferensi dan privasi; Connections tetap dapat diakses dari sini.

Pintasan tengah Assistant yang sudah ada dipertahankan sampai ada persetujuan desain lain, namun statusnya harus tetap jelas sebagai placeholder/not connected. Penamaan tab di atas merupakan opsi arsitektur untuk rancangan tahap berikutnya; perubahan label belum disetujui.

### Floating Edge Panel — navigasi sekunder dalam aplikasi

Panel direncanakan sebagai overlay Flutter **di dalam `MainShell`**. Panel tidak meminta izin Android `SYSTEM_ALERT_WINDOW`, tidak menggambar di atas aplikasi lain, dan tidak menjadi sumber data baru. Panel hanya menavigasikan ke layar/segmen yang sudah ada.

Pintasan awal yang dapat dipertimbangkan: Tool Catalog/My Tools, Findings, Activity, Market, Connections, Settings, dan Assistant placeholder. Setelah fitur nyata disetujui/diimplementasikan, Terminal, Runtime Manager, serta Knowledge Base dapat ditambahkan. Item masa depan harus diberi status planned/disabled sampai benar-benar tersedia.

#### Diagram hubungan

```text
MainShell
├── Bottom Navigation (primer, wajib dipertahankan)
│   ├── Dashboard
│   ├── Assessment / Workbench
│   │   ├── Security Assessment
│   │   └── Tool Catalog → calon My Tools
│   ├── Records / Reports
│   │   ├── Reports
│   │   ├── Findings
│   │   └── Activity Timeline
│   └── Settings
│       ├── Connections
│       ├── Diagnostics
│       └── Privacy / language
│
├── Pintasan Assistant di tengah (saat ini placeholder)
│
└── Floating Edge Panel (sekunder, in-app only)
    ├── shortcut → destinasi/segmen yang sama, bukan salinan UI/data
    ├── current: My Tools, Findings, Activity, Market, Connections, Settings
    └── future only: Terminal, Runtime Manager, Knowledge Base
```

### Batas perilaku Edge Panel untuk tahap rancangan

- Handle visual kecil, tetapi target sentuh dan accessibility semantics tetap memadai.
- Tarik untuk membuka; dapat diminimalkan/dibuka kembali; posisi dan sisi kiri/kanan dapat dipindah.
- Posisi vertikal dibatasi area aman dan disimpan sebagai posisi relatif agar tetap masuk layar setelah rotasi/resize.
- Batas ukuran panel harus menjaga konten utama, keyboard, bottom bar, system gesture area, dan tombol penting tetap dapat digunakan.
- Tampilkan overlay hanya saat dibuka; jangan menjalankan animasi terus-menerus saat tertutup.
- Persistensi posisi harus menggunakan penyimpanan preferensi aplikasi yang dipilih/ditinjau saat rancangan; jangan menambah permission overlay Android.
- Floating Edge Panel berbeda dari **Floating Workspace** masa depan. Edge Panel hanya navigasi cepat; workspace/terminal overlay memerlukan rancangan dan persetujuan terpisah.

## 7. Konsep visual Dashboard yang aman dan berbasis data

Arah visual **Futuristic Cybersecurity Instrument Dashboard** dapat memakai fondasi warna yang sudah ada: ink `#0B1020`, panel `#151D31`, mint `#73F0C2`, dan electric blue `#168DFF`; splash juga memakai cyan `#36D9FF`. Tema aplikasi menggunakan Material 3 dan `sans-serif` ([main.dart](../apps/android/lib/main.dart#L109-L145)). Pertahankan kontras teks dan keterbacaan; efek glow menjadi aksen, bukan lapisan di belakang teks kecil.

| Elemen rancangan | Data yang benar-benar tersedia | Batas rancangan |
|---|---|---|
| **Digital Earth** | Belum ada topology/network-node dataset. Built-in checks menghasilkan target dan bukti pemeriksaan, bukan peta jaringan. `Connectivity` hanya petunjuk transport/Wi-Fi kasar, bukan internet reachability atau topology ([main.dart](../apps/android/lib/main.dart#L42-L67)). | Globe idle adalah keadaan default. Jangan gambar node/garis aktif tanpa event nyata; jika nanti visualisasi hasil, tampilkan sumber, waktu, dan maksud setiap node. Utamakan ilustrasi vector ringan dibanding scene 3D/WebView. |
| **Security Speedometer** | Tidak ada algoritme Security Score atau agregasi Risk Level di UI saat ini. Findings memiliki severity/status; assessment memiliki outcomes; tool readiness adalah status tersendiri. | Pisahkan tiga modul: **Security Score** hanya setelah metodologi terdokumentasi/approved; **Risk Level** hanya dari aturan findings yang transparan; **Scan Progress** hanya dari assessment aktif (jumlah terpilih, selesai, berjalan, skipped). Jangan mengubah status Registry menjadi skor keamanan. |
| **Security Radar** | Assessment mengirim outcome completed/failed/skipped/cancelled dan UI mengetahui `_running` serta daftar outcome ([assessment_runner.dart](../apps/android/lib/widgets/assessment_runner.dart#L40-L65), [tool_orchestrator.dart](../apps/android/lib/core/tool_orchestrator.dart#L44-L64)). | Saat idle, radar diam/berlabel idle; saat assessment berlangsung, animasi hanya merepresentasikan proses/outcome yang diterima. Hentikan animasi setelah run/cancel; jangan menampilkan ancaman atau sweep sebagai temuan nyata. |
| **Security Analytics** | SQLite v4 menyimpan laporan, Activity, dan Findings; Dashboard saat ini menunjukkan hitungan session, saved report, registry dan hasil terbaru ([main.dart](../apps/android/lib/main.dart#L993-L1018)). Findings/Activity dimuat maksimal 500 item di MainShell ([main.dart](../apps/android/lib/main.dart#L405-L430), [main.dart](../apps/android/lib/main.dart#L491-L515)). | Grafik severity berasal dari records Findings yang benar-benar dimuat; riwayat assessment dari `ActivityKind.assessment`; status registry dari resolver live. Tampilkan batas rentang dan status loading/error; jangan menyimpulkan absence of findings sebagai sistem aman. |

Susunan visual yang dapat diuji pada wireframe: baris ringkas status/asal data; Digital Earth idle/observed; panel Speedometer yang memisahkan score/risk/progress (nilai yang belum tersedia harus “Belum tersedia”, bukan 0); lalu grafik Findings/Assessment dan Activity. Ini hanya opsi komposisi, belum final.

## 8. State, data, dan integrasi layar

- **Dashboard:** menerima `recentResults`, `savedResultCount`, dan status history-loaded dari `MainShell`; recent list adalah maksimum 30 hasil sesi. Riwayat disimpan/dimuat oleh `LocalResultStore`.
- **Assessment → Registry/Runtime → persistence:** Tool Catalog mengambil status dari `ToolOrchestrator.statusForTool`; `AssessmentRunner` menyerahkan hasil ke MainShell; Activity, Findings, dan Reports menggunakan repository/callback yang sudah ada.
- **Reports/Findings/Activity:** tiga sub-view menerima snapshot data dari `MainShell`; Findings dan Activity dimuat asynchronously, disaring di layar, dan dapat membuka referensi silang sumber report/activity.
- **Market:** dibuka dari Tool Catalog dan berbagi instance `MarketPackageManager`; package terpasang tidak berarti tool executable.
- **Connections, Assistant, Diagnostics:** navigasi sekunder saat ini; Assistant secara eksplisit belum menghubungi provider.
- **SQLite:** `LocalResultStore` schema version 4 memiliki tabel `scan_results`, `activity_events`, dan `security_findings` ([local_result_store.dart](../apps/android/lib/core/local_result_store.dart#L31-L43)). Audit ini tidak mengusulkan perubahan schema.

Rancangan Dashboard hendaknya memakai selector/view-model tipis yang membaca sumber data yang sama, tidak membuat salinan atau angka alternatif di widget visualisasi. Data “loading”, “empty”, “error”, “stale”, dan “partial” perlu dibedakan.

## 9. Risiko teknis dan dampak

| Risiko | Dampak | Mitigasi yang harus dirancang sebelum implementasi |
|---|---|---|
| Animasi globe/radar terus berjalan | GPU, baterai, dan RAM meningkat pada perangkat menengah | Idle static state; jalankan hanya saat visible/assessment aktif; hentikan saat tab tidak aktif; patuhi `MediaQuery.disableAnimations`; profiling pada perangkat nyata. Splash saat ini sudah menghormati `disableAnimations`, tetapi itu belum membuktikan kesiapan untuk animasi Dashboard ([animated_splash_screen.dart](../apps/android/lib/widgets/animated_splash_screen.dart#L23-L56)). |
| Visualisasi fiktif | Menggambarkan network topology/serangan atau skor yang tidak pernah dihitung | Data contract per visual; idle state; label provenance/timestamp; jangan render event jika tidak ada record. |
| Overlay menutupi form/tab atau system gestures | Assessment tidak dapat digunakan atau panel sulit ditutup | Panel dibatasi viewport/safe area, keyboard-aware, dismiss gesture/tombol yang mudah dijangkau, target sentuh, dan UI tests di berbagai ukuran. Tetap in-app; tanpa permission overlay. |
| Navigasi menambah terlalu banyak pintasan | Duplikasi tab, label membingungkan, panel berubah menjadi menu kedua | Bottom nav tetap sumber navigasi utama; Edge Panel hanya shortcut ke rute/segmen yang sama dan jumlahnya dibatasi. |
| State lokal hilang antar-tab | Pencarian/filter dan pilihan pengguna ter-reset | Rancangkan retensi state per destination dan perilaku deep link sebelum implementasi; uji perpindahan tab. |
| Agregasi Findings/Activity bertambah | Sorting/filter pada build makin berat ketika dataset tumbuh | Saat ini data UI dibatasi 500; pertahankan batas/paginasi dan pindahkan agregasi berat ke repository/query bila skala berubah. |
| Score/risk/progress tercampur | Pengguna mengira pemeriksaan yang sedang berjalan adalah tingkat risiko atau jaminan keamanan | Model status terpisah, definisi/rentang jelas, label “belum tersedia” dan partial assessment. |
| Font scaling/layar sempit | Label dan kontrol terpotong atau tumpang-tindih | Wireframe dan uji minimal layar kecil, landscape, font scaling besar, dan tablet; semua konten tetap scrollable. |

## 10. Komponen: pertahankan, perbaiki setelah persetujuan, rencanakan

### Pertahankan

- Empat destinasi utama dan fungsi navigasinya; tidak menghapus bottom navigation.
- Local-first pipeline: SQLite v4, Reports, Findings, Activity, Registry readiness, Policy/Orchestrator.
- Status kejujuran pada Assistant dan Market; package tidak disamakan dengan executable.
- Palet dark navy/mint/electric blue dan informasi privacy/local storage.

### Pertimbangkan untuk diperbaiki pada milestone implementasi UI/UX setelah approval

- Pastikan bottom bar tetap tersedia pada semua layout yang masuk cakupan produk.
- Perjelas metrik registered/ready dan “recent activity” vs recent results.
- Putuskan kebijakan state-retention saat pindah tab.
- Beri shortcut konsisten untuk Reports/Findings/Activity/Market/Connections tanpa membuat route/data duplikat.
- Tambahkan state loading/idle/no-data/error yang seragam untuk komponen instrumen.

### Rencanakan, jangan tampilkan seolah sudah aktif

- Floating Edge Panel in-app.
- My Tools sebagai pengalaman katalog/pengelolaan yang lebih terstruktur.
- Runtime Manager UI dan Terminal terpisah, hanya setelah embedded runtime didesain/disetujui.
- Knowledge Base dengan sumber dan retrieval yang dapat diaudit.
- AI Cybersecurity Expert hanya sesudah model/provider/guardrail benar-benar diimplementasikan.
- Digital Earth, Security Score, radar, dan analytics hanya dengan data/aturan produk yang tervalidasi.

## 11. Tahapan setelah audit disetujui

1. **Evaluasi audit ini** dan koreksi prioritas/penempatan fitur bersama pemilik produk.
2. **Rancangan (belum implementasi):** sitemap final, wireframe layar kecil/lebar, panel open/minimized/dragged, dan state idle/loading/active/partial/empty/error untuk tiap visual.
3. **Persetujuan eksplisit** untuk desain Dashboard dan navigasi, termasuk arti score/risk/progress dan item Edge Panel.
4. **Implementasi UI/UX bertahap:** navigasi/retensi state, Edge Panel in-app, Dashboard data-backed, lalu visualisasi/analytics yang sumber datanya disetujui. Pertahankan schema SQLite v4 kecuali ada kebutuhan terpisah yang disetujui.
5. **Verifikasi:** widget tests navigasi/state, aksesibilitas, reduced motion, layar/resolusi/font scaling, data provenance, serta profiling performa Android kelas menengah.
6. **Embedded Runtime/Terminal** tetap milestone berikutnya yang terpisah setelah UI/UX disetujui dan fondasi navigasi siap.

## 12. Batas audit

Tidak ada kode aplikasi, UI/UX, Tool Registry, Tool Orchestrator, Runtime Manager, atau SQLite yang diubah dalam audit ini. Dokumen ini bukan persetujuan desain final dan bukan izin untuk memulai implementasi. **Berhenti di sini sampai hasil audit ditinjau dan rancangan berikutnya disetujui.**
