import '../models/article.dart';

/// Classifies an article into a canonical topic bucket using a two-layer
/// strategy: RSS categories first (normalized), keyword taxonomy as fallback.
class TopicClassifier {
  static const String aiMl = 'AI & Machine Learning';
  static const String security = 'Security';
  static const String mobile = 'Mobile';
  static const String hardware = 'Hardware';
  static const String softwareDev = 'Software & Dev';
  static const String policyLaw = 'Policy & Law';
  static const String scienceSpace = 'Science & Space';
  static const String business = 'Business';
  static const String other = 'Other';

  static const List<String> orderedBuckets = [
    aiMl,
    security,
    mobile,
    hardware,
    softwareDev,
    policyLaw,
    scienceSpace,
    business,
    other,
  ];

  // Lowercase RSS category label → canonical bucket
  static const Map<String, String> _categoryNormalization = {
    'ai': aiMl,
    'artificial intelligence': aiMl,
    'machine learning': aiMl,
    'ml': aiMl,
    'deep learning': aiMl,
    'generative ai': aiMl,
    'llm': aiMl,
    'security': security,
    'cybersecurity': security,
    'infosec': security,
    'privacy': security,
    'hacking': security,
    'mobile': mobile,
    'android': mobile,
    'ios': mobile,
    'smartphones': mobile,
    'iphone': mobile,
    'hardware': hardware,
    'chips': hardware,
    'semiconductors': hardware,
    'processors': hardware,
    'software': softwareDev,
    'open source': softwareDev,
    'programming': softwareDev,
    'developer': softwareDev,
    'development': softwareDev,
    'cloud': softwareDev,
    'policy': policyLaw,
    'law': policyLaw,
    'regulation': policyLaw,
    'legal': policyLaw,
    'government': policyLaw,
    'science': scienceSpace,
    'space': scienceSpace,
    'research': scienceSpace,
    'physics': scienceSpace,
    'biology': scienceSpace,
    'business': business,
    'startups': business,
    'finance': business,
    'economy': business,
  };

  // Bucket → keywords matched against lowercased title + description.
  // Checked in order; the bucket with the most keyword hits wins.
  static const Map<String, List<String>> _keywordTaxonomy = {
    aiMl: [
      'artificial intelligence', 'machine learning', 'deep learning',
      'language model', 'generative ai', 'neural network',
      ' llm', 'openai', 'chatgpt', 'gemini', 'anthropic', 'claude',
      'copilot', 'midjourney', 'stable diffusion', 'dall-e', 'mistral',
      'transformer', 'inference', 'fine-tun',
    ],
    security: [
      'ransomware', 'malware', 'phishing', 'zero-day', 'zero day',
      'vulnerability', 'exploit', 'cybersecurity', 'data breach',
      'data leak', 'backdoor', 'spyware', 'botnet', 'ddos',
      'cve-', 'hacked', 'stolen data', 'encryption key',
    ],
    mobile: [
      'android ', 'iphone', 'samsung galaxy', 'google pixel',
      'app store', 'google play', ' ios ', 'ipad', 'wearable',
      'smartwatch', 'foldable phone', 'oneplus', 'smartphone',
    ],
    hardware: [
      'nvidia', ' amd ', ' intel ', 'qualcomm', 'apple silicon',
      ' cpu', ' gpu', 'processor', 'semiconductor', 'transistor',
      ' tsmc', 'datacenter', 'data center', 'risc-v', 'arm chip',
      ' ssd', 'memory chip', 'wafer',
    ],
    softwareDev: [
      'open source', 'github', 'linux kernel', 'docker', 'kubernetes',
      ' sdk', 'developer tool', 'programming language', 'framework',
      'aws ', 'azure ', 'google cloud', 'devops', 'api ', 'microservice',
      'pull request', 'git ',
    ],
    policyLaw: [
      'regulation', 'lawsuit', ' ftc', 'gdpr', 'antitrust', 'congress',
      'legislation', 'senate ', 'parliament', 'court ruling', 'fined ',
      ' banned', 'illegal', 'compliance', ' doj', 'european union',
      'court order', 'attorney general',
    ],
    scienceSpace: [
      'nasa', 'spacex', 'rocket launch', 'satellite', 'orbit',
      ' mars', 'lunar', 'telescope', 'quantum computing',
      'climate change', 'renewable energy', 'scientific study',
      'researchers found', 'new discovery',
    ],
    business: [
      'acquisition', 'funding round', ' ipo', 'earnings report',
      'quarterly revenue', 'layoffs', 'valuation', 'merger',
      'venture capital', 'series a', 'series b', 'billion dollar',
      'ceo ', 'executive', 'stock price',
    ],
  };

  /// Returns the canonical topic bucket for [article].
  static String classify(Article article) {
    // Layer 1: RSS categories (normalized)
    for (final raw in article.categories) {
      final bucket = _categoryNormalization[raw.toLowerCase().trim()];
      if (bucket != null) return bucket;
    }

    // Layer 2: keyword taxonomy on title + description
    final text =
        '${article.title} ${article.description ?? ''}'.toLowerCase();

    String? bestBucket;
    int bestCount = 0;

    for (final entry in _keywordTaxonomy.entries) {
      int count = 0;
      for (final kw in entry.value) {
        if (text.contains(kw)) count++;
      }
      if (count > bestCount) {
        bestCount = count;
        bestBucket = entry.key;
      }
    }

    return bestBucket ?? other;
  }
}
