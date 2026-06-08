import 'package:flutter_test/flutter_test.dart';
import 'package:news_reader/services/topic_classifier.dart';

void main() {
  group('TopicClassifier.bucketForCategory', () {
    test('returns correct bucket for known category (case-insensitive)', () {
      expect(TopicClassifier.bucketForCategory('ai'), TopicClassifier.aiMl);
      expect(TopicClassifier.bucketForCategory('AI'), TopicClassifier.aiMl);
      expect(TopicClassifier.bucketForCategory('Security'),
          TopicClassifier.security);
      expect(TopicClassifier.bucketForCategory('mobile'), TopicClassifier.mobile);
      expect(
          TopicClassifier.bucketForCategory('hardware'), TopicClassifier.hardware);
      expect(TopicClassifier.bucketForCategory('software'),
          TopicClassifier.softwareDev);
      expect(
          TopicClassifier.bucketForCategory('policy'), TopicClassifier.policyLaw);
      expect(TopicClassifier.bucketForCategory('science'),
          TopicClassifier.scienceSpace);
      expect(TopicClassifier.bucketForCategory('business'),
          TopicClassifier.business);
    });

    test('returns null for unknown category', () {
      expect(TopicClassifier.bucketForCategory('cooking'), isNull);
      expect(TopicClassifier.bucketForCategory(''), isNull);
      expect(TopicClassifier.bucketForCategory('unknown category'), isNull);
    });

    test('strips leading/trailing whitespace before lookup', () {
      expect(
          TopicClassifier.bucketForCategory('  ai  '), TopicClassifier.aiMl);
    });
  });
}
