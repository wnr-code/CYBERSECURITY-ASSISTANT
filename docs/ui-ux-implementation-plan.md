# Milestone 2B — UI Implementation Planning (Audit Mapping Only)

**Status:** Audit teknis dan rencana implementasi; belum ada implementasi yang dimulai
**Branch yang diperiksa:** `arena/02828d01-cybersecurity-assistant`
**HEAD aktual saat audit:** `0c88165ad80c22ff483a24f771dd3884ba072f4f`
**HEAD acuan dalam permintaan:** `88ad0e1e6745972e81198a8e2c1400746347b2c1`
**Tanggal audit:** 2026-11-23
**Desain acuan:** [`ui-ux-architecture-audit.md`](ui-ux-architecture-audit.md), [`ui-ux-design-proposal.md`](ui-ux-design-proposal.md), [`ui-ux-high-fidelity-prototype.md`](ui-ux-high-fidelity-prototype.md), aset di [`ui-ux-prototype-assets/`](ui-ux-prototype-assets/).

> Dokumen ini hanya memetakan implementasi UI/UX masa depan ke kode yang diperiksa pada working tree. Tidak ada kode aplikasi, tampilan, database, service, dependency, konfigurasi atau aset prototype yang diubah. Persetujuan desain tidak dianggap sebagai persetujuan implementasi.
>
> Catatan terbaru: audit ini tidak merancang install/uninstall provider modules. Arah Market modular yang dikonfirmasi pemilik dicatat terpisah di [Market Modular Delivery](market-modular-delivery.md); gunakan dokumen itu untuk scope distribusi Cloudflare/Gemini/Local AI.

## 1. Ringkasan kondisi kode saat ini

### 1.1 Navigasi dan ownership state

