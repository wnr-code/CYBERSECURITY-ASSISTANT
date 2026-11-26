import 'package:material_ui/material_ui.dart';

import '../core/github_releases.dart';
import '../l10n/app_localizations.dart';

String _releaseError(String error, BuildContext context) {
  const messages = {
    'This repository is not in the app reference allowlist.': 'Repositori ini tidak termasuk dalam daftar referensi yang diizinkan aplikasi.',
    'GitHub release lookup timed out.': 'Pencarian rilis GitHub melewati batas waktu.',
    'Could not reach the GitHub API. Check network access.': 'API GitHub tidak dapat dijangkau. Periksa koneksi jaringan.',
    'GitHub TLS certificate validation failed.': 'Validasi sertifikat TLS GitHub gagal.',
    'GitHub returned an HTTP protocol error.': 'GitHub mengembalikan kesalahan protokol HTTP.',
    'GitHub returned invalid release metadata.': 'GitHub mengembalikan metadata rilis yang tidak valid.',
  };
  final noRelease = RegExp(r'^No published latest release was found for (.+)\.$').firstMatch(error);
  if (noRelease != null) {
    return AppLocalizations.of(context).locale.languageCode == 'id'
        ? 'Rilis terbaru tidak ditemukan untuk ${noRelease.group(1)}.'
        : error;
  }
  final status = RegExp(r'^GitHub API returned HTTP (\d+)\. Try again later\.$').firstMatch(error);
  if (status != null) {
    return AppLocalizations.of(context).locale.languageCode == 'id'
        ? 'GitHub API mengembalikan HTTP ${status.group(1)}. Coba lagi nanti.'
        : error;
  }
  return context.tr(messages[error] ?? error);
}

class ReleaseCatalogDialog extends StatefulWidget {
  const ReleaseCatalogDialog({super.key});

  @override
  State<ReleaseCatalogDialog> createState() => _ReleaseCatalogDialogState();
}

class _ReleaseCatalogDialogState extends State<ReleaseCatalogDialog> {
  final _client = GitHubReleaseClient();
  GitHubRepository _repository = githubReferenceRepositories.first;
  GitHubRelease? _release;
  String? _error;
  bool _loading = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('Metadata rilis GitHub')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(
                context.tr('Pilih repositori referensi yang diizinkan. Halaman ini hanya membaca metadata rilis; file tidak diunduh atau dijalankan.'),
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<GitHubRepository>(
                initialValue: _repository,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('Repositori referensi')),
                items: [
                  for (final repository in githubReferenceRepositories)
                    DropdownMenuItem(
                      value: repository,
                      child: Text(repository.fullName, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _loading
                    ? null
                    : (repository) {
                        if (repository == null) return;
                        setState(() {
                          _repository = repository;
                          _release = null;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 8),
              Text(context.tr(_repository.description), style: TextStyle(color: Colors.white.withValues(alpha: .65))),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _fetch,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(_loading ? context.tr('Memeriksa GitHub…') : context.tr('Periksa rilis terbaru')),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_releaseError(_error!, context), style: const TextStyle(color: Colors.orangeAccent)),
              ],
              if (_release != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text(_release!.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('${context.tr('Tag')} ${_release!.tag} · ${_release!.publishedAt?.toLocal() ?? context.tr('tanggal publikasi tidak tersedia')}'),
                const SizedBox(height: 10),
                Text('${context.tr('Berkas rilis')} (${_release!.assets.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (_release!.assets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(context.tr('Tidak ada berkas rilis yang tercantum.')),
                  ),
                for (final asset in _release!.assets) ...[
                  const SizedBox(height: 6),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_formatSize(asset.sizeBytes)} · ${asset.contentType ?? context.tr('jenis konten tidak diketahui')}'),
                        Text(asset.sha256 == null
                            ? '${context.tr('SHA-256 dari penerbit')}: ${context.tr('tidak tersedia')}'
                            : '${context.tr('SHA-256 dari penerbit')}: ${asset.sha256}'),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  context.tr('Digest yang dipublikasikan bukan tanda tangan dan belum diverifikasi terhadap file unduhan. Tidak ada berkas yang dipasang atau dijalankan.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 12, height: 1.4),
                ),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Tutup')))],
      );

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
      _release = null;
    });
    try {
      final release = await _client.fetchLatest(_repository);
      if (mounted) setState(() => _release = release);
    } on GitHubReleaseException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
