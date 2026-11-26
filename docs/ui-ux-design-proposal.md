# Proposal Rancangan UI/UX dan Arsitektur Visual

**Milestone:** 2 — rancangan untuk ditinjau, belum implementasi
**Status:** Proposal menunggu persetujuan pemilik produk
**Branch:** `arena/02828d01-cybersecurity-assistant`
**HEAD acuan:** `88ad0e1e6745972e81198a8e2c1400746347b2c1`
**Tanggal:** 2026-11-23
**Audit sumber:** [`ui-ux-architecture-audit.md`](ui-ux-architecture-audit.md)

> Dokumen ini hanya rancangan. Tidak ada kode aplikasi, SQLite v4, backend, Tool Registry, Orchestrator, atau Runtime yang diubah. Komponen dan halaman berstatus rencana/masa depan tidak boleh ditampilkan seolah sudah aktif. Konsep visual tidak menyatakan keamanan sistem, koneksi jaringan, atau serangan tanpa data pendukung.

## 1. Tujuan dan prinsip rancangan

Arah visual: **Futuristic Cybersecurity Instrument Dashboard** — ruang kerja keamanan lokal yang terasa seperti pusat kendali, namun tetap dapat dipercaya, mudah dipindai, dan efisien di ponsel Android kelas menengah.

Prinsip desain:

1. **Truth before spectacle:** angka, status, node, dan grafik mempunyai sumber data yang jelas. Tidak ada data dekoratif yang bisa disalahartikan sebagai temuan.
2. **Local-first dan transparan:** bedakan hasil yang tersimpan lokal, hasil sesi, aktivitas, status tool, dan konektivitas.
3. **Empat destinasi tetap stabil:** Home, Assessment, Reports, Settings tetap menjadi navigasi utama.
4. **Progress bukan risk; risk bukan score:** ketiganya terpisah secara visual dan semantik.
5. **Idle berarti idle:** visual idle boleh bercahaya/berputar halus, tetapi tidak menunjukkan titik, garis jaringan, ancaman, atau aktivitas seolah nyata.
6. **Aksesibilitas dan performa:** kontras, ukuran teks, touch target, reduced motion, serta layar kecil menjadi batas desain sejak awal.
7. **Future features diberi label:** Terminal, Runtime Manager, AI Expert, Knowledge Base dan Workspace tidak muncul sebagai fitur aktif sebelum dibangun dan disetujui.

## 2. Status fitur yang menjadi dasar proposal

Status di bawah mengikuti audit pada HEAD acuan; ini bukan perubahan status implementasi.

| Area | Status saat audit | Perlakuan dalam rancangan |
|---|---|---|
| Home / Dashboard | Tersedia; overview local-first, metrik Registry/session/saved, hasil terbaru, kartu Assistant | Mengembangkan hierarki visual yang dirancang di dokumen ini. Score, Risk dan topology tidak diasumsikan tersedia. |
| Assessment | Tersedia; target, konfirmasi otorisasi, pilihan check yang ready, hasil per-check | Menjadi alur kerja; radar aktif hanya ketika assessment benar-benar berjalan. |
| Reports | Tersedia; hasil sesi dan tersimpan lokal | Tetap di destinasi Reports, dengan filter dan detail sumber. |
| Findings | Tersedia; severity, confidence, status dan referensi sumber | Tab dalam Reports; agregat hanya dari records yang dimuat/tersedia. |
| Activity | Tersedia; assessment/tool events, status dan timestamp | Tab dalam Reports; grafik timeline tidak mengarang event. |
| Tool Catalog | Tersedia, empat entri Registry saat audit; readiness dapat berubah | Berada dalam Assessment sebagai sub-view. “My Tools” bukan koleksi/favorit aktif saat ini. |
| Market | Tersedia sebagai katalog demonstrasi terbatas | Halaman sekunder dari katalog; tandai bahwa package tidak otomatis executable. |
| Settings | Tersedia | Preferensi, bahasa, privasi, data lokal, Diagnostics. |
| Connections | Prototipe; pemeriksaan endpoint HTTPS/panduan provider, belum ada konektor provider terautentikasi | Tampilkan status prototipe secara eksplisit. Jangan klaim provider connected jika belum demikian. |
| Assistant / AI Expert | Assistant placeholder; menyatakan belum terhubung | Akses tetap tersedia, diberi label “Preview / belum terhubung”. AI Expert aktif adalah masa depan. |
| Runtime Manager UI | Belum tersedia (core lifecycle/runtime metadata ada) | Rencana halaman masa depan; tidak ditampilkan sebagai item aktif. |
| Terminal / Floating Workspace | Belum tersedia | Rencana terpisah setelah desain dan runtime disetujui. Bukan akses ke shell bebas. |
| Knowledge Base | Belum ada layar/retrieval; ada knowledge pack data | Rencana masa depan, tidak disamakan dengan pack yang terpasang. |
| Digital Earth / Score / Radar Dashboard / Analytics | Belum ada pada Dashboard saat audit | Elemen desain baru; data kontrak dan unavailable states didefinisikan di proposal ini. |

## 3. Design system

### 3.1 Palet warna

Palet mengambil landasan dari tema aplikasi saat ini (ink/navy, mint, electric blue) lalu menetapkan token semantik untuk konsistensi. Warna severity tetap harus didampingi teks/icon, bukan warna saja.