- Root halaman utama adalah `MainShell` dan `_MainShellState` di [`apps/android/lib/main.dart`](../apps/android/lib/main.dart#L178-L746). State tab primer saat ini sebuah `int _selectedIndex` dengan empat destinasi: Home, Assessment, Reports, Settings.
- Pada layar sempit (`MediaQuery.sizeOf(context).width < 760`), `_FloatingBottomNavigation` menampilkan empat destination dan tombol tengah `_AIChatNavButton`. Tombol AI membuka screen sekunder, bukan destination kelima. Tests yang ada menguji empat destination dan shortcut tengah.
- Pada lebar `>= 760` logical px, bottom bar saat ini disembunyikan dan `NavigationRail` digunakan ([main.dart](../apps/android/lib/main.dart#L623-L745)). Karena rancangan utama berorientasi HP, jangan ubah perilaku tablet tanpa keputusan responsivitas tersendiri; jangan menghapus Bottom Navigation pada layout HP.
- Page utama dirangkai dalam daftar `pages`, lalu child terpilih ditampilkan melalui `AnimatedSwitcher` dan `KeyedSubtree(ValueKey(_selectedIndex))` ([main.dart](../apps/android/lib/main.dart#L632-L700)). Ini berarti state lokal `ToolsScreen`/`ReportsScreen` berpotensi dibuat ulang ketika pengguna pindah destination. Edge Panel yang ingin membuka segmen nested harus menangani tujuan tersebut secara eksplisit, bukan memakai `GlobalKey` untuk mengontrol widget.
- State aplikasi dikelola dengan `StatefulWidget`/`setState`, constructor callbacks dan repository interfaces. Tidak ditemukan package state-management eksternal di `pubspec.yaml` atau pola provider terpusat.

### 1.2 Data dan persistence yang tersedia

| Sumber | Kondisi yang terlihat di kode | Batas yang harus dipertahankan |
|---|---|---|
| Result history | `MainShell` memakai `ResultHistoryStore`; `LocalResultStore.loadRecent()` default 30. `_recentResults` dibatasi 30; simpan/clear dan detail report memakai callback existing. | Hitungan yang bersumber dari list ini adalah current session/recent window, bukan total sejarah. Riwayat awal hanya sejumlah record yang dimuat. |
| Activity | `ActivityHistoryStore` di `LocalResultStore`; MainShell meminta hingga 500 event dan mengurutkan `startedAt`. Model memisahkan assessment/tool, status, target sanitized dan source link. | Analytics hanya mencakup item yang tersedia/dimuat; tidak ada dasar untuk label all-time atau real-time. |
| Findings | `FindingRepository` dan model `FindingRecord`; MainShell memuat hingga 500, menyortir berdasarkan `lastSeen`, serta bisa memperbarui status. Severity/confidence/status/source fields memang tersedia. | Severity count dapat dihitung dari records yang dimuat; belum ada agregasi Risk Level keseluruhan yang disetujui/diimplementasikan. |
| SQLite | `LocalResultStore` versi schema 4: `scan_results`, `activity_events`, `security_findings` ([local_result_store.dart](../apps/android/lib/core/local_result_store.dart#L21-L43)). | Rencana UI tidak memerlukan migration/schema baru. Jangan menyimpan preferensi panel di tabel hasil atau mengubah schema dalam milestone UI ini. |
| Tool readiness | `ToolRegistry` memuat empat app-owned P0 tools; Tool Catalog memanggil `ToolOrchestrator.statusForTool` dan menampilkan status async. | Registry count tidak sama dengan Ready count. Data readiness saat ini merupakan status resolver; tidak ada historical readiness series untuk chart tren. |
| Assessment state | `AssessmentRunner` menyimpan `_selected`, `_outcomes`, `_running`, authorization, target dan cancellation secara lokal di state widget; hasil diteruskan lewat callbacks. | MainShell/Dashboard saat ini tidak menerima live selected/outcomes/running state. Dashboard Progress/Radar tidak bisa menampilkan progress live tanpa kontrak state/callback baru. |
| Network | `Connectivity` hanya dipakai sebagai petunjuk Wi-Fi untuk diagnostics; komentar kode menyebut ini bukan bukti internet reachability ([main.dart](../apps/android/lib/main.dart#L42-L67)). | Tidak ada topology/network-node data source untuk Digital Earth. Jangan pakai Wi-Fi state, host hasil check, atau animasi sebagai jaringan teramati. |
| Preferences | `pubspec.yaml` memiliki `path_provider` dan `flutter_secure_storage`, tetapi tidak ada `shared_preferences` atau store khusus posisi UI yang ditemukan. | Credential storage bukan tempat yang tepat untuk posisi panel. Pilihan persistence lokal perlu dipisahkan dan tidak mengubah SQLite v4. |

Data history dimuat asynchronous setelah frame pertama; fungsi `_loadSavedResults`, `_loadActivityEvents`, dan `_loadFindings` berada di MainShell ([main.dart](../apps/android/lib/main.dart#L405-L430), [main.dart](../apps/android/lib/main.dart#L491-L580)). Pertahankan pola non-blocking ini agar Dashboard tidak menunggu query/aggregation untuk menampilkan first frame.

### 1.3 Ketidaksesuaian baseline / working tree

Saat audit dimulai:

- Branch aktual sesuai nama yang diwajibkan: `arena/02828d01-cybersecurity-assistant`.
- `git rev-parse HEAD` menghasilkan **`0c88165ad80c22ff483a24f771dd3884ba072f4f`**, bukan acuan `88ad0e1e6745972e81198a8e2c1400746347b2c1`.
- Working tree sudah tidak bersih sebelum dokumen ini dibuat: `README.md` berstatus modified; `.github/`, `.gitignore`, `apps/`, dan `docs/` berstatus untracked. Dokumen audit, proposal, prototype dan aset termasuk dalam `docs/` tersebut.

Karena itu, peta teknis ini mengacu pada isi file yang tersedia di working tree pada sesi ini, bukan klaim bahwa file tersebut seluruhnya tersimpan di HEAD acuan. Tidak ada file existing yang dibersihkan/di-reset. Perbedaan baseline dan dirty tree harus diselaraskan/review sebelum implementasi supaya test/build yang nanti dijalankan merepresentasikan baseline yang dimaksud. Jangan switch branch atau menghapus untracked files untuk memperbaikinya.

## 2. Pemetaan prototype ke file/widget Flutter

| Halaman/state prototype | Implementasi sekarang dan file | Reuse yang terlihat | Kebutuhan implementasi masa depan (belum dibuat) | Data/state dan persistence |
|---|---|---|---|---|
| **Home Dashboard** | `DashboardScreen` dan `_LocalFirstHero` di `main.dart` sekitar 953–1160; komponen metrik/section/empty state sekitar 2026–2160. `MainShell` memasok recent results dan saved count. | `_LocalFirstHero`, `_DashboardMetric`, `_DashboardSectionHeader`, `_ResultCard`, `_AssistantModuleCard`, `_EmptyState`, cards dan theme colors. | Ganti/perluas komposisi Dashboard sesuai hero Digital Earth; komponen `DigitalEarthHero` yang statis/idle; instrument cards; scope/freshness labels. Hindari rewrite seluruh `main.dart`. | Data saat ini dari MainShell: recent results (maks 30), saved result count (hasil `loadRecent`, default 30 saat load awal), registry length; belum ada findings/activity/status/assessment progress di Dashboard. SQLite tidak perlu berubah. |
| **Analytics** | Belum ada halaman/widget Analytics khusus. Prototype Analytics adalah bagian lanjutan scroll Dashboard. Data/model berada di `main.dart`, `local_result_store.dart`, `activity_timeline.dart`, `security_findings.dart`, `tool_registry.dart`. | `_EmptyState`, `_DashboardSectionHeader`, async loading/error state di MainShell, `FindingSeverity`, `ActivityKind/ActivityStatus`, `ToolStatus`. | Komponen tipis `DashboardAnalytics` / `AnalyticsCard`, `SeverityCounts`, `AssessmentHistorySummary`, `ActivitySummary`, `ToolReadinessSummary`, data scope caption. Chart awal dapat berupa bar/status rows menggunakan Flutter core; jangan tambah chart package tanpa approval terpisah. | Findings max 500, Activity max 500, recent results max 30; readiness live/resolved tanpa history series. Aggregation harus asynchronously menggunakan data yang sudah dimuat/repository; jangan membuat telemetry atau sample count. |
| **Assessment** | `ToolsScreen` dalam `main.dart` sekitar 2187–2423; `AssessmentRunner` di [`apps/android/lib/widgets/assessment_runner.dart`](../apps/android/lib/widgets/assessment_runner.dart#L12-L312). | SegmentedButton, `AssessmentRunner`, tool status FutureBuilder, checkbox/authorization, cancel token, outcome list/ExpansionTile. | Radar presentation state (idle/running/stopped) dan mungkin state callback tipis dari runner ke MainShell/dashboard. Tidak perlu membuat execution service baru atau mengganti Orchestrator. | Runner memegang `_running`, `_selected`, `_outcomes` lokal. `ToolOrchestrator` menjalankan check; Activity/Findings/Reports dipersist melalui interfaces existing. Progress ke Dashboard belum diekspos. |
| **Reports** | `_ReportContent.reports` dalam `ReportsScreen` di `main.dart` sekitar 1170–1926; route tab dikelola MainShell index 2. | SegmentedButton, `_ResultCard`, filters, `ListView`, dialog/detail dan local history state. | Penyesuaian presentasi agar serasi dengan design; state/loading/empty labels dan scope caption. Jika Edge Panel deep-link membuka Reports subsection, expose selected subsection secara deklaratif/callback. | ResultStore SQLite v4; session results volatile in-memory (maks 30), saved history asynchronous (`loadRecent()` default 30); ekspor/clear existing. Jangan ganti query semantics diam-diam. |
| **Findings** | `_ReportContent.findings`, `_StoredFindingCard`, `_FindingTag`, finding detail dialog dalam `ReportsScreen` (`main.dart` sekitar 1311–1675 dan 1774–1867). | `FindingRecord`, severity/status/confidence badges, current search/filter/status update, source report/activity callbacks. | Dashboard severity aggregate presentational card; navigasi cepat ke segmen Findings memerlukan controlled subsection selection API. Tidak perlu screen/table baru pada tahap pertama. | Repository memuat sampai 500 records; fields severity/status/confidence, dates, target sanitized, sources tersedia. Status update melalui repository; schema tetap v4. |
| **Activity** | `_ReportContent.activity`, `_ActivityCard`, `_ActivityDetailLine` dalam `main.dart` sekitar 1311–1692 dan 1710–1773. | Existing date/kind/status/tool/target filters, timeline cards, link ke source result. | Dashboard summary dan Edge Panel intent menuju Activity subsection; pastikan target aman dan loaded-scope ditampilkan. | `ActivityHistoryStore.loadActivities(limit: 500)` dan `ActivityEvent` (`assessment`/`tool`, statuses, timestamps). Data lokal saja; source refs opsional. |
| **Settings** | `SettingsScreen` di `main.dart` sekitar 1927–2025; route tetap destination index 3. | Locale dropdown, Cards/ListTile, callback open Assistant/Connections/Diagnostics, privacy/local storage disclosure. | Penyesuaian visual/spacing; lokasi edge-placement preference hanya jika nantinya ada kontrol pengaturan yang disetujui. Tidak perlu menaruh semua panel controls di Settings. | Locale berasal dari root app state/callback; tidak ditemukan persistence preference store khusus panel. Tidak perlu menyentuh AI/provider state. |
| **Connections** | `_openConnections()` mendorong `ConnectionsScreen` melalui `PageRouteBuilder`; `ConnectionsScreen` di `main.dart` sekitar 2479–2726. | Existing endpoint test, ProviderRegistry/search/category, status/prototype disclosures, `ProviderDetailsDialog`. | Edge Panel shortcut membuka route existing setelah panel ditutup. Penyesuaian hanya jika masuk scope desain; jangan menampilkan provider authenticated jika belum ada flow. | State form lokal di `ConnectionsScreen`; endpoint reachability terpisah dari authenticated provider. Tidak memakai database untuk placement panel. |
| **Edge Panel** | Belum ada implementasi. Titik integrasi yang paling dekat adalah `_MainShellState.build`, `Scaffold.body`, `_selectedIndex`, route callbacks dan `_FloatingBottomNavigation` di `main.dart` sekitar 202–810. | `SafeArea`, `Stack`, `Positioned`, `LayoutBuilder`, existing `Scaffold`, `_FloatingBottomNavigation`, callbacks `_selectDestination`, `_openMarket`, `_openConnections`, `_openDiagnostics`, `_openAssistantModule`. | Widget baru `FloatingEdgePanel`/`FloatingEdgeHandle` plus typed navigation intent dan `PanelPlacementStore` bila persistensi disetujui. Panel bukan system overlay. | Posisi belum punya provider; SQLite bukan tempatnya. Rekomendasi penyimpanan lokal file terpisah memakai `path_provider` yang sudah ada, setelah keputusan/review. |

### 2.1 Navigasi untuk nested destinations

Panel prototype menyediakan shortcut ke Reports, Findings, Activity, Tool Catalog, Market, Connections dan Assistant Preview. Destinasi top-level sudah dapat dipilih lewat `_selectDestination`; nested view saat ini dimiliki state private `_ReportsScreenState._content` dan `_ToolsScreenState._activeView`.

Implikasi: jangan pakai `GlobalKey`/deep widget lookup untuk memaksa segmen berubah. Sebelum panel mengirim shortcut nested, tambahkan kontrak navigation intent yang typed (misalnya target destination + subsection) di MainShell, lalu berikan subsection terpilih/callback ke screen terkait. Ini akan mengubah ownership state dan bisa memperbaiki/menambah state-retention. Untuk rollout paling aman, panel versi pertama dapat memakai shortcut top-level saja; aktifkan shortcut Findings/Activity/Tool Catalog setelah interface nested ditentukan dan dites.

## 3. Komponen reusable dan komponen baru

### Reuse, jangan digandakan

- Shell: `MainShell`, `_FloatingBottomNavigation`, `_BottomNavItem`, `_AIChatNavButton`, `_ModeBadge`.
- Dashboard: `_LocalFirstHero` hanya sebagai pola card/local-first disclosure (bukan globe renderer); `_DashboardMetric`, `_DashboardSectionHeader`, `_ResultCard`, `_AssistantModuleCard`, `_EmptyState`.
- Assessment: `ToolsScreen`, `AssessmentRunner`, status resolver `ToolOrchestrator`, outcome model dan cancellation.
- Records: `ReportsScreen`, `_ResultCard`, `_StoredFindingCard`, `_ActivityCard`, `_FindingTag`, filter controls dan details.
- Settings/Connections: `SettingsScreen`, `ConnectionsScreen`, provider/endpoint existing UI.
- Persistence/data: `LocalResultStore` v4, `FindingRepository`, `ActivityHistoryStore`, `ResultHistoryStore`, `ToolRegistry`/`ToolOrchestrator`.
- Foundation: Material cards/buttons, `SafeArea`, `ListView`, `Wrap`, `SegmentedButton`, existing localization helper `context.tr`.

### Komponen minimal yang mungkin perlu ditambah

| Komponen/abstraksi | Tanggung jawab | Saran batas |
|---|---|---|
| `FloatingEdgePanel` + `FloatingEdgeHandle` | In-app handle, open/close/minimize, panel layout, drag side/vertical | Presentational; tidak menyimpan data keamanan dan tidak memanggil Runtime/Tool. Parent memberi callbacks dan current placement. |
| `PanelPlacement` value object | Side kiri/kanan + normalized vertical fraction + version | Clamp dan validate saat load/resize; unit test murni tanpa widget. |
| `PanelPlacementStore` | Baca/tulis preferensi placement | File app-private terpisah menggunakan `path_provider` existing. Default placement jika file hilang/corrupt. Tidak pakai SQLite findings/results atau credential store. |
| `AppNavigationIntent` / typed destination target | Memetakan shortcut ke primary tab dan optional subsection | Dikelola MainShell; tidak mengganti empat index/top-level destinations. Hindari `GlobalKey` dan route duplikat. |
| `DigitalEarthHero` | Ilustrasi 2D idle/no topology; aksesibilitas semantics | Tidak menerima connectivity/Wi-Fi sebagai topology. Jika feed tidak ada, hanya renderer ilustratif dan status “data topology tidak tersedia”. |
| `SecurityInstrumentCard` / `GaugeTrack` | Presentasi status Score, Risk, Progress terpisah | Track kosong/Unavailable/Not calculated/Idle; jangan memiliki algoritme score/risk di widget. |
| `AssessmentUiSnapshot` callback/value | Meneruskan state run dari AssessmentRunner jika progress Dashboard memang disetujui | Hanya snapshot aktual: selected count, outcomes, running/cancelled. `AssessmentRunner` tetap pemilik execution. |
| `DashboardAnalytics` + summary rows | Severity counts, assessment event summary, activity summary, readiness summary | Data scope/timestamp/loading/error; menerima hasil agregasi dari provider, bukan memalsukan nilai dalam chart painter. |
| `DataScopeCaption` (opsional) | Menyebut sumber, loaded count, rentang/timestamp | Reusable pada Dashboard dan Records. |

Tidak perlu provider state management baru untuk MVP jika callbacks dan immutable view model cukup. Tidak perlu library chart khusus pada milestone pertama. Jangan buat `SecurityScoreService` atau `RiskEngine` sebelum metodologi bisnis disetujui.

## 4. Rencana teknis Edge Panel

### 4.1 Integrasi tanpa mengganti navigasi

1. Pertahankan `Scaffold.bottomNavigationBar` yang sudah dipakai di HP dan `_AIChatNavButton`; empat destination tidak berubah.
2. Tempatkan handle/drawer dalam `Stack` yang dibatasi area konten `Scaffold.body`/`SafeArea`, bukan `OverlayEntry`, Android window, service, atau root overlay global. Bottom Navigation adalah sibling terpisah sehingga panel/scrim tidak menerima tap di area bar.
3. `NavigationRail` wide layout yang ada tidak disentuh dalam implementasi phone-first tanpa keputusan tablet; hindari menggambar panel di atas rail atau mengubah breakpoint 760 secara tidak sengaja.
4. Panel menerima navigation callbacks dari `MainShell`; tidak punya repository atau runtime dependency.
5. Pada tap shortcut: tutup panel dahulu, kemudian pilih top-level destination atau mengirim typed nested intent. Untuk route pushes (Connections/Market/Assistant), tutup panel sebelum `Navigator.push`; saat route pop, panel kembali closed.

### 4.2 Model posisi dan persistence lokal

- Model minimal: `side = left | right`, `verticalFraction ∈ [0,1]`, `version`. Nilai vertikal relatif pada area aman yang memang dapat dipakai, bukan seluruh physical screen.
- Snap/drag center dihitung dari tinggi viewport setelah mengecualikan status/app bar, system safe areas, keyboard inset dan bottom-navigation region. Handle memiliki inset dari tepi dan clamp min/max top/bottom.
- Re-clamp dan hitung posisi pixel dari fraction pada resize, orientation change, font/layout changes, atau perubahan safe-area. Jangan persist posisi pixel yang tidak valid pada device lain.
- Simpan pada drag-end, bukan setiap pointer move; batasi write frequency. Jika posisi preference gagal dibaca/ditulis atau data invalid, pakai default (contoh: right-middle) dan lanjutkan aplikasi tanpa crash.
- Tidak ada `shared_preferences` di dependencies saat ini. Karena SQLite schema harus tetap v4 dan credential store tidak semestinya menyimpan setting UI, kandidat ringan adalah JSON kecil di app-private support directory memakai `path_provider` yang sudah ada. Keputusan format/lokasi final dan error handling harus direview sebelum implementation. Tidak menambah dependency dalam rencana ini.
- Posisi tidak sensitif, tetapi tetap app-private. Hindari menyimpan target, finding, credential, atau data assessment sebagai bagian dari preferences panel.

### 4.3 Lifecycle, page changes, dan batas tumpang tindih

- `_MainShellState` menjadi owner `isOpen`, `isMinimized`, placement dan pending `AppNavigationIntent`, sehingga handle konsisten saat tab berpindah.
- Tab berubah: tutup drawer; handle dapat tetap di sisi/offset yang sama (placement persisted). Tidak merender overlay baru di masing-masing halaman.
- Nested route dibuka: close dahulu; panel tidak tetap terapung di atas `ConnectionsScreen`, `MarketScreen`, dialog, atau Assistant route. Saat kembali ke MainShell default closed.
- System back saat drawer terbuka menutup drawer lebih dahulu; klik outside/dismiss memberi semantik yang konsisten. Focus dikembalikan ke handle ketika panel tutup.
- Scrim dan hit testing hanya berada pada konten utama; Bottom Navigation tetap dapat dilihat dan tidak tertutup. Handle min/max y tidak intersect dengan bar.
- Saat keyboard visible (`MediaQuery.viewInsets.bottom > 0`) atau form/authorization flow aktif, sembunyikan/relokasi handle dan tutup panel agar target field, keyboard action, run/cancel controls dan private-target consent tidak tertutup. Kembalikan placement setelah keyboard ditutup.
- `SafeArea`/view padding harus dihitung dari viewport lokal; pada gesture navigation hindari edge gestures OS dan status/navigation bars. Handle harus bisa dipindah dari kiri ke kanan lewat drag/explicit action, bukan melalui tap kecil saja.
- Compact-first; treatment tablet/landscape belum ditetapkan. Untuk layout lebar, pilih hide panel atau pin di batas content setelah evaluasi; jangan duplikasi NavigationRail dan jangan menutup rail.

## 5. Rencana teknis Dashboard

### 5.1 Digital Earth

- **Source saat ini:** tidak ada provider topology. Connectivity plugin memberi Wi-Fi hint untuk diagnostics saja; itu bukan network map, internet reachability, serangan atau node. Data target assessment juga bukan topology.
- **MVP visual:** ilustrasi vector/CustomPainter 2D dengan graticule/rim glow statis atau animasi sangat lambat yang hanya aktif ketika Home terlihat dan motion diizinkan. State harus menyebut topology unavailable/illustrative; tanpa markers/arcs/routes/blips.
- **Interaksi/data masa depan:** network nodes/edges baru boleh ditampilkan setelah ada data-source/permission/provenance, freshness, sanitization, privacy policy dan kontrak visual yang disetujui. Target assessment tidak boleh dipetakan sebagai serangan.
- Digital Earth tidak memerlukan database, backend, Registry ataupun Connectivity sebagai data provider. Widget idle yang menerima status unavailable cukup untuk tahap visual pertama.

### 5.2 Security Score, Risk Level, Scan Progress, Radar

| UI | Sumber aktual yang ada | Rencana aman |
|---|---|---|
| Security Score | Tidak ditemukan model/algoritme/metodologi score pada widget dan core yang diaudit. | Tampilkan unavailable/“metodologi belum tersedia” dan ring neutral. Jangan render angka, fill/needle atau default 0. Tidak buat algoritme sampai definisi input, coverage, weighting, confidence, freshness/partial rules disetujui. |
| Risk Level | `FindingRecord.severity`, `confidence`, `status` tersedia; tidak ada overall risk aggregation yang disetujui. | Tampilkan “belum dihitung”; boleh tampilkan jumlah Findings per severity dari records yang benar-benar dimuat, dengan scope. Counts bukan overall Risk Level. |
| Scan Progress | `AssessmentRunner` memegang selected IDs, outcomes, `_running`, cancel dan reports. | Assessment page dapat menggambar progress dari state lokal. Untuk Dashboard, expose read-only `AssessmentUiSnapshot` callback ke MainShell; saat idle/tiada state, tunjukkan Idle, bukan 0%. Progress denominator adalah checks terpilih/valid, bukan registry length. |
| Security Radar | Tidak ada dashboard radar. AssessmentRunner tahu status berjalan dan outcome aktual. | Idle statis. Sweep hanya saat `running=true`; berhenti pada completed/failed/cancelled dan mengikuti reduced motion. Radar merepresentasikan pekerjaan assessment, bukan sensor ancaman. |

Lift progress ke MainShell adalah perubahan state/navigation yang nontrivial: callback harus menangani unmount saat user mengganti tab, cancellation, assessment selesai, error, dan stale snapshot. Alternatif safest first pass adalah menampilkan ringkasan `No assessment running` di Home dan hanya menampilkan radar/progress live di halaman Assessment. Jika live progress lintas halaman tetap dibutuhkan, prototipe acceptance harus menetapkan behavior ketika tab berganti terlebih dahulu.

### 5.3 Analytics dan data scope

- **Findings severity:** agregasi per enum severity dari `_findings` atau repository; cap yang dimuat saat ini 500. Filter status yang dipakai harus jelas, dan zero/empty tidak berarti “aman”.
- **Assessment history:** derive hanya dari `ActivityEvent.kind == assessment` dan status/timestamp aktual. MainShell memuat 500 activity events. UI harus menyebut loaded records/rentang; tidak menampilkan total all-time.
- **Activity summary:** events `assessment` dan `tool` dari Activity store; tidak mengasumsikan setiap tool result identik dengan assessment run. Existing `parentEventId`/source fields dipakai untuk dedup/source linking.
- **Tool status:** resolver `ToolOrchestrator.statusForTool`/`availabilityForTool`. Tampilkan snapshot per tool/status yang berhasil dimuat; tidak ada historical series. Jangan chart tren status tanpa event history.
- **Reports/check statistics:** `recentResults` session cap 30; `LocalResultStore.loadRecent()` default 30. “Saved locally” Dashboard saat ini menghitung jumlah hasil yang termuat, bukan query `COUNT(*)` semua report. Tetap label loaded/recent; jangan menyebut total database kecuali repository count API terpisah disetujui.
- Analytics sebaiknya menambah presentation selector/helper async yang menerima repositori/view-model, bukan melakukan synchronous SQLite reads di `build`. Pertahankan loading/empty/error/partial distinctions dan first-frame behavior.
- Tidak ada chart dependency saat ini; tahap awal dapat memakai summary row/simple bars lewat Flutter existing primitives, dengan aksesibilitas tekstual. Library chart baru perlu approval terpisah.

## 6. Strategi responsivitas

Frame prototype 390 × 860 dp adalah target komposisi, bukan fixed design constraint. Existing tests punya widget view 390 × 844 dan narrow 320 × 720; aplikasi juga mengadaptasi pada breakpoint 760 dan max-width 960/760. Belum ada bukti model Redmi tertentu telah diuji.

| Kondisi | Observasi/kebutuhan rencana |
|---|---|
| 390 × 860 dp | Jadikan ukuran awal golden/widget scenario; scroll Dashboard hero → instruments → Analytics, empat destination + center shortcut tetap terlihat. Jangan menganggap status/navigation system bar termasuk dalam tinggi usable. |
| Lebar < 360 dp | `DashboardMetric` sekarang memiliki fixed width 150 dan menggunakan `Wrap`; periksa stacking/spacing. Floating bar membagi ruang untuk 4 tab + AI center; pastikan text/48dp targets tidak menyempit atau overflow. Hero globe harus mempertahankan aspect/diameter dan label tidak clip. |
| Font scale besar | Semua title/labels/cards harus wrap/scroll; jangan hardcode gauge text width atau drawer list height. Segmented reports labels dan bottom navigation perlu diuji dalam Indonesian/English. |
| Keyboard | `Scaffold`/`SafeArea` dan `viewInsets` mengubah usable region. Edge Panel ditutup/disembunyikan; scroll target/checkbox/run/cancel harus tetap accessible. Test Assessment target field dan Connections endpoint field. |
| System gestures / safe area | Handle offset dihitung dari `MediaQuery.padding/viewPadding`; tidak ditempatkan di system edge gesture strip atau di bawah bottom bar. Panel/scrim hanya di app viewport. |
| Orientation/resize | Persist vertical fraction, clamp ulang dan orientasi kiri/kanan; periksa landscape dan split-screen agar panel tidak menutupi rail/navigation. |
| Dynamic content | Use `LayoutBuilder`, `Wrap`, `Expanded`, `ConstrainedBox` dan vertical scroll. Hindari nilai frame PNG menjadi pixel constant Flutter. |

Hambatan yang sudah terlihat untuk diuji: `_DashboardMetric` width 150; `_LocalFirstHero` memakai constraints relative to screen width; dialog finding memberi `SizedBox(width: 520)` yang perlu dicek pada phone; `NavigationRail` mengambil alih bar pada `>=760`; labels/navigasi localization panjang; modal/scrim/keyboard dapat berinteraksi dengan panel.

## 7. Risiko regresi dan mitigasi

| Risiko | Dampak yang mungkin | Mitigasi/guardrail |
|---|---|---|
| HEAD/current tree tidak sama dengan acuan dan working tree pre-dirty | Perubahan/testing nanti bisa dibandingkan dengan baseline yang salah; file yang tampak untracked tidak punya baseline tracked yang dapat di-diff. | Sebelum implementasi, pemilik/agent mengklarifikasi commit acuan dan menangani status Git tanpa menghapus/meng-reset untracked. Tidak switch branch atau melakukan cleanup otomatis. |
| Bottom Navigation/AI shortcut berubah ruang atau semantics | Tab hilang, tengah terlihat sebagai tab kelima, test existing gagal | Reuse `_FloatingBottomNavigation`/`_AIChatNavButton`; pertahankan keys 0–3 dan `bottom-navigation-ai-chat`, localized labels; jalankan test existing 390/320 dp. |
| State `AnimatedSwitcher`/nested section hilang | Filter Tool Catalog/Findings/Activity reset; Edge Panel deep-link membuka subsection yang salah | Tentukan typed target dan owner state; tambah regression tests sebelum mengubah state ownership; jangan `GlobalKey`. |
| Panel menutup tombol atau area teks | Assessment/Connections form, keyboard, action buttons atau Bottom Navigation tidak dapat digunakan | Panel terbatas content viewport; close saat route/input; keyboard-aware; drag clamp; gesture/accessibility alternatives. |
| Preferences storage corrupt/failed | Crash saat shell startup, posisi di luar layar, write terlalu sering | Async read dengan fallback default; validate/version/clamp; write saat drag end; unit test corrupt/missing file; tidak blocking frame pertama. |
| False telemetry/score/risk | Pengguna salah mengira app menemukan jaringan/menilai keamanan | Dashboard widgets menerima typed actual state; `Unavailable/Not calculated/Idle` eksplisit; no invented values/markers; source and limits visible. |
| Salah aggregate / cap records | Statistik tampak all-time padahal hanya recent 30 atau loaded 500 | Caption scope/time range; definisi per aggregate; jangan label total count kalau hanya `List.length`; test batas 30/500. |
| Perf/motion | Startup/jank/battery buruk di Android menengah | Vector 2D/light renderer; no heavy loop offscreen; reduced motion; async data; profile scrolling/panel drag; no new chart package without need. |
| Localization/font scaling | Text overflow, inaccessible tiny hit areas | L10n keys, large text and 320 dp tests, semantics labels, 48dp targets, scrollable panels. |
| Assessment workflow regression | Authorization/cancel/status/results/Activity/Findings persistence berubah | Jangan ubah Orchestrator or runner execution path. Add read-only progress callback only if approved; keep existing runner tests and cancellation/authorization tests. |
| Reports / SQLite regression | Schema/history clear/save/findings references rusak | UI-only read models; no migration; run local_result_store/findings/activity/widget regression tests in implementation milestone. |
| Route stack/panel layering | Panel tertinggal di atas Market/Connections/Assistant atau back menutup route yang salah | Close before push; back first closes open panel; route pop returns shell with panel closed. Test route stack. |

## 8. Urutan implementasi yang paling aman (rencana masa depan)

Urutan ini adalah rekomendasi dependensi, **bukan** izin mulai coding.

### Tahap 0 — Baseline dan kontrak acceptance

- Klarifikasi mismatch actual HEAD `0c88165…` vs requested `88ad0e1…`, dan working tree pre-dirty/untracked; simpan semua dokumen/assets.
- Konfirmasi target Redmi/model, minimum width, tablet/landscape scope, font-scale/accessibility targets.
- Setujui definisi source/scope untuk Score/Risk/Progress; untuk Score/Risk, keputusan dapat berupa tetap unavailable.
- Tetapkan perilaku panel pada pindah tab, route push/pop, keyboard, app restart, orientation dan data corruption.
- Ambil baseline test/build yang relevan hanya setelah source snapshot diputuskan.

### Tahap 1 — Navigation intent & state contract

- Tulis typed navigation target yang mempertahankan empat top-level destinations dan center AI shortcut.
- Tentukan apakah Reports subsection dan Tools Catalog subsection state dikendalikan parent atau hanya top-level shortcut dulu.
- Tambah widget tests untuk tab selection, center assistant route, back, subsection restoration dan compact viewport.
- Jangan refactor semua routing atau mengganti rail/bottom behavior sekaligus.

**Dependensi:** Tahap 0; menjadi prasyarat shortcut Edge Panel ke nested screen.

### Tahap 2 — Reusable responsive Dashboard shell + honest static states

- Pecah/isolasi `DigitalEarthHero`, `SecurityInstrumentCard`, `DataScopeCaption` dan shared async states, tanpa membongkar keseluruhan `main.dart`.
- Implement Digital Earth static/idle only; score unavailable; risk not calculated; progress idle. No fake network/data.
- Verify 390 × 860, 320 × 720, large text, localization, reduced motion.

**Dependensi:** visual acceptance + Tahap 1 untuk Dashboard navigation callbacks.

### Tahap 3 — Data-backed Dashboard analytics

- Tambah selectors untuk loaded Findings severity counts, Activity/Assessment summaries dan current tool readiness.
- Pertahankan caps/scope labels serta async error/empty/partial states; hindari query di build.
- Progress live ke Dashboard bersifat opsional dan baru dilakukan bila state callback dari AssessmentRunner disetujui/ditest; jika tidak, Home hanya menunjukkan idle summary dan progress live di halaman Assessment.

**Dependensi:** source definitions dari Tahap 0 dan UI foundation Tahap 2.

### Tahap 4 — In-app Floating Edge Panel

- Buat `FloatingEdgePanel`, handle, placement model/store. Mount dalam MainShell `Stack`, di atas content saja dan di bawah bottom-bar layer.
- Implement default placement, drag/snap left/right/up/down, open/closed/minimized, close on route/navigation/keyboard, route intent dan preference fallback.
- Tidak menambah permission/global overlay, tidak menggunakan SQLite, tidak mengeksekusi tool.

**Dependensi:** navigation contract Tahap 1; safe-area/layout utilities Tahap 2; placement persistence decision Tahap 0.

### Tahap 5 — Regression hardening dan device review

- Widget/golden + accessibility + manual Redmi test matrix; data provenance; gesture/keyboard/orientation; storage restart/failure.
- Verifikasi invariants bottom nav, AI preview, Assessment authorization/cancellation, Reports save/clear, Findings/Activity source linking dan SQLite schema v4.
- Lakukan profile/perf pada perangkat yang ditetapkan. Pertahankan Terminal/Runtime/AI Expert/KB/Floating Workspace di luar scope.

**Dependensi:** Tahap 1–4 yang disetujui; implementasi dilaksanakan hanya setelah persetujuan terpisah.

## 9. Kriteria penerimaan dan pengujian nanti

### Navigasi

- Empat destination Home, Assessment, Reports, Settings masih ada dan fungsinya tidak berubah.
- Center AI Preview tetap shortcut sekunder; tidak dihitung sebagai primary destination.
- Perpindahan destination dari bar/Edge Panel memperbarui selection secara benar; nested Findings/Activity/Tool Catalog membuka section yang diminta atau secara eksplisit membuka top-level Reports/Assessment.
- Existing tests `floating mobile navigation has four destinations...`, narrow viewport test, AI secondary route dan language test tetap lulus.

### Dashboard dan provenance

- Digital Earth idle jelas ilustrasi/no topology; tidak menggunakan Wi-Fi, target host, random/simulated coordinates, attack nodes atau fake links.
- Score selalu unavailable sampai metodologi approved; Risk Level overall tidak tampil sebelum agregasi approved; Findings counts punya severity source dan loaded scope.
- Progress/Radar hanya aktif berdasarkan Assessment state yang nyata; idle bukan 0%, completed/fail/cancel berhenti dan label akurat.
- Analytics menampilkan loading/empty/error/partial; cap recent 30 / loaded 500 / current registry readiness tidak disamarkan sebagai all-time.
- Query/aggregation tidak menahan first frame dan tidak mengubah struktur/schema SQLite v4.

### Edge Panel

- Closed/open/minimized; kiri/kanan; drag vertikal; default/fallback; normalized placement survive app restart bila storage diaktifkan.
- Tidak ada system overlay permission atau Android manifest change.
- Bottom Navigation, form/action, keyboard, safe area, OS gestures tetap dapat diakses.
- Tap shortcut menutup panel dan menavigasi ke existing page; route push menutup panel; back behavior predictable.
- Missing/corrupt preference fallback aman, orientation resize re-clamp, write hanya setelah drag selesai.

### Responsivitas dan aksesibilitas

- Widget/golden test minimal pada 390×860, existing 390×844, 320×720, dan ukuran/model Redmi yang disepakati; landscape dan split view bila scope.
- Large text scale dan Indonesian/English tidak overflow; vertical scroll tetap berfungsi.
- Target utama minimum 48dp, semantics screen-reader/focus order, keyboard navigation dan contrast check.
- `disableAnimations`/reduced motion statis; panel/globe tidak terus bergerak offscreen/background.

### Regression/data

- Tools, Assessment authorization/cancel/outcomes, Report save/load/clear, Findings status update, Activity filters/source links tetap berperilaku sama.
- Jalankan test terkait `widget_test.dart`, `local_result_store_test.dart`, `activity_timeline_test.dart`, `security_findings_test.dart`, dan core/tool tests yang terdampak pada milestone implementasi; tidak perlu dijalankan dalam audit dokumentasi ini.

## 10. File yang kemungkinan terdampak pada implementasi berikutnya

**Daftar prospektif; tidak ada file ini yang diubah pada Milestone 2B.**

### Kemungkinan perubahan

- `apps/android/lib/main.dart` — MainShell, nav intent, Dashboard composition, Reports/Tools subsection handoff, Edge Panel mount; saat ini juga memuat banyak widgets/screens sehingga perubahan harus dibatasi.
- `apps/android/lib/widgets/assessment_runner.dart` — hanya jika Dashboard live-progress memerlukan callback snapshot; jangan ubah execution/orchestration semantics.
- `apps/android/lib/l10n/app_localizations.dart` — label/state baru (Digital Earth unavailable, scope, panel actions, statuses).
- `apps/android/lib/core/local_preferences_store.dart` **(calon file baru)** atau `apps/android/lib/core/panel_placement_store.dart` **(calon file baru)** — persistence preferensi app-private terpisah; keputusan akhir perlu review.
- `apps/android/lib/widgets/floating_edge_panel.dart` **(calon file baru)** — handle/drawer/drag/clamp.
- `apps/android/lib/widgets/digital_earth_hero.dart` **(calon file baru)** — visual idle/topology unavailable.
- `apps/android/lib/widgets/security_instruments.dart` **(calon file baru)** — score/risk/progress states; no score algorithms.
- `apps/android/lib/widgets/dashboard_analytics.dart` **(calon file baru)** — data scope/status cards dan simple data display.
- Test baru yang mungkin: `apps/android/test/floating_edge_panel_test.dart`, `apps/android/test/panel_placement_store_test.dart`, `apps/android/test/dashboard_analytics_test.dart`; atau tambahkan cases terarah ke `widget_test.dart`.

### Tidak direncanakan berubah untuk UI-only milestone ini

- `apps/android/lib/core/local_result_store.dart` dan schema v4.
- `apps/android/lib/core/tool_registry.dart`, `tool_orchestrator.dart`, `runtime_manager.dart`, policy/security tools dan backend.
- `apps/android/pubspec.yaml` (tidak menambah dependency).
- Android manifest/native window permission (tidak ada global overlay).
- Assessment/Reports execution/persistence contract, kecuali callback presentasi kecil dan disetujui.
- Tidak ada Terminal, Runtime Manager UI, AI Expert, Knowledge Base atau Floating Workspace.

## 11. Pertanyaan/ketidakpastian yang harus dibereskan sebelum implementasi

1. Mengapa HEAD aktual `0c88165…` berbeda dari HEAD acuan `88ad0e1…`, dan bagaimana perubahan `README.md` serta direktori untracked akan diperlakukan? Jangan reset/clean tanpa keputusan pemilik.
2. Model Redmi mana yang menjadi perangkat target? Apakah tablet/layout `NavigationRail` ikut scope?
3. Apakah MVP Dashboard perlu live progress saat user berpindah dari Assessment, atau cukup progress/radar hanya di halaman Assessment dan idle di Home?
4. Apakah initial Edge Panel berisi shortcut nested Findings/Activity/Tool Catalog pada rilis awal, atau hanya primary tabs sampai navigation intent dan state retention siap?
5. Di mana lokasi/cara penyimpanan preferensi yang disetujui? Rekomendasi audit ini: file kecil app-private melalui `path_provider` yang sudah ada; bukan SQLite dan bukan credential storage.
6. Adakah definisi score/risk yang disetujui? Bila belum, komponen tetap unavailable/not calculated.
7. Apakah analytics harus mencakup semua sejarah atau hanya loaded/recent window? Implementasi sekarang hanya menyediakan limits/list snapshots yang disebut di atas.

## 12. Batas audit dan validasi milestone ini

Pemeriksaan dilakukan dengan membaca working tree dan Git metadata. Tidak ada test suite yang dijalankan karena tidak ada perubahan kode. Validasi yang dilakukan setelah dokumentasi adalah status Git, branch, HEAD dan whitespace dokumen. File/direktori untracked yang sudah ada dipertahankan.

**Kesimpulan:** Implementasi dapat dikerjakan tanpa menyentuh schema v4 atau backend, tetapi Edge Panel membutuhkan kontrak navigation/state dan preferensi lokal baru; Dashboard tidak memiliki topology/score/risk/live-progress provider yang lengkap. Risiko terbesar sebelum coding adalah baseline git yang tidak cocok/dirty, diikuti state nested destinations dan potensi klaim metrik/data yang tidak didukung.

**Status akhir: hanya rencana audit. Berhenti di sini dan tunggu review serta persetujuan implementasi yang terpisah.**
