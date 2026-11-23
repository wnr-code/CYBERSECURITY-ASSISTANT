enum ProviderCategory { backend, database, storage, ai, securityIntelligence, custom }

enum ProviderAuthType { none, apiKey, scopedToken, providerConfig, custom }

class ProviderDefinition {
  const ProviderDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.authType,
    required this.setupGuidance,
  });

  final String id;
  final String name;
  final ProviderCategory category;
  final String description;
  final ProviderAuthType authType;
  final String setupGuidance;

  /// The provider is catalogued for planning but has no authenticated adapter yet.
  bool get integrationImplemented => false;
}

const providerRegistry = <ProviderDefinition>[
  ProviderDefinition(
    id: 'cloudflare_workers',
    name: 'Cloudflare Workers',
    category: ProviderCategory.backend,
    description: 'User-owned edge API or backend.',
    authType: ProviderAuthType.scopedToken,
    setupGuidance: 'Deploy your own Worker and configure its HTTPS endpoint. A scoped token connector is not implemented yet.',
  ),
  ProviderDefinition(
    id: 'firebase_auth',
    name: 'Firebase Authentication',
    category: ProviderCategory.backend,
    description: 'Optional user-owned authentication service.',
    authType: ProviderAuthType.providerConfig,
    setupGuidance: 'Configure a Firebase project and restrict its Android application. The Firebase SDK adapter is not implemented yet.',
  ),
  ProviderDefinition(
    id: 'firebase_functions',
    name: 'Firebase Cloud Functions',
    category: ProviderCategory.backend,
    description: 'Optional user-owned serverless functions.',
    authType: ProviderAuthType.providerConfig,
    setupGuidance: 'Deploy functions in your Firebase project. This app does not invoke functions yet.',
  ),
  ProviderDefinition(
    id: 'supabase',
    name: 'Supabase',
    category: ProviderCategory.database,
    description: 'User-owned Postgres, authentication, and REST services.',
    authType: ProviderAuthType.providerConfig,
    setupGuidance: 'Configure your own project URL and a least-privilege client credential. Authenticated Supabase access is not implemented.',
  ),
  ProviderDefinition(
    id: 'cloudflare_d1',
    name: 'Cloudflare D1',
    category: ProviderCategory.database,
    description: 'User-owned database accessed through a backend Worker.',
    authType: ProviderAuthType.scopedToken,
    setupGuidance: 'Expose the database through your own Worker API; the mobile app should not contain administrator credentials.',
  ),
  ProviderDefinition(
    id: 'firebase_firestore',
    name: 'Cloud Firestore',
    category: ProviderCategory.database,
    description: 'User-owned Firebase document database.',
    authType: ProviderAuthType.providerConfig,
    setupGuidance: 'Apply restrictive Firestore rules and configure Firebase Authentication before connecting an app.',
  ),
  ProviderDefinition(
    id: 'cloudflare_r2',
    name: 'Cloudflare R2',
    category: ProviderCategory.storage,
    description: 'User-owned S3-compatible object storage.',
    authType: ProviderAuthType.scopedToken,
    setupGuidance: 'Use a dedicated bucket and narrowly scoped access. No R2 upload or credential adapter is implemented.',
  ),
  ProviderDefinition(
    id: 'firebase_storage',
    name: 'Firebase Storage',
    category: ProviderCategory.storage,
    description: 'User-owned Firebase object storage.',
    authType: ProviderAuthType.providerConfig,
    setupGuidance: 'Use restrictive Storage rules and authenticated identities. Uploads are not implemented.',
  ),
  ProviderDefinition(
    id: 's3_compatible',
    name: 'S3-compatible storage',
    category: ProviderCategory.storage,
    description: 'User-selected S3-compatible object store.',
    authType: ProviderAuthType.scopedToken,
    setupGuidance: 'Use a dedicated bucket and scoped credentials. This app does not accept or store access keys.',
  ),
  ProviderDefinition(
    id: 'webdav',
    name: 'WebDAV',
    category: ProviderCategory.storage,
    description: 'User-selected WebDAV endpoint.',
    authType: ProviderAuthType.custom,
    setupGuidance: 'Use an HTTPS endpoint and a dedicated account. Authenticated WebDAV operations are not implemented.',
  ),
  ProviderDefinition(
    id: 'openai',
    name: 'OpenAI',
    category: ProviderCategory.ai,
    description: 'Optional cloud AI provider using a user-owned key.',
    authType: ProviderAuthType.apiKey,
    setupGuidance: 'A user-owned API key can be stored locally, but no provider call is implemented. Review provider data handling before future cloud analysis.',
  ),
  ProviderDefinition(
    id: 'gemini',
    name: 'Gemini',
    category: ProviderCategory.ai,
    description: 'Optional cloud AI provider using a user-owned key.',
    authType: ProviderAuthType.apiKey,
    setupGuidance: 'A user-owned API key can be stored locally, but no provider call is implemented. Review provider data handling before future cloud analysis.',
  ),
  ProviderDefinition(
    id: 'anthropic',
    name: 'Anthropic',
    category: ProviderCategory.ai,
    description: 'Optional cloud AI provider using a user-owned key.',
    authType: ProviderAuthType.apiKey,
    setupGuidance: 'A user-owned API key can be stored locally, but no provider call is implemented. Review provider data handling before future cloud analysis.',
  ),
  ProviderDefinition(
    id: 'openrouter',
    name: 'OpenRouter',
    category: ProviderCategory.ai,
    description: 'Optional model routing provider using a user-owned key.',
    authType: ProviderAuthType.apiKey,
    setupGuidance: 'A user-owned API key can be stored locally, but no provider call is implemented. Review provider/model data handling and cost controls before future use.',
  ),
  ProviderDefinition(
    id: 'virustotal',
    name: 'VirusTotal',
    category: ProviderCategory.securityIntelligence,
    description: 'Optional security-intelligence API.',
    authType: ProviderAuthType.apiKey,
    setupGuidance: 'A user-owned API key can be stored locally, but no API integration is implemented. Review provider terms and data-sharing implications before submitting any indicator.',
  ),
  ProviderDefinition(
    id: 'shodan',
    name: 'Shodan',
    category: ProviderCategory.securityIntelligence,
    description: 'Optional internet-exposure intelligence API.',
    authType: ProviderAuthType.apiKey,
    setupGuidance: 'A user-owned API key can be stored locally, but no API integration is implemented. Review applicable terms before use.',
  ),
  ProviderDefinition(
    id: 'urlscan',
    name: 'URLScan',
    category: ProviderCategory.securityIntelligence,
    description: 'Optional URL scanning intelligence API.',
    authType: ProviderAuthType.apiKey,
    setupGuidance: 'A user-owned API key can be stored locally, but no API integration is implemented. Submissions may be visible to third parties depending on scan settings; review privacy before use.',
  ),
  ProviderDefinition(
    id: 'custom_rest',
    name: 'Custom REST API',
    category: ProviderCategory.custom,
    description: 'User-owned HTTPS endpoint.',
    authType: ProviderAuthType.custom,
    setupGuidance: 'Only the generic unauthenticated HTTPS reachability check exists. Authenticated API requests are not implemented.',
  ),
];

String providerCategoryLabel(ProviderCategory category) => switch (category) {
      ProviderCategory.backend => 'Backend',
      ProviderCategory.database => 'Database',
      ProviderCategory.storage => 'Cloud Storage',
      ProviderCategory.ai => 'AI Provider',
      ProviderCategory.securityIntelligence => 'Security Intelligence',
      ProviderCategory.custom => 'Custom Service',
    };

String providerAuthLabel(ProviderAuthType authType) => switch (authType) {
      ProviderAuthType.none => 'No authentication',
      ProviderAuthType.apiKey => 'User-owned API key required',
      ProviderAuthType.scopedToken => 'Scoped user token required',
      ProviderAuthType.providerConfig => 'Provider-specific app configuration required',
      ProviderAuthType.custom => 'User-defined authentication',
    };
