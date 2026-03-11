/// Utilities for cleaning HTML content from RSS feeds.

/// Decodes common HTML entities to their plain-text equivalents.
String decodeHtmlEntities(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&ndash;', '–')
      .replaceAll('&mdash;', '—')
      .replaceAll('&lsquo;', '\u2018')
      .replaceAll('&rsquo;', '\u2019')
      .replaceAll('&ldquo;', '\u201C')
      .replaceAll('&rdquo;', '\u201D')
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      )
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      );
}

/// Strips HTML tags and decodes entities, returning plain text suitable for
/// card previews and other contexts that don't support HTML rendering.
String stripHtml(String html) {
  final stripped = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
  final collapsed = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
  return decodeHtmlEntities(collapsed);
}