| Token proposal | Nilai | Penggunaan |
|---|---:|---|
| `canvas` | `#0B1020` | Latar layar utama, ink/navy yang sudah ada. |
| `surface` | `#151D31` | Panel/card dasar, mengikuti warna panel yang ada. |
| `surfaceRaised` | `#1B2740` | Dialog, drawer, kartu bertingkat; dibatasi agar layar tidak menjadi lautan panel. |
| `surfaceMuted` | `#10182A` | Inset/data strip dan latar area idle. |
| `textPrimary` | `#F4F7FB` | Judul dan nilai utama. |
| `textSecondary` | `#A9B6C9` | Keterangan. Uji kontras sebelum implementasi; jangan gunakan mint tipis untuk paragraf. |
| `mint` | `#73F0C2` | Aksi utama/ready/idle highlight, mengikuti aksen yang ada. |
| `electricBlue` | `#168DFF` | Link, progress dan data series netral. |
| `cyan` | `#36D9FF` | Highlight/glow terbatas; warna cyan yang telah dipakai splash. |
| `warning` | `#F6C66B` | Status peringatan / medium severity. |
| `danger` | `#FF6B7A` | High severity/error; selalu bersama label dan ikon. |
| `info` | `#90A7C4` | Informasional, status netral. |
| `divider` | `#2A3852` | Pemisah dan outline berkontras rendah. |

**Batas penggunaan:** glow hanya pada aksen, bukan teks kecil; maksimum dua warna aksen terang pada satu komponen. Jangan memakai hijau sebagai “aman” secara otomatis. Tidak ada palet hijau/merah yang menyimpulkan score keamanan.

### 3.2 Tipografi, bentuk, spacing

- Pertahankan tipografi sans-serif sistem dan hirarki Material yang sudah ada; gunakan angka tabular untuk metrik.
- Judul Dashboard 24–28sp, judul section 16–18sp, body 14–16sp, label sekunder minimum 12sp. Teks penting tetap dapat dibaca pada font scaling besar.
- Radius card 16–20dp; gauge/globe boleh lingkaran. Border 1dp halus, bukan outline neon tebal pada semua kartu.
- Spacing basis 4dp; content padding ponsel 16dp (minimum 12dp pada viewport sempit), gap komponen 12–20dp.
- Touch target kontrol utama sekurangnya 48dp. Label/icon selalu disertakan untuk pintasan nonteks.
- Terapkan safe area, scroll vertikal, dan wrapping; jangan memaksa metrik 4 kolom pada ponsel sempit.

### 3.3 Gaya visual

Panel cockpit gelap dengan sedikit depth, garis instrumen tipis, dan aksen cyan/mint. Hindari noise, partikel konstan, parallax berat, foto stock ancaman, serta animasi scanner yang terlihat seperti deteksi aktif ketika tidak sedang menjalankan Assessment.

## 4. Navigasi yang direkomendasikan

### 4.1 Bottom Navigation: destinasi tidak berubah

Pada penggunaan HP, empat tab tetap terlihat dan dapat dicapai:

```text
┌────────────────────────────────────────────┐
│                Konten halaman               │
├────────────────────────────────────────────┤
│  Home   Assessment   Reports   Settings     │
└────────────────────────────────────────────┘
```

| Label saat ini (dipertahankan) | Isi utama | Sub-view / pintasan |
|---|---|---|
| **Home** | Dashboard overview dan instrument | Assistant card/pintasan; hasil terbaru membuka Reports/detail terkait. |
| **Assessment** | Alur Security Assessment | Segmented sub-view `Assessment` / `Tool Catalog`; Market dari katalog. “My Tools” dapat menjadi label/konsep lanjutan setelah ada fungsi pengelolaan nyata. |
| **Reports** | Riwayat hasil tersimpan dan sesi | Segmented sub-view `Reports` / `Findings` / `Activity`. |
| **Settings** | Preferensi, privasi, diagnostics | Connections, bahasa, data lokal; buka sebagai halaman sekunder yang memiliki judul/back. |

Tab terpilih jelas lewat icon, label dan indikator; jangan mengandalkan warna saja. Pada ukuran lebih lebar, proposal ini tidak menjadikan `NavigationRail` sebagai pengganti Bottom Navigation pada rancangan utama. Varian tablet dapat diputuskan terpisah, tetapi harus mempertahankan empat destinasi dan akses mudah ke bottom tabs.

### 4.2 Penempatan Assistant

Pertahankan akses yang sudah tersedia melalui kartu Home dan Settings, serta tombol tengah pada bottom bar untuk menjaga discoverability sampai ada persetujuan perubahan. Perlakukan tombol tengah sebagai **shortcut aksi sekunder**, bukan destinasi kelima: label/accessibility “Assistant — preview, belum terhubung”, style terpisah tetapi tidak lebih menonjol dari Assessment, dan state disabled hanya untuk tindakan mengirim yang memang belum tersedia. Jika posisi tombol tengah menciptakan kesan Assistant aktif, opsi desain selanjutnya ialah memindah pintasan ke Edge Panel atau menu Home — tetapi opsi itu memerlukan persetujuan dan tidak boleh menghilangkan akses.

### 4.3 Peta halaman dan hubungan

```text
MainShell
├── Home (Dashboard)
│   ├── Digital Earth (visual; idle sampai data topology nyata tersedia)
│   ├── Security Instruments
│   ├── Security Analytics
│   ├── Recent check results → Reports/detail
│   └── Assistant preview (belum terhubung)
├── Assessment
│   ├── Assessment Runner → hasil, report, findings/activity
│   └── Tool Catalog → detail tool / Market
├── Reports
│   ├── Reports
│   ├── Findings
│   └── Activity Timeline
└── Settings
    ├── Connections (prototipe)
    ├── Diagnostics
    └── Language / Privacy / Local data

Floating Edge Panel (sekunder, in-app)
└── shortcut → Home, Assessment, Reports/Findings/Activity,
    Tool Catalog, Market, Connections, Settings, Assistant preview

Masa depan, terpisah dan tidak tampil sebagai fitur aktif:
├── My Tools (jika fungsi koleksi/pengelolaan dirancang)
├── Runtime Manager UI
├── Terminal + Floating Workspace (setelah runtime disetujui)
├── AI Cybersecurity Expert (setelah provider/engine siap)
└── Knowledge Base (setelah retrieval dan provenance tersedia)
```

### 4.4 Penempatan fitur dan akses

