import 'package:flutter/material.dart';

import '../core/github_releases.dart';

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
        title: const Text('GitHub release metadata'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'Choose an allowlisted reference repository. This reads release metadata only; it does not download or run files.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<GitHubRepository>(
                value: _repository,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reference repository'),
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
              Text(_repository.description, style: TextStyle(color: Colors.white.withValues(alpha: .65))),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _fetch,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(_loading ? 'Checking GitHub…' : 'Check latest release'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
              ],
              if (_release != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text(_release!.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('Tag ${_release!.tag} · ${_release!.publishedAt?.toLocal() ?? 'publication date unavailable'}'),
                const SizedBox(height: 10),
                Text('Assets (${_release!.assets.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (_release!.assets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('No release assets were listed.'),
                  ),
                for (final asset in _release!.assets) ...[
                  const SizedBox(height: 6),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_formatSize(asset.sizeBytes)} · ${asset.contentType ?? 'content type unknown'}'),
                        Text(asset.sha256 == null ? 'Publisher SHA-256: unavailable' : 'Publisher SHA-256: ${asset.sha256}'),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'A published digest is not a signature and has not been verified against a downloaded file. No asset is installed or executed.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 12, height: 1.4),
                ),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
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
