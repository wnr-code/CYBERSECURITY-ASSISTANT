import 'package:material_ui/material_ui.dart';

import '../core/provider_registry.dart';
import '../core/secure_credential_store.dart';
import '../l10n/app_localizations.dart';

String _providerDescription(String id, BuildContext context) => switch (id) {
      'cloudflare_workers' => context.tr('API serverless milik Anda untuk menyambungkan layanan sendiri.'),
      'firebase_auth' => context.tr('Autentikasi Firebase opsional untuk project milik Anda.'),
      'firebase_functions' => context.tr('Fungsi serverless dalam project Firebase milik Anda.'),
      'supabase' => context.tr('Database Postgres dan layanan Supabase milik Anda.'),
      'cloudflare_d1' => context.tr('Database SQL D1 milik Anda; akses sebaiknya melalui Worker.'),
      'firebase_firestore' => context.tr('Database dokumen Cloud Firestore milik Anda.'),
      'cloudflare_r2' => context.tr('Penyimpanan objek S3-compatible milik Anda.'),
      'firebase_storage' => context.tr('Penyimpanan file Firebase milik Anda.'),
      's3_compatible' => context.tr('Penyimpanan objek yang kompatibel dengan S3.'),
      'webdav' => context.tr('Endpoint penyimpanan file WebDAV milik Anda.'),
      'openai' => context.tr('Penyedia model AI opsional menggunakan API key milik Anda.'),
      'gemini' => context.tr('Penyedia model AI Google opsional menggunakan API key milik Anda.'),
      'anthropic' => context.tr('Penyedia model AI opsional menggunakan API key milik Anda.'),
      'openrouter' => context.tr('Perute model AI opsional menggunakan API key milik Anda.'),
      'virustotal' => context.tr('API intelijen keamanan opsional; pengiriman indikator belum tersedia.'),
      'shodan' => context.tr('API intelijen eksposur internet opsional; pencarian belum tersedia.'),
      'urlscan' => context.tr('API pemindaian URL opsional; pengiriman URL belum tersedia.'),
      _ => context.tr('Endpoint layanan HTTPS pilihan Anda.'),
    };

String _providerGuidance(String id, BuildContext context) => switch (id) {
      'openai' => context.tr('Buat API key pada dashboard resmi OpenAI dan simpan hanya jika Anda memahami tagihan API. Aplikasi ini belum mengirim permintaan OpenAI.'),
      'gemini' => context.tr('Buat API key melalui Google AI Studio. Kunci hanya dapat disimpan lokal; pemanggilan Gemini belum diimplementasikan.'),
      'anthropic' => context.tr('Buat API key di Anthropic Console. Kunci hanya dapat disimpan lokal; pemanggilan Claude belum diimplementasikan.'),
      'openrouter' => context.tr('Buat API key di OpenRouter dan periksa biaya model. Kunci hanya dapat disimpan lokal; permintaan belum tersedia.'),
      'cloudflare_workers' => context.tr('Deploy Worker pada akun Anda dan gunakan endpoint HTTPS milik Anda. Aplikasi belum mengirim token atau memanggil Worker.'),
      'cloudflare_d1' => context.tr('Akses D1 lewat Worker milik Anda; jangan menaruh token administrator di aplikasi Android. Adapter belum tersedia.'),
      'cloudflare_r2' => context.tr('Gunakan bucket khusus dan akses terbatas. Aplikasi belum mengunggah atau mengunduh objek R2.'),
      'firebase_auth' => context.tr('Batasi aplikasi Android pada project Firebase dan siapkan Security Rules. SDK Firebase belum terpasang.'),
      'firebase_functions' => context.tr('Deploy fungsi pada project Firebase milik Anda. Aplikasi belum memanggil fungsi tersebut.'),
      'firebase_firestore' => context.tr('Aktifkan Authentication dan aturan Firestore yang ketat. Akses database belum diimplementasikan.'),
      'firebase_storage' => context.tr('Atur Storage Rules untuk identitas terautentikasi. Unggah/unduh belum tersedia.'),
      'supabase' => context.tr('Gunakan URL project Anda dan Row Level Security. Jangan gunakan service-role key di klien; konektor belum tersedia.'),
      's3_compatible' => context.tr('Gunakan bucket khusus dan kredensial berhak minimum. Akses S3 belum tersedia.'),
      'webdav' => context.tr('Gunakan HTTPS dan akun khusus. Operasi WebDAV terautentikasi belum tersedia.'),
      'virustotal' || 'shodan' || 'urlscan' => context.tr('Periksa syarat layanan dan dampak privasi sebelum mengirim indikator. Integrasi belum tersedia; kredensial tidak digunakan.'),
      _ => context.tr('Entri ini hanya panduan. Pemeriksaan koneksi generik tidak mengautentikasi layanan atau menguji konfigurasi provider.'),
    };

class ProviderDetailsDialog extends StatefulWidget {
  const ProviderDetailsDialog({super.key, required this.provider, this.credentialStore});
  final ProviderDefinition provider;
  final SecureCredentialStore? credentialStore;

