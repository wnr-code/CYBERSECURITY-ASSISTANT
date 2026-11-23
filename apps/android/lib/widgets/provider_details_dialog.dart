import 'package:flutter/material.dart';

import '../core/provider_registry.dart';
import '../core/secure_credential_store.dart';

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

  String get _credentialLabel => switch (_credentialKind) {
        SecureCredentialKind.apiKey => 'API key',
        SecureCredentialKind.accessToken => 'access token',
        null => 'credential',
      };

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.provider.name),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(providerCategoryLabel(widget.provider.category), style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              Text(widget.provider.description),
              const SizedBox(height: 12),
              Text('Status: ${widget.provider.integrationImplemented ? 'Available' : 'Guide only · not connected'}'),
              Text('Authentication: ${providerAuthLabel(widget.provider.authType)}'),
              const SizedBox(height: 12),
              Text(widget.provider.setupGuidance, style: const TextStyle(height: 1.45)),
              const SizedBox(height: 12),
              if (_credentialKind != null) ...[
                const Divider(),
                Text('Credential storage: ${_credentialPresent == null ? 'not checked' : _credentialPresent! ? 'present' : 'not set'}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _storeCredential,
                    icon: const Icon(Icons.key_outlined),
                    label: Text('Store $_credentialLabel'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _checkCredential,
                    child: const Text('Check stored status'),
                  ),
                  if (_credentialPresent == true)
                    TextButton.icon(
                      onPressed: _busy ? null : _deleteCredential,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                ]),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!, style: TextStyle(color: Colors.white.withValues(alpha: .7))),
                ],
              ],
              const SizedBox(height: 12),
              const Text(
                'Stored credentials are not sent to this provider: authenticated requests and provider-specific connection tests are not implemented.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 8),
              const Text(
                'Storage uses the platform secure-storage plugin. This build has not been verified on Android; avoid entering production secrets until native hardening and device tests are complete.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );

  Future<void> _storeCredential() async {
    final kind = _credentialKind;
    if (kind == null) return;
    final secret = await showDialog<String>(
      context: context,
      builder: (_) => _CredentialInputDialog(label: _credentialLabel),
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
        title: const Text('Delete stored credential?'),
        content: const Text('This removes the credential for this provider from secure storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
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
        title: Text('Store ${widget.label}'),
        content: TextField(
          controller: _controller,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 8192,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: 'Saved locally only; no provider request will be sent.',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = _controller.text;
              if (value.trim().isEmpty || value.length > 8192) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Save securely'),
          ),
        ],
      );
}