| Fitur | Penempatan proposal | Status badge di rancangan |
|---|---|---|
| Dashboard | Home | Current / design extension |
| Assessment | Tab Assessment, sub-view Assessment | Available |
| Tool Catalog | Tab Assessment, sub-view kedua | Available; cakupan terbatas |
| Reports | Tab Reports | Available |
| Findings | Tab Reports, sub-view | Available |
| Activity | Tab Reports, sub-view | Available |
| Settings | Tab Settings | Available |
| Connections | Settings → Connections | Prototype |
| Market | Tool Catalog → Market | Limited catalog / prototype scope |
| My Tools | Potensi sub-view Tool Catalog | Planned; tidak ditampilkan sebagai aktif |
| Terminal | Future Workbench, bukan navigasi saat ini | Future / unavailable |
| Runtime Manager | Settings/Workbench masa depan setelah desain | Future / unavailable |
| AI Cybersecurity Expert | Assistant surface masa depan | Not connected / future |
| Knowledge Base | Future search/library | Future / unavailable |
| Floating Workspace | Lapisan masa depan berbeda dari Edge Panel | Future / not implemented |

## 5. Wireframe Dashboard

Wireframe berikut bersifat konseptual, alur vertikal pada HP. Konten dapat scroll; Bottom Navigation tetap terlihat. Data “belum tersedia” bukan nilai nol.

```text
┌────────────────────────────────────────────┐
│ CYBERSECURITY                     LOCAL    │  app bar/status mode nyata
│ Your security workspace                    │
│ Data lokal • Last updated [timestamp]       │  jika timestamp tersedia
├────────────────────────────────────────────┤
│                                            │
│        ┌────────────────────────┐          │
│        │      DIGITAL EARTH     │          │
│        │    (idle illustration) │          │
│        │ topology: unavailable  │          │
│        │ No live network map    │          │
│        └────────────────────────┘          │
│                                            │
│ SECURITY INSTRUMENTS                       │
│ ┌────────────────────────────────────────┐ │
│ │ Security Score   Belum tersedia        │ │
│ │ Metodologi belum ditetapkan             │ │
│ ├────────────────────────────────────────┤ │
│ │ Risk Level       Tidak dihitung         │ │
│ │ berdasarkan findings terpilih*          │ │
│ ├────────────────────────────────────────┤ │
│ │ Scan Progress    Idle / tidak ada run   │ │
│ └────────────────────────────────────────┘ │
│ *Ringkasan severity findings bukan skor   │
│                                            │
│ SECURITY ANALYTICS                         │
│ [Findings severity: empty/current counts]  │
│ [Assessment history: records if available] │
│ [Tool status: ready / unavailable / error] │
│ [Recent activity → View all]               │
│                                            │
│ Recent check results                       │
│ [result row] [result row] [View Reports]   │
│                                            │
│ Assistant preview · Not connected          │
├────────────────────────────────────────────┤
│ Home   Assessment   Reports   Settings     │
└────────────────────────────────────────────┘
```


data footnote (when relevant): `Local records only · limited to loaded records · [time range]`. Ketika ada Assessment aktif, blok progress dan radar dapat ditonjolkan, tetapi laporan/score/risk tidak boleh saling menggantikan.

### 5.1 Dashboard pada layar lebih luas

Tetap memakai satu kolom hero dengan Digital Earth sebagai fokus utama; di bawahnya instruments dapat mengalir menjadi dua kolom, lalu analytics grid dua kolom. Breakpoint harus dipilih melalui prototype responsif, bukan dengan angka metrik fixed-width. Jaga urutan baca: status/sumber → globe → instruments → analytics → recent results.

## 6. Rancangan Digital Earth

### 6.1 Komposisi visual

- Hero berbentuk kartu lebar navy dengan globe vector/layered 2D: graticule lintang-bujur, kontur/bentuk bumi abstrak dan rim light cyan.
- Pada **idle default**: globe dapat berputar sangat lambat atau berupa efek parallax ringan; hanya ilustrasi. Tampilkan label `Network topology unavailable` / `No live network map` yang dapat diterjemahkan.
- Tidak ada pin, node, garis antarkota, jalur paket, ikon ancaman, atau heatmap pada idle. Tidak ada klaim `online` berdasarkan indikator Wi-Fi saja.
- Jika kelak data topology nyata tersedia: legenda jelas, node hanya dari entitas terukur/diizinkan, garis hanya dari relasi yang teramati, timestamp/asal data tampil. Jangan memetakan target Assessment sebagai “serangan”. Privasi target dan izin tampilan perlu disetujui.
- Jika hanya ada data check terhadap host: visual yang tepat adalah daftar/objek target berlabel “assessment target”, bukan menghubungkannya ke globe seolah topology.

### 6.2 Kontrak state globe

| State | Tampilan |
|---|---|
| Idle/no topology | Globe ilustratif; tidak ada marker/data line; keterangan topology belum tersedia. |
| Loading topology (masa depan) | Placeholder netral dan teks sedang memuat; jangan animasikan seolah node ditemukan. |
| Observed topology (masa depan) | Hanya node/edge dari feed yang terdokumentasi; legenda, timestamp, sumber, batas cakupan. |
| Error / stale | Tampilkan pesan gagal atau waktu data lama; visual kembali netral, bukan peta yang terlihat live. |
| Reduced motion | Globe statis, rim glow statis, tanpa rotation/parallax. |

### 6.3 Gerak globe

Satu rotasi perlahan berbasis animasi transform/layer ringan; durasi target konseptual 60–120 detik per siklus, opacity/scale minimal, tidak ada particle emitters. Hentikan saat layar tidak terlihat/route tertutup, pause ketika aplikasi background, serta nonaktifkan gerak saat `disableAnimations`. Nilai durasi ini target rancangan yang harus diuji, bukan implementasi sekarang.

## 7. Security Instruments, Speedometer, dan Radar

### 7.1 Tiga panel terpisah

