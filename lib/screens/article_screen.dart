import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/article.dart';
import '../providers/bookmarks_provider.dart';
import '../utils/html_utils.dart';

/// Reader mode article view — clean, distraction-free layout
class ArticleScreen extends ConsumerStatefulWidget {
  final Article article;

  const ArticleScreen({super.key, required this.article});

  @override
  ConsumerState<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends ConsumerState<ArticleScreen> {
  Article get article => widget.article;

  final _shareButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bookmarksNotifier = ref.read(bookmarksProvider.notifier);
    final isBookmarked = ref.watch(bookmarksProvider
        .select((list) => list.any((a) => a.id == article.id)));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: _shareButtonKey,
            icon: const Icon(Icons.share),
            tooltip: 'Share article',
            onPressed: () => _shareArticle(context),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in browser',
            onPressed: () => _openInBrowser(context),
          ),
          IconButton(
            icon: Icon(
              isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            ),
            tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark',
            onPressed: () => bookmarksNotifier.toggle(article),
          ),
        ],
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Source + date
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    article.sourceName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (article.sourceCount > 1) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${article.sourceCount} sources',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                Text(
                  _formatDate(article.publishedAt),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              decodeHtmlEntities(article.title),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            // Author
            if (article.author != null) ...[
              const SizedBox(height: 8),
              Text(
                'By ${article.author}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Image
            if (article.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  article.imageUrl!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            const Divider(),
            const SizedBox(height: 12),

            // Content — prefer full content, fall back to description
            // Render as HTML if content contains tags, otherwise plain text
            _buildContent(theme),

            const SizedBox(height: 24),

            // Categories
            if (article.categories.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: article.categories
                    .where((c) => c.isNotEmpty)
                    .map((cat) => Chip(
                          label: Text(cat),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Source link
            if (article.sourceNames.length > 1) ...[
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Also reported by:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                article.sourceNames
                    .where((s) => s != article.sourceName)
                    .join(', '),
                style: theme.textTheme.bodyMedium,
              ),
            ],

            const Divider(),
            const SizedBox(height: 16),

            // Read full article button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openInBrowser(context),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Read Full Article'),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final raw = article.content ?? article.description ?? '';
    if (raw.isEmpty) {
      return Text(
        'No content available.',
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
      );
    }

    // Check if content contains HTML tags
    final hasHtml = RegExp(r'<[a-zA-Z][^>]*>').hasMatch(raw);
    if (!hasHtml) {
      return Text(
        raw,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
      );
    }

    return Html(
      data: raw,
      style: {
        'body': Style(
          fontSize: FontSize(theme.textTheme.bodyLarge?.fontSize ?? 16),
          lineHeight: const LineHeight(1.6),
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'a': Style(
          color: theme.colorScheme.primary,
        ),
        'img': Style(
          margin: Margins.symmetric(vertical: 8),
        ),
      },
      onLinkTap: (url, _, __) {
        if (url != null) {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  Future<void> _shareArticle(BuildContext context) async {
    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromLTWH(0, 0, 100, 50);
    final text = '${article.title}\n${article.url}';
    await Share.share(text, sharePositionOrigin: origin);
  }

  Future<void> _openInBrowser(BuildContext context) async {
    final url = article.url;
    final uri = Uri.parse(url);

    // Try url_launcher first (works on native Windows, Android, iOS, macOS)
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    // Fallback for WSL: use cmd.exe to open in Windows browser
    if (Platform.isLinux) {
      try {
        // Check if running under WSL
        final result = await Process.run('wslview', [url]);
        if (result.exitCode == 0) return;
      } catch (_) {
        // wslview not available, try xdg-open directly
        try {
          final result = await Process.run('xdg-open', [url]);
          if (result.exitCode == 0) return;
        } catch (_) {}
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  String _formatDate(DateTime dateTime) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }
}
