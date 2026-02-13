import 'package:hive/hive.dart';

part 'article.g.dart';

/// Represents a news article from any source
@HiveType(typeId: 0)
class Article extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? description;

  @HiveField(3)
  final String? content;

  @HiveField(4)
  final String url;

  @HiveField(5)
  final String? imageUrl;

  @HiveField(6)
  final DateTime publishedAt;

  @HiveField(7)
  final String sourceName;

  @HiveField(8)
  final String? author;

  @HiveField(9)
  final List<String> categories;

  /// Number of sources that reported this article
  @HiveField(10)
  final int sourceCount;

  /// List of all source names that reported this article
  @HiveField(11)
  final List<String> sourceNames;

  Article({
    required this.id,
    required this.title,
    this.description,
    this.content,
    required this.url,
    this.imageUrl,
    required this.publishedAt,
    required this.sourceName,
    this.author,
    this.categories = const [],
    this.sourceCount = 1,
    List<String>? sourceNames,
  }) : sourceNames = sourceNames ?? [sourceName];

  /// Create Article from JSON
  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      content: json['content'] as String?,
      url: json['url'] as String,
      imageUrl: json['imageUrl'] as String?,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      sourceName: json['sourceName'] as String,
      author: json['author'] as String?,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      sourceCount: json['sourceCount'] as int? ?? 1,
      sourceNames: (json['sourceNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
    );
  }

  /// Convert Article to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'content': content,
      'url': url,
      'imageUrl': imageUrl,
      'publishedAt': publishedAt.toIso8601String(),
      'sourceName': sourceName,
      'author': author,
      'categories': categories,
      'sourceCount': sourceCount,
      'sourceNames': sourceNames,
    };
  }

  /// Create a copy with modified fields
  Article copyWith({
    String? id,
    String? title,
    String? description,
    String? content,
    String? url,
    String? imageUrl,
    DateTime? publishedAt,
    String? sourceName,
    String? author,
    List<String>? categories,
    int? sourceCount,
    List<String>? sourceNames,
  }) {
    return Article(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      content: content ?? this.content,
      url: url ?? this.url,
      imageUrl: imageUrl ?? this.imageUrl,
      publishedAt: publishedAt ?? this.publishedAt,
      sourceName: sourceName ?? this.sourceName,
      author: author ?? this.author,
      categories: categories ?? this.categories,
      sourceCount: sourceCount ?? this.sourceCount,
      sourceNames: sourceNames ?? this.sourceNames,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Article && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Article(id: $id, title: $title, sourceName: $sourceName)';
  }
}