Jangan membuat satu dial yang menempatkan score, risk, dan progress sebagai angka/warna yang saling dapat dipertukarkan. Tampilkan tiga kartu dengan judul, nilai/status, sumber data, waktu, dan affordance menuju detail.

| Instrument | Konsep UI | Sumber/status yang boleh dipakai | Keputusan yang belum boleh diasumsikan |
|---|---|---|---|
| **Security Score Gauge** | Half-ring/gauge dengan value center; kartu memiliki tooltip `How is this calculated?` | Saat ini `Unavailable / Methodology not defined` | Tidak ada angka contoh seperti 72/100, tidak ada nilai default 0/100. Sebelum aktif perlu metodologi disetujui: input, bobot, confidence, cakupan check, missing/partial data, waktu berlaku dan penjelasan. |
| **Risk Level Gauge** | Level teks (mis. `Not assessed`) dengan indikator kategori, bukan speedometer score | Finding severity/status yang benar-benar tersimpan dapat dihitung sebagai *counts per severity*; total Findings bukan risk score | Jangan membuat level keseluruhan sebelum aturan agregasi, status mana yang dihitung, confidence dan cakupan disetujui. Findings tidak sama dengan jaminan risiko lengkap. |
| **Scan Progress Gauge** | Progress ring/linear + `completed / selected`, current tool jika ada, tombol menuju Assessment | State Assessment aktif: checks selected, outcomes, running/cancelled; bila tidak berjalan tunjukkan `Idle` | Tidak menganggap jumlah tool terdaftar sebagai progress. Jika tidak ada active assessment, tidak ada persentase palsu. |

Untuk mockup statis: pakai status teks, bukan angka arbitrer; `Score — Not available`, `Risk — Not calculated`, `Progress — Idle`. Jika ilustrasi gauge perlu menunjukkan bentuk, gunakan track kosong dan catatan `illustrative only`, jangan mengisi persentase.

### 7.2 Radar

- **Idle:** latar lingkaran/ring statis dengan caption `Assessment not running`; tidak ada sweep berulang, blip, atau titik ancaman.
- **Running:** sweep lembut hanya saat event assessment aktif. Label menunjukkan target yang disanitasi (host saja sesuai activity storage), tool aktif, dan jumlah checks yang selesai/terpilih. Hindari memvisualisasi target sebagai ancaman.
- **Completed/cancelled/failed:** hentikan sweep; tampilkan ringkasan outcome terverifikasi dan timestamp, dengan link ke Reports/Activity.
- **Reduced motion/background:** radar tidak menganimasikan. Tetap tunjukkan progress tekstual/accessibility semantics.
- Radar adalah representasi status kerja Assessment, bukan sensor keamanan real-time.

## 8. Rancangan Security Analytics

Semua grafik harus menyatakan rentang waktu, jumlah item yang dianalisis, sumber, dan batas data. Dengan pemuatan saat ini yang dibatasi hingga 500 Findings/Activity serta hasil terbaru yang dibatasi, UI harus menghindari label “all time” kecuali repository benar-benar menghitung seluruh data.

| Visual | Data aktual / definisi aman | Empty/unavailable dan interaksi |
|---|---|---|
| **Findings by severity** | Hitung records Findings yang dimuat menurut `high`, `medium`, `low`, `info`; tampilkan Open/Resolved terpisah jika status disertakan. Gunakan severity enum yang ada. Label `N findings in loaded records`; tidak menganggap nol sebagai sistem aman. | 0 records: “No findings recorded in this view” (bukan “No threats”). Loading/error ditampilkan terpisah. Tap kategori membuka Reports → Findings dengan filter. |
| **Assessment history** | Derive hanya dari Activity event `kind=assessment`; status `started/running/completed/failed/cancelled`, startedAt/finishedAt. Grafik batang jumlah run per bucket waktu hanya untuk event yang dimuat dan rentang yang dinyatakan. | Kosong: “No assessment history yet” + CTA Assessment. Event parsial/aktif ditandai in progress. Jika event limit memotong data, tampilkan batas records / waktu. |
| **Activity Timeline** | Gunakan Activity events (assessment/tool) aktual. Tampilkan event bersanitasi, timestamp dan status; jangan menggandakan tool event sebagai assessment event tanpa parent/linkage. | Kosong: “No activity recorded yet”; error store tampil sebagai error dengan retry. Tap membuka event/report terkait jika reference tersedia. |
| **Tool Registry status** | Snapshot jumlah tool registry dan count per resolver status aktual, misalnya Ready / Unavailable / Error / Checking, hanya setelah resolver memberi hasil. Bedakan Registry entries dengan executable/ready tools. | Status belum dimuat: `Checking tool readiness`; error: `Could not determine status`; tidak mengasumsikan semua tool ready. Tap membuka Tool Catalog. |
| **Security check statistics** | Hitung hasil check dari Report/Activity records yang tersedia: jumlah run, completed/failed/cancelled, findings terkait. Definisi “check” vs “assessment run” diberi label; deduplicate melalui event/report linkage. | Tanpa data, tampilkan empty state. Jangan tampilkan coverage/security posture yang belum dihitung. |
| **Recent reports** | Daftar hasil sesi dan report tersimpan dengan label saved/session, timestamp, tool dan target yang sudah disanitasi. | Beda state session-only, saved local, no reports, loading, error. Hindari target berisi path/query/credentials. |

### Grafik yang disarankan

- Findings: horizontal bar kategori (lebih terbaca daripada donut untuk label kecil), empat severity dengan count eksplisit. Warna + ikon/teks.
- Assessment per waktu: kolom sederhana bertumpuk menurut completed/failed/cancelled; hanya setelah aggregate event nyata. Rentang `7 days / 30 days` dapat menjadi filter UI rancangan, tetapi data perlu benar-benar tersedia untuk periode itu.
- Activity: timeline/list dahulu; sparkline bukan keharusan. Grafik tidak boleh menyiratkan volume real-time jika event hanya dicatat setelah operasi.
- Tool readiness: status strip/list, bukan trend chart kecuali status historis memang disimpan. Saat ini tidak ada riwayat transisi readiness yang cukup untuk grafik tren.
- Accessibility: sediakan tabel/list ekuivalen, label chart, navigasi fokus dan ringkasan tekstual yang dapat dibaca screen reader.

