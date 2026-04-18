import 'package:flutter_test/flutter_test.dart';
import 'package:news_reader/utils/html_utils.dart';

void main() {
  group('decodeHtmlEntities', () {
    test('returns plain text unchanged', () {
      expect(decodeHtmlEntities('Hello world'), 'Hello world');
    });

    test('returns empty string unchanged', () {
      expect(decodeHtmlEntities(''), '');
    });

    test('decodes &amp;', () {
      expect(decodeHtmlEntities('Rock &amp; Roll'), 'Rock & Roll');
    });

    test('decodes &lt; and &gt;', () {
      expect(decodeHtmlEntities('&lt;div&gt;'), '<div>');
    });

    test('decodes &quot;', () {
      expect(decodeHtmlEntities('She said &quot;hello&quot;'), 'She said "hello"');
    });

    test('decodes &apos;', () {
      expect(decodeHtmlEntities("it&apos;s fine"), "it's fine");
    });

    test('decodes &nbsp;', () {
      expect(decodeHtmlEntities('a&nbsp;b'), 'a b');
    });

    test('decodes &ndash; and &mdash;', () {
      expect(decodeHtmlEntities('2020&ndash;2024'), '2020–2024');
      expect(decodeHtmlEntities('wait&mdash;what'), 'wait—what');
    });

    test('decodes curly quotes', () {
      expect(decodeHtmlEntities('&lsquo;hello&rsquo;'), '\u2018hello\u2019');
      expect(decodeHtmlEntities('&ldquo;world&rdquo;'), '\u201Cworld\u201D');
    });

    test('decodes decimal numeric entity', () {
      expect(decodeHtmlEntities('&#65;'), 'A');
      expect(decodeHtmlEntities('&#9829;'), '♥');
    });

    test('decodes hex numeric entity', () {
      expect(decodeHtmlEntities('&#x41;'), 'A');
      expect(decodeHtmlEntities('&#x2665;'), '♥');
    });

    test('decodes multiple entities in one string', () {
      expect(
        decodeHtmlEntities('&lt;b&gt;Rock &amp; Roll&lt;/b&gt;'),
        '<b>Rock & Roll</b>',
      );
    });
  });

  group('stripHtml', () {
    test('returns empty string unchanged', () {
      expect(stripHtml(''), '');
    });

    test('strips a simple tag', () {
      expect(stripHtml('<p>Hello</p>'), 'Hello');
    });

    test('strips multiple tags', () {
      expect(stripHtml('<h1>Title</h1><p>Body text</p>'), 'Title Body text');
    });

    test('collapses extra whitespace', () {
      expect(stripHtml('<p>  Too   many   spaces  </p>'), 'Too many spaces');
    });

    test('strips tag and decodes entities', () {
      expect(stripHtml('<p>Rock &amp; Roll</p>'), 'Rock & Roll');
    });

    test('strips self-closing tags', () {
      expect(stripHtml('Line one<br/>Line two'), 'Line one Line two');
    });

    test('handles tag with attributes', () {
      expect(stripHtml('<a href="http://example.com">Link</a>'), 'Link');
    });

    test('returns plain text without tags unchanged', () {
      expect(stripHtml('Just plain text'), 'Just plain text');
    });
  });
}
