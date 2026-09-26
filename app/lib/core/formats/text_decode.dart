// Bytes → text for formats that don't insist on UTF-8. Old text files and
// Word-era exports are often Windows-1252 (curly quotes at 0x91–0x94); FB2
// books from the Russian ecosystem are often Windows-1251.

import 'dart:convert';

/// Decodes by byte-order mark, else UTF-8 if the bytes are valid UTF-8, else
/// Windows-1252.
String decodeText(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return _utf16(bytes, 2, littleEndian: true);
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return _utf16(bytes, 2, littleEndian: false);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return decodeSingleByte(bytes, 'windows-1252');
  }
}

/// Decodes with a named encoding (from an XML declaration or RTF header);
/// unknown names fall back to [decodeText].
String decodeWithCharset(List<int> bytes, String? charset) {
  final name = charset?.toLowerCase().replaceAll('_', '-');
  return switch (name) {
    'utf-8' || 'utf8' => utf8.decode(bytes, allowMalformed: true),
    'utf-16' || 'utf-16le' || 'utf-16be' => decodeText(bytes),
    'windows-1251' || 'cp1251' || 'win-1251' => decodeSingleByte(bytes, 'windows-1251'),
    'windows-1252' || 'cp1252' || 'iso-8859-1' || 'latin1' || 'us-ascii' || 'ascii' => decodeSingleByte(bytes, 'windows-1252'),
    _ => decodeText(bytes),
  };
}

/// Windows-1252 or Windows-1251; bytes below 0x80 are ASCII in both.
String decodeSingleByte(List<int> bytes, String codepage) {
  final high = codepage == 'windows-1251' ? _cp1251 : _cp1252;
  final out = StringBuffer();
  for (final b in bytes) {
    out.writeCharCode(b < 0x80 ? b : high.codeUnitAt(b - 0x80));
  }
  return out.toString();
}

String _utf16(List<int> bytes, int start, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

// 0x80–0xFF. Undefined slots map to their Latin-1 code point, as browsers do.
const _cp1252 = '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008DŽ\u008F'
    '\u0090‘’“”•–—˜™š›œ\u009DžŸ'
    ' ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ';

const _cp1251 = 'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\u0098™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕї'
    'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя';
