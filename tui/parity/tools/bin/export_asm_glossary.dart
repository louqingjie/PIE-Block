import 'dart:convert';
import 'dart:io';
import '../../../../lib/src/asm_glossary.dart';

void _dump(String kind, Map<String, AsmHoverData> map, List<Map<String, Object?>> out) {
  map.forEach((key, data) {
    out.add({
      'kind': kind,
      'key': key,
      'title': data.title,
      'description': data.description,
      'detail': data.detail,
    });
  });
}

void main() {
  final entries = <Map<String, Object?>>[];
  _dump('mnemonic', asmMnemonics, entries);
  _dump('register', asmRegisters, entries);
  _dump('segment', asmSegments, entries);
  _dump('directive', asmDirectives, entries);
  _dump('notation', asmNotations, entries);
  _dump('sfr', asmSpecialFunctionRegisters, entries);
  _dump('bit', asmSpecialFunctionBits, entries);
  final out = File('../golden/asm_glossary.json');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(entries));
  stdout.writeln('entries: ${entries.length}');
}