## 9. Wireframe halaman utama dan sekunder

### 9.1 Assessment

```text
┌────────────────────────────────────────────┐
│ Assessment                                 │
│ [Assessment] [Tool Catalog]                │
│ Target domain / HTTPS URL                   │
│ [______________________________________]    │
│ □ Saya punya izin ...                       │
│ Checks (status readiness di setiap tool)    │
│ ☑ TLS Inspector       Ready                 │
│ □ DNS Lookup          Ready/Unavailable     │
│ □ HTTP Headers        Ready/Unavailable     │
│ [Run selected checks]   [Cancel saat run]   │
│                                             │
│ Assessment state / progress                │
│ Radar idle atau aktif hanya saat run        │
│ Per-check: waiting / running / done / error │
│ Results → Reports / Findings / Activity     │
├────────────────────────────────────────────┤
│ Home   Assessment   Reports   Settings     │
└────────────────────────────────────────────┘
```

Pertahankan alur explicit authorization, target review, tool readiness dan hasil per check. Jangan menampilkan radar aktif sebelum `running == true`; cancel/partial outcome harus dibedakan dari sukses.

### 9.2 Tool Catalog dan Market

```text
┌────────────────────────────────────────────┐
│ Assessment > Tool Catalog                  │
│ [Search] [Category filter]                 │
│ Ready / Unavailable / Checking legend      │
│ ┌────────────────────────────────────────┐ │
│ │ Tool name       status                 │ │
│ │ Description • capabilities • risk      │ │
│ │ [Details]         [Market (secondary)] │ │
│ └────────────────────────────────────────┘ │
│ Installed package ≠ executable tool         │
└────────────────────────────────────────────┘
```

Market tetap halaman sekunder dengan status kompatibilitas dan lifecycle yang jujur. “My Tools” hanya muncul setelah ada fungsi nyata untuk memilih/menyimpan tool; sebelum itu gunakan nama `Tool Catalog` yang tersedia.

**Klarifikasi produk disetujui pemilik (2026-11-23):** Market dan katalognya selalu ada di base app. Pengguna dapat memasang atau menghapus modul Cloudflare, Gemini, dan Local AI secara independen tanpa menghapus aplikasi atau Market. Kartu modul tetap terlihat saat belum dipasang, dengan status yang membedakan `Belum dipasang`, `Mengunduh`, `Terpasang`, `Perlu konfigurasi`, `Belum siap`, `Tidak kompatibel`, dan `Gagal`. Sebelum pemasangan, tampilkan sumber, versi, ukuran, lisensi, perangkat/izin yang diperlukan, serta efek penghapusan.

```text
┌────────────────────────────────────────────┐
│ Market > Provider Modules                  │
│ Cloudflare    Not installed      [Install] │
│ Gemini        Not installed      [Install] │
│ Local AI      Not installed      [Install] │
└────────────────────────────────────────────┘
```

Setelah Cloudflare terpasang, buka halaman khusus dan tampilkan hanya operasi yang benar-benar lolos pemeriksaan izin API per kapabilitas. Gemini tetap meminta key pengguna dan persetujuan data setiap permintaan. Local AI tetap `Not Ready` sampai runtime/model kompatibel lulus pemeriksaan dan inferensi lokal nyata berhasil. Menghapus modul tidak menghapus aplikasi, Market, riwayat pemeriksaan, atau provider lain. Ini adalah **target UI/produk**, belum perilaku Market saat ini. Prioritas teknisnya adalah stabilisasi APK dasar; setelah itu uji paket bertanda tangan dari server resmi dengan kontrak transport netral. Paket data tidak boleh diperlakukan sebagai kode executable. Pengiriman kode melalui Play modular dievaluasi menjelang rilis. Detail ada di [Market Modular Delivery](market-modular-delivery.md).

### 9.3 Reports

```text
┌────────────────────────────────────────────┐
│ Reports                                    │
│ [Reports] [Findings] [Activity]             │
│ [Session] [Saved locally] [Filter]          │
│ Report card: tool • sanitized target        │
│ time • result/finding summary • saved state │
│ [Open details] [Save/export jika tersedia]  │
│ Empty/loading/error + source/local note     │
└────────────────────────────────────────────┘
```

### 9.4 Findings

```text
┌────────────────────────────────────────────┐
│ Reports > Findings                         │
│ [Search] [Severity] [Status] [Target]       │
│ Count ringkas dari data yang dimuat         │
│ Severity badge + confidence + title         │
│ status • first/last seen                    │
│ [Detail] → evidence/recommendation/source   │
│ [Update status] (status action yang ada)     │
└────────────────────────────────────────────┘
```

Kesimpulan keparahan bukan risk gauge. Jelaskan bahwa data lokal terbatas pada temuan yang tercatat; rekomendasi/evidence memiliki hierarchy dan target disanitasi.

### 9.5 Activity

```text
┌────────────────────────────────────────────┐
│ Reports > Activity                         │
│ [Date range] [Kind] [Status] [Tool]         │
│ Timeline • timestamp • assessment/tool      │
│ status • safe summary • sanitized target    │
│ [Open source report]                       │
│ Local history • records/time range          │
└────────────────────────────────────────────┘
```

Pertahankan filter dan deep-link ke assessment/report saat reference tersedia. Jangan menjanjikan event real-time atau event lengkap lintas perangkat.

### 9.6 Settings

```text
┌────────────────────────────────────────────┐
│ Settings                                   │
│ Appearance / Language                      │
│ Privacy & local data                       │
│ Connections       Prototype status          │
│ Diagnostics                                │
│ About / app version                         │
└────────────────────────────────────────────┘
```