  @override
  State<ProviderDetailsDialog> createState() => _ProviderDetailsDialogState();
}

class _ProviderDetailsDialogState extends State<ProviderDetailsDialog> {
  late final SecureCredentialStore _credentialStore;
  bool _busy = false;
  bool? _credentialPresent;
  String? _message;

  @override
  void initState() {
    super.initState();
    _credentialStore = widget.credentialStore ?? SecureCredentialStore();
  }

  SecureCredentialKind? get _credentialKind {
    if (widget.provider.authType == ProviderAuthType.apiKey) return SecureCredentialKind.apiKey;
    if (widget.provider.authType == ProviderAuthType.scopedToken) return SecureCredentialKind.accessToken;
    return null;
  }

  String _credentialLabel(BuildContext context) => switch (_credentialKind) {
        SecureCredentialKind.apiKey => context.tr('API key'),
        SecureCredentialKind.accessToken => context.tr('Access token'),
        null => context.tr('Credential'),
      };

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.provider.name),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(context.tr(providerCategoryLabel(widget.provider.category)), style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              Text(_providerDescription(widget.provider.id, context)),
              const SizedBox(height: 12),
              Text('${context.tr('Status')}: ${widget.provider.integrationImplemented ? context.tr('Tersedia') : context.tr('Panduan saja · belum terhubung')}'),
              Text('${context.tr('Autentikasi')}: ${context.tr(providerAuthLabel(widget.provider.authType))}'),
              const SizedBox(height: 12),
              Text(_providerGuidance(widget.provider.id, context), style: const TextStyle(height: 1.45)),
              const SizedBox(height: 12),
              if (_credentialKind != null) ...[
                const Divider(),
                Text('${context.tr('Status penyimpanan kredensial')}: ${_credentialPresent == null ? context.tr('belum diperiksa') : _credentialPresent! ? context.tr('tersimpan') : context.tr('belum disetel')}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _storeCredential,
                    icon: const Icon(Icons.key_outlined),
                    label: Text('${context.tr('Simpan')} ${_credentialLabel(context)}'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _checkCredential,
                    child: Text(context.tr('Periksa status penyimpanan')),
                  ),
                  if (_credentialPresent == true)
                    TextButton.icon(
                      onPressed: _busy ? null : _deleteCredential,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(context.tr('Hapus')),
                    ),
                ]),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(context.tr(_message!), style: TextStyle(color: Colors.white.withValues(alpha: .7))),
                ],
              ],
              const SizedBox(height: 12),
              Text(
                context.tr('Kredensial tersimpan belum dikirim ke provider. Permintaan terautentikasi dan uji koneksi khusus provider belum dibuat.'),
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('Penyimpanan memakai plugin secure storage platform. Perilaku Android belum diuji pada perangkat; jangan masukkan secret produksi sebelum verifikasi perangkat selesai.'),
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Tutup')))],
      );

  Future<void> _storeCredential() async {
    final kind = _credentialKind;
    if (kind == null) return;
    final secret = await showDialog<String>(
      context: context,
      builder: (_) => _CredentialInputDialog(label: _credentialLabel(context)),
    );
    if (secret == null || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _credentialStore.save(providerId: widget.provider.id, kind: kind, secret: secret);
      if (mounted) {
        setState(() {
          _credentialPresent = true;
          _message = 'Credential stored locally. No provider request was made.';
        });
      }
    } on SecureCredentialException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Secure storage is unavailable on this build.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkCredential() async {
    final kind = _credentialKind;
    if (kind == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final stored = await _credentialStore.read(providerId: widget.provider.id, kind: kind);
      if (mounted) {
        setState(() {
          _credentialPresent = stored != null;
          _message = stored == null ? 'No credential is stored.' : 'A credential is stored; its value was not displayed.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Secure storage is unavailable on this build.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCredential() async {
    final kind = _credentialKind;
    if (kind == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Hapus kredensial tersimpan?')),
        content: Text(context.tr('Kredensial provider ini akan dihapus dari penyimpanan aman.')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(context.tr('Batal'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(context.tr('Hapus'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _credentialStore.delete(providerId: widget.provider.id, kind: kind);
      if (mounted) {
        setState(() {
          _credentialPresent = false;
          _message = 'Credential deleted.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not delete the stored credential.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _CredentialInputDialog extends StatefulWidget {
  const _CredentialInputDialog({required this.label});
  final String label;

  @override
  State<_CredentialInputDialog> createState() => _CredentialInputDialogState();
}

class _CredentialInputDialogState extends State<_CredentialInputDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${context.tr('Simpan')} ${widget.label}'),
        content: TextField(
          controller: _controller,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 8192,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: context.tr('Disimpan hanya di perangkat; tidak ada permintaan ke provider.'),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Batal'))),
          FilledButton(
            onPressed: () {
              final value = _controller.text;
              if (value.trim().isEmpty || value.length > 8192) return;
              Navigator.of(context).pop(value);
            },
            child: Text(context.tr('Simpan dengan aman')),
          ),
        ],
      );
}
