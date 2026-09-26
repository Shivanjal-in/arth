// Rich Text Format (.rtf) → blocks. RTF is a stream of `{groups}`, `\control`
// words and text. This reads the subset that carries a book's text: `\par`
// paragraphs, `\b`/`\i` emphasis, headings (by `\outlinelevel` or a
// stylesheet name like "heading 1"), `\'hh` bytes in the document's code
// page and `\uN` Unicode. Font tables, pictures, headers, footers, footnotes
// and field instructions are skipped.

import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:arth/core/formats/text_decode.dart';

/// Destinations whose content isn't running text.
const _skipDestinations = {
  'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object', 'header', 'headerl', 'headerr', 'headerf', //
  'footer', 'footerl', 'footerr', 'footerf', 'footnote', 'fldinst', 'themedata', 'colorschememapping',
  'latentstyles', 'datastore', 'listtable', 'listoverridetable', 'rsidtbl', 'generator', 'xmlnstbl',
  'pntext', 'listtext', 'pntxta', 'pntxtb', 'shp', 'shpinst', 'nonshppict', 'bkmkstart', 'bkmkend',
  'revtbl', 'mmathPr', 'filetbl', 'userprops', 'docvar', 'template', 'ftnsep', 'ftnsepc', 'aftnsep',
};

const _symbols = {
  'emdash': '—', 'endash': '–', 'lquote': '‘', 'rquote': '’', 'ldblquote': '“', 'rdblquote': '”', //
  'bullet': '•', 'emspace': ' ', 'enspace': ' ', 'qmspace': ' ', 'tab': ' ', 'cell': ' ',
};

final _headingName = RegExp(r'^heading (\d)', caseSensitive: false);

({String? title, List<EpubBlock> blocks}) parseRtf(List<int> bytes) {
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != r'{\rtf') throw EpubFormatException('not RTF');
  return _RtfParser(bytes).parse();
}

class _State {
  _State();

  _State.copy(_State s)
      : bold = s.bold,
        italic = s.italic,
        skip = s.skip,
        uc = s.uc,
        style = s.style,
        outline = s.outline,
        list = s.list,
        destination = s.destination;

  bool bold = false;
  bool italic = false;
  bool skip = false;

  /// How many fallback characters follow a `\uN`.
  int uc = 1;
  int? style;
  int? outline;
  bool list = false;

  /// The non-text destination this group is in (`title`, `stylesheet`…).
  String? destination;
}

class _RtfParser {
  _RtfParser(this.bytes);

  final List<int> bytes;
  final out = BlockBuilder();
  var _i = 0;
  var _state = _State();
  final _stack = <_State>[];
  var _codepage = 'windows-1252';

  /// Fallback characters still to drop after a `\uN`.
  var _skipChars = 0;

  // Stylesheet: `{\s1 ... heading 1;}` maps style 1 to a name.
  final _styleNames = <int, String>{};
  int? _definingStyle;
  final _styleName = StringBuffer();
  final _title = StringBuffer();

  /// Pending `\'hh` bytes: a multi-byte run is decoded together.
  final _bytes = <int>[];

  ({String? title, List<EpubBlock> blocks}) parse() {
    while (_i < bytes.length) {
      final c = bytes[_i];
      if (c == 0x7B) {
        // {
        _flushBytes();
        _stack.add(_state);
        // Groups nested in the stylesheet or info inherit its destination.
        _state = _State.copy(_state);
        _i++;
        if (_peekIs(r'\*')) {
          // An ignorable destination: skip it unless we know it.
          _i += 2;
          final word = _peekWord();
          if (word != 'fldrslt') _state.skip = true;
        }
      } else if (c == 0x7D) {
        // }
        _flushBytes();
        _closeGroup();
        _i++;
      } else if (c == 0x5C) {
        // backslash
        _control();
      } else if (c == 0x0D || c == 0x0A) {
        _i++; // line breaks in the file aren't text
      } else {
        _flushBytes();
        _i++;
        _char(String.fromCharCode(c));
      }
    }
    _flushBytes();
    out.flush();
    final title = _title.toString().trim();
    return (title: title.isEmpty ? null : title, blocks: out.blocks);
  }

  bool _peekIs(String s) {
    for (var k = 0; k < s.length; k++) {
      if (_i + k >= bytes.length || bytes[_i + k] != s.codeUnitAt(k)) return false;
    }
    return true;
  }

  String? _peekWord() {
    if (_i >= bytes.length || bytes[_i] != 0x5C) return null;
    var j = _i + 1;
    final b = StringBuffer();
    while (j < bytes.length && _isAlpha(bytes[j])) {
      b.writeCharCode(bytes[j++]);
    }
    return b.toString();
  }