Kelompokkan berdasarkan tujuan; tampilkan secara eksplisit mana data lokal/tidak tersinkron dan tindakan hapus data sebelum konfirmasi.

### 9.7 Connections

```text
┌────────────────────────────────────────────┐
│ Settings > Connections                     │
│ Provider directory / endpoint test          │
│ State: not configured / test result         │
│ Provider integration: Not connected         │
│ Privacy disclosure before test              │
│ [Run endpoint test]                         │
└────────────────────────────────────────────┘
```

Jangan menyamakan endpoint reachable dengan provider terautentikasi/AI aktif. State koneksi harus berasal dari handshake/credential flow yang benar-benar ada; jika belum, label prototype.

### 9.8 Assistant, masa depan dan Diagnostics

- **Assistant saat ini:** layar placeholder “AI/provider belum terhubung”, menjelaskan apa yang belum tersedia. Tidak ada composer aktif yang seolah mengirim prompt. CTA dapat menuju Connections atau Tools yang tersedia.
- **AI Cybersecurity Expert masa depan:** halaman terpisah hanya setelah integrasi provider/engine, consent, privasi, tool permissions, provenance dan guardrails disetujui.
- **Diagnostics:** tampilan status dan error teknis; hindari informasi rahasia. Bukan halaman analytics keamanan.
- **My Tools masa depan:** hanya bila ada konsep favorit/pinned/installed readiness yang berguna. Bedakan `installed`, `ready`, `enabled` dan `available` sesuai status sebenarnya.

### 9.9 Masa depan: Terminal, Runtime Manager, Knowledge Base

- **Terminal:** tidak dibuat sebagai shell bebas. Jika runtime mendatang menyetujui terminal terbatas, harus ada scope/capabilities, target authorization, audit log, command allowlist, cancellation dan batas resource. Tidak ada mock terminal aktif di navigasi saat ini.
- **Runtime Manager:** halaman masa depan untuk runtime yang disetujui, kompatibilitas, lifecycle/health dan capability; tidak mengklaim shell/package manager tersedia sekarang.
- **Knowledge Base:** search/library masa depan dengan sumber, versi dan tanggal; knowledge pack terpasang tidak sama dengan retrieval siap pakai.
- **Floating Workspace:** kemungkinan overlay in-app masa depan untuk konteks kerja; dibedakan dari Edge Panel shortcut, perlu desain, izin produk dan threat model sendiri.

## 10. Floating Edge Panel

### 10.1 Tujuan dan batas

Panel adalah kumpulan shortcut aplikasi yang menumpang di dalam area `MainShell`; bukan Android system overlay, tidak meminta `SYSTEM_ALERT_WINDOW`, tidak mengganti Bottom Navigation, tidak menjalankan tool, serta tidak menambah sumber data atau kemampuan runtime.

### 10.2 Wireframe keadaan

```text
CLOSED / HANDLE                       OPEN / PANEL
┌──────────────────────┐              ┌──────────────────────┐
│ Halaman Dashboard    │              │ Halaman (scrim ringan)│
│                      │              │ ┌──────────────────┐ │
│                 [≡]  │ tap/swipe →  │ │ Quick access  ×  │ │
│                      │              │ │ Home             │ │
│                      │              │ │ Assessment       │ │
│                      │              │ │ Reports          │ │
│                      │              │ │ Findings         │ │
│                      │              │ │ Activity         │ │
│                      │              │ │ Tool Catalog     │ │
│                      │              │ │ Market           │ │
│                      │              │ │ Connections      │ │
│                      │              │ │ Settings         │ │
│                      │              │ │ Assistant preview│ │
│                      │              │ └──────────────────┘ │
├──────────────────────┤              ├──────────────────────┤
│ Bottom Navigation    │              │ Bottom Navigation    │
└──────────────────────┘              └──────────────────────┘
```

### 10.3 Gerak dan perilaku

- Handle kecil di sisi kiri/kanan layar, area sentuh minimal 48dp dengan semantics (`Open quick access panel`). Handle dapat dibuka dengan tap dan swipe menuju tengah.
- Panel bisa dismiss dengan tap close, swipe keluar, system back; modal semantics dan fokus keyboard harus benar.
- Posisi handle diubah dengan drag vertikal dan dapat berpindah sisi menggunakan drag horizontal atau kontrol `Move to left/right` di panel. Jangan meminta gestur presisi tinggi sebagai satu-satunya cara.
- Snap ke zona aman vertikal, simpan sisi dan offset relatif (bukan pixel absolut) di preferensi aplikasi setelah rancangan/approval. Clamp ulang saat orientasi/ukuran layar berubah. Penyimpanan ini tidak memerlukan schema database.
- Minimalkan: panel menutup kembali ke handle. Saat keyboard terbuka atau halaman memasuki alur input/konfirmasi kritis, handle/panel harus menghindari field dan tidak menghalangi gesture system.
- Shortcut membuka destinasi/sub-view yang sama seperti navigasi utama; selected tab diperbarui dan panel tertutup. Jangan membuat layar kloning.
- Jumlah pintasan awal dibatasi pada item yang benar-benar tersedia. Item masa depan disembunyikan, bukan tampil seolah bisa dipakai.
- Panel tidak auto-open, tidak berdenyut terus-menerus, dan tidak menutupi Bottom Navigation.

### 10.4 Aksesibilitas dan keamanan

Urutan fokus logis, label screen-reader, close yang mudah dijangkau, dukungan switch/accessibility gestures, ukuran teks adaptif, kontras, reduced motion. Panel tidak menampilkan target sensitif, recent command, credential, atau detail finding tanpa navigasi/otorisasi yang sesuai. Audit privasi diperlukan bila posisi panel disimpan.

### 10.5 Edge Panel vs Floating Workspace

| Edge Panel | Floating Workspace masa depan |
|---|---|
| Shortcut navigasi tipis, selalu in-app | Area kerja/terminal yang dapat memuat konten/alat |
| Tidak mengeksekusi tool | Dapat berinteraksi dengan runtime jika disetujui |
| Data sama dengan halaman utama | Memerlukan data/session/context management tersendiri |
| Tidak membutuhkan izin overlay global | Tetap harus in-app; permission overlay global tidak termasuk rancangan ini |

## 11. Animasi dan interaksi

| Interaksi | Perilaku yang diusulkan | Guardrail |
|---|---|---|
| Navigasi tab | Fade/slide sangat halus atau transisi minimal | Hindari rebuild/animasi berat; jangan menunda aksesibilitas. |
| Globe idle | Rotasi lambat konstan atau statis | Tidak ada node/link saat idle; berhenti off-screen/background; patuhi reduced motion. |
| Glow | Perubahan opacity lembut pada aksen | Tidak berkedip/berdenyut cepat; no motion pada status error/high severity. |
| Assessment progress | Update pada outcome yang diterima; radar sweep hanya ketika run | Text status tetap sumber kebenaran; animasi tak boleh menciptakan hasil. |
| Gauge | Animasi singkat saat nilai nyata berubah, bukan loop | Unavailable state bukan animasi nol-ke-nilai. |
| Analytics | Crossfade sederhana ketika rentang berubah | Hindari animasi chart yang mengesankan data live. |
| Edge Panel | Slide in/out singkat dan handle drag | Hentikan saat reduced motion; tap/close tetap tersedia. |
| Loading | Skeleton statis/subtle shimmer jika performa memadai | Bedakan dari data kosong dan gagal; jangan tampilkan angka placeholder. |

Target durasi transisi sekitar 160–240ms sebagai titik awal prototype. Gerakan kontinu harus dihindari kecuali globe idle dan radar Assessment aktif. Gunakan `disableAnimations`, lifecycle app, visibility dan `TickerMode` dalam rancangan implementasi berikutnya.

## 12. Empty, unavailable, loading, error, partial states

| State | Copy/perilaku contoh |
|---|---|
| Empty findings | `No findings recorded in this view.` Subteks: `Ini bukan jaminan bahwa tidak ada risiko; hasil bergantung pada checks yang dijalankan.` |
| No assessment history | `No assessment history yet.` CTA `Start an assessment` menuju tab Assessment. |
| No reports | `No reports saved locally yet.` Bedakan hasil sesi terbaru yang belum disimpan dari riwayat tersimpan. |
| No Activity | `No activity recorded yet.` Tidak menyatakan tidak ada aktivitas sistem di luar app. |
| No topology | `Network topology unavailable.` Globe ilustrasi idle; tidak ada markers/connection arcs. |
| Score unavailable | `Security Score unavailable — methodology not defined.` Tidak ada angka, gauge fill, atau default 0. |
| Risk not calculated | `Risk level not calculated.` Tawarkan link ke Findings; severity counts bukan risk level. |
| Scan idle | `No assessment running.` Tampilkan CTA ke Assessment, bukan 0%. |
| Tool readiness loading | `Checking readiness…` untuk status resolver yang belum selesai. |
| Tool readiness error/unavailable | Label status aktual dan penjelasan safe; bukan “offline” kecuali status memang berarti demikian. |
| Analytics partial | `Showing loaded records only` serta count/rentang yang tersedia; jangan memberi label all-time. |
| Storage error | Pesan bahwa data lokal tidak dapat dimuat, tombol retry, Diagnostics jika sesuai. Jangan fallback ke angka 0 yang menyesatkan. |
| Stale data | `Last updated [time]`; jangan visualisasikan sebagai live. |
| Assistant unavailable | `AI/provider not connected. Assistant is not sending messages.` CTA koneksi atau tools lokal yang benar-benar tersedia. |

## 13. Komponen Flutter reusable yang diperlukan (usulan, belum implementasi)

Nama berikut adalah vocabulary desain, bukan komitmen file/class tertentu.

### Foundation

- `AppColorTokens`, `AppSpacing`, `AppRadii`, `AppTypography`, semantic status/severity theme.
- `PageScaffold` / `SectionHeader` / `StatusBadge` / `SourceAndFreshnessLabel`.
- `AccessibleIconAction` dengan semantic label dan touch target standar.
- `AsyncContentState` yang membedakan loading/empty/error/unavailable/partial/stale.

### Dashboard dan visualisasi

- `DashboardHeroCard`.
- `DigitalEarthView` dengan state `idle`, `loading`, `observed`, `stale`, `error`, `reducedMotion`; renderer visual idle dapat berbeda dari renderer topology data.
- `InstrumentCard`, `SecurityScoreGauge` (unavailable sampai kontrak disetujui), `RiskLevelIndicator`, `ScanProgressIndicator`.
- `AssessmentRadar` yang menerima status assessment eksplisit dan tidak memiliki data/animasi internal palsu.
- `AnalyticsCard`, `SeverityDistributionChart`, `AssessmentHistoryChart`, `ToolReadinessSummary`, `ActivityTimelineChart/List`; masing-masing menerima aggregate berlabel provenance, bukan melakukan query atau mengarang angka dalam painter.
- `DataScopeCaption` untuk rentang, jumlah records, sumber dan timestamp.

### Navigasi dan panel

- `PrimaryBottomNavigation` mempertahankan empat destination.
- `AssistantShortcut` dengan state placeholder/not-connected.
- `FloatingEdgeHandle`, `FloatingEdgePanel`, `QuickAccessItem`; hanya mengirim navigation intent ke `MainShell`.
- `ResponsiveContentFrame` untuk gutter/max-width dan adaptasi dua kolom.

### Prinsip arsitektur

- Komponen presentasional menerima nilai/status dan callbacks; repository tetap pemilik data.
- Chart menerima agregat immutable; format dan empty/error state seragam.
- Instrumen tidak membuat angka sendiri. View-model/selector mendefinisikan source, timestamp, validity, partialness dan limit.
- Hindari dependency graph/chart/3D sebelum desain/profiling menyatakan manfaatnya; pertimbangkan CustomPainter 2D sederhana atau package yang ringan bila disetujui.