  static bool _isAlpha(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  void _closeGroup() {
    final closing = _state;
    final entryEnds = closing.destination == 'stylesheet-entry' && (_stack.isEmpty || _stack.last.destination != 'stylesheet-entry');
    if (entryEnds && _definingStyle != null) {
      _styleNames[_definingStyle!] = _styleName.toString().replaceAll(';', '').trim();
      _definingStyle = null;
      _styleName.clear();
    }
    if (_stack.isNotEmpty) _state = _stack.removeLast();
    _applyParagraph();
  }

  void _control() {
    _i++; // backslash
    if (_i >= bytes.length) return;
    final c = bytes[_i];
    if (!_isAlpha(c)) {
      // A control symbol.
      _i++;
      switch (c) {
        case 0x27: // \'hh
          final hex = String.fromCharCodes(bytes.sublist(_i, (_i + 2).clamp(0, bytes.length)));
          _i += 2;
          final v = int.tryParse(hex, radix: 16);
          if (v == null) return;
          if (_skipChars > 0) {
            _skipChars--;
          } else {
            _bytes.add(v);
          }
        case 0x7E: // \~ non-breaking space
          _char(' ');
        case 0x5F: // \_ non-breaking hyphen
          _char('-');
        case 0x2D: // \- optional hyphen
          break;
        case 0x5C || 0x7B || 0x7D: // escaped \ { }
          _char(String.fromCharCode(c));
        case 0x0A || 0x0D: // backslash-newline is \par
          _par();
      }
      return;
    }
    _flushBytes();
    final word = StringBuffer();
    while (_i < bytes.length && _isAlpha(bytes[_i])) {
      word.writeCharCode(bytes[_i++]);
    }
    var negative = false;
    if (_i < bytes.length && bytes[_i] == 0x2D) {
      negative = true;
      _i++;
    }
    final digits = StringBuffer();
    while (_i < bytes.length && _isDigit(bytes[_i])) {
      digits.writeCharCode(bytes[_i++]);
    }
    if (_i < bytes.length && bytes[_i] == 0x20) _i++; // the delimiting space
    final n = digits.isEmpty ? null : int.parse(digits.toString()) * (negative ? -1 : 1);
    _word(word.toString(), n);
  }

  void _word(String w, int? n) {
    if (_skipDestinations.contains(w)) {
      if (w == 'stylesheet') {
        _state.destination = 'stylesheet';
        return;
      }
      if (w == 'info') {
        _state.destination = 'info';
        return;
      }
      _state.skip = true;
      return;
    }
    switch (w) {
      case 'title' when _state.destination == 'info':
        _state.destination = 'title';
      case 's' when _state.destination == 'stylesheet':
        _state.destination = 'stylesheet-entry';
        _definingStyle = n;
      case 'ansicpg':
        _codepage = n == 1251 ? 'windows-1251' : 'windows-1252';
      case 'uc':
        _state.uc = n ?? 1;
      case 'u':
        if (n != null) _char(String.fromCharCode(n < 0 ? n + 65536 : n));
        _skipChars = _state.uc;
      case 'b':
        _state.bold = n != 0;
      case 'i':
        _state.italic = n != 0;
      case 'plain':
        _state
          ..bold = false
          ..italic = false;
      case 'pard':
        _state
          ..style = null
          ..outline = null
          ..list = false;
        _applyParagraph();
      case 's':
        _state.style = n;
        _applyParagraph();
      case 'outlinelevel':
        _state.outline = n;
        _applyParagraph();
      case 'ls' || 'pnlvlblt' || 'pnlvlbody':
        _state.list = true;
        _applyParagraph();
      case 'par' || 'sect' || 'page' || 'row':
        _par();
      case 'line':
        _char('\n', pre: true);
      case 'bin':
        _i += n ?? 0; // binary data
      default:
        final symbol = _symbols[w];
        if (symbol != null) _char(symbol);
    }
  }

  /// Sets the block kind from the current paragraph properties; the next
  /// `\par` ends a block of that kind.
  void _applyParagraph() {
    final heading = _state.outline ?? _headingLevel(_state.style);
    if (heading != null && heading >= 0 && heading < 9) {
      out
        ..kind = BlockKind.heading
        ..level = (heading + 1).clamp(1, 6);
    } else {
      out
        ..kind = _state.list ? BlockKind.listItem : BlockKind.paragraph
        ..level = 0;
    }
  }

  /// A stylesheet "heading N" as a 0-based outline level.
  int? _headingLevel(int? style) {
    final name = style == null ? null : _styleNames[style];
    final m = name == null ? null : _headingName.firstMatch(name);
    return m == null ? null : int.parse(m.group(1)!) - 1;
  }

  void _par() {
    if (_state.skip || _state.destination != null) return;
    out.flush();
  }

  void _flushBytes() {
    if (_bytes.isEmpty) return;
    final text = decodeSingleByte(_bytes, _codepage);
    _bytes.clear();
    _char(text);
  }

  void _char(String s, {bool pre = false}) {
    if (_skipChars > 0 && s.length == 1 && s != '\n') {
      // A `\uN`'s ASCII fallback.
      _skipChars--;
      return;
    }
    if (_state.skip) return;
    switch (_state.destination) {
      case 'stylesheet-entry':
        _styleName.write(s);
        return;
      case 'title':
        _title.write(s);
        return;
      case 'stylesheet' || 'info':
        return;
    }
    out.write(s, bold: _state.bold || out.kind == BlockKind.heading, italic: _state.italic, pre: pre);
  }
}