## 14. Risiko performa Android kelas menengah

| Risiko | Risiko praktis | Kriteria mitigasi/verifikasi rancangan |
|---|---|---|
| Globe 3D/WebView/shader berat | GPU, memori, cold-start, baterai; potensi jank | Mulai dari 2D/layered vector; animasi satu layer; uji profile mode pada perangkat kelas menengah; tidak menjalankan loop di luar Home. |
| Beberapa grafik sekaligus | Repaint, layout, chart labels kecil, scrolling berat | Lazy build di bawah fold; chart 2D ringan; tampilkan ringkasan awal dan detail on-demand; painter harus repaint hanya saat data berubah. |
| Animasi kontinu | Baterai/GPU bahkan saat idle | Matikan off-screen/background/reduced motion; globe idle harus bisa statis. Radar hanya active Assessment. |
| Dashboard aggregate dari SQLite | Startup lambat atau hitungan tidak sinkron pada 500-limit | Jangan membuat query sync di build; gunakan cache/aggregate asynchronously dari repositories yang sama; tampilkan loading/scope. Tidak mengubah schema pada proposal ini. |
| Edge Panel overlay | Hit testing, keyboard overlap, touch conflict, accessibility | Batas safe area, dismiss/cancel sederhana, coverage widget tests untuk drag/keyboard/rotation/small viewport. |
| Font scaling & localized labels | Overflow/wrapping yang menggeser Bottom Navigation | Test Indonesian dan English, text scaling besar, landscape, lebar kecil; pakai label adaptif namun destinasi tak berubah. |
| Visual terlalu padat | Informasi utama tenggelam oleh dekorasi | Progressive disclosure; Digital Earth sebagai hero tetapi data/gauge dalam cards jelas; jangan semua modul menyala sekaligus. |
| Dataset capped/partial | Grafik tampak sebagai statistik keseluruhan padahal hanya sampel | Scope caption selalu hadir; paginasi/agregasi repository menjadi keputusan terpisah bila perlu. |

## 15. Tahapan implementasi yang disarankan (setelah persetujuan)

Tahapan ini bukan otorisasi implementasi saat ini. Masing-masing memerlukan review/izin sesuai tata kelola proyek.

1. **Review proposal:** konfirmasi sitemap, Assistant shortcut, visual hierarchy, edge panel, terminologi dan empty-state copy.
2. **Definisi data & metrik:** persetujuan metodologi Security Score (atau putuskan tidak ada), Risk aggregation, sumber progress, retention/privacy target data topology, periodisasi analytics. Tidak melakukan migration schema tanpa persetujuan terpisah.
3. **Wireframe high-fidelity/prototype:** ukuran HP kecil/umum/landscape, font scaling besar, Dashboard states (idle/active/partial/error), panel open/closed/dragged, Reports filters. Verifikasi Bottom Navigation tetap terlihat.
4. **Design review:** evaluasi keterbacaan, aksesibilitas, visual honesty, penempatan Assistant dan status prototype/future. Persetujuan eksplisit sebelum kode.
5. **Implementasi UI bertahap (izin terpisah):** visual foundation dan layout; navigasi/state retention; edge panel in-app; data-backed Dashboard cards/analytics; kemudian globe visual idle dan radar assessment yang state-driven. Jangan mulai mengimplementasikan Score sebelum metodologi disetujui.
6. **Validasi data dan keamanan UX:** pastikan provenance, sanitization, partial state, tidak ada target/sensitif yang bocor, status provider tidak dilebihkan, dan empty state tidak menyiratkan “secure”.
7. **Pengujian:** widget/golden, accessibility, reduced motion, localization, screen size/font scaling, navigation state, SQLite v4 existing tests, integration/persistence, profiling/perf Android. Cold-start emulator tetap perlu diverifikasi terpisah; proposal ini tidak mengklaim sudah tervalidasi.
8. **Milestone masa depan terpisah:** My Tools semantics, Runtime Manager, Terminal/Floating Workspace, AI Expert, KB, dan topology feed dirancang/disetujui secara terpisah sebelum implementasi.

## 16. Keputusan yang diminta dalam review

Untuk menutup Tahap 2, mohon tinjau/putuskan:

1. Apakah empat tab dipertahankan persis dengan label Home, Assessment, Reports, Settings? (Proposal: ya.)
2. Apakah Assistant shortcut tengah dipertahankan sebagai placeholder yang jelas, sambil akses dari Home/Settings tetap ada? (Proposal: ya untuk kontinuitas.)
3. Apakah Digital Earth idle memakai ilustrasi 2D berotasi halus, tanpa node/garis data? (Proposal: ya; reduced motion statis.)
4. Apakah Security Score tetap unavailable sampai metodologi dan data disetujui? (Proposal: ya.)
5. Apakah Risk Level ditunda sebagai angka/kategori keseluruhan sampai aturan agregasi disetujui, dengan Findings severity counts tetap boleh tampil? (Proposal: ya.)
6. Apakah Floating Edge Panel hanya pintasan in-app dan awalnya hanya item yang tersedia? (Proposal: ya.)
7. Setujukah bahwa Terminal, Runtime Manager UI, AI Expert, Knowledge Base, dan Floating Workspace disembunyikan dari UI aktif sampai milestone masing-masing siap? (Proposal: ya.)

## 17. Batas dokumen dan status

Proposal ini memperluas audit menjadi rancangan konseptual dan wireframe tekstual untuk ditinjau. Ia tidak mengubah implementasi, tidak menambah dependensi, tidak mengubah schema/database/backend, tidak mengubah Tool Registry/Orchestrator, dan tidak mengimplementasikan Digital Earth, gauges, analytics, Edge Panel, Workspace, Runtime, atau Terminal.

**Status akhir:** Menunggu koreksi dan persetujuan desain. Jangan lanjut ke implementasi otomatis sebelum persetujuan diberikan.
