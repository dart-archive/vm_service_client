// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.utils;

import 'dart:async';

/// A [Map] between whitespace characters and their escape sequences.
const _escapeMap = const {
  '\n': r'\n',
  '\r': r'\r',
  '\f': r'\f',
  '\b': r'\b',
  '\t': r'\t',
  '\v': r'\v',
  '\x7F': r'\x7F', // delete
};

/// Transforms [stream] with a [StreamTransformer] that transforms data events
/// using [handleData].
Stream transform(Stream stream, handleData(data, EventSink sink)) =>
    stream.transform(
        new StreamTransformer.fromHandlers(handleData: handleData));

/// A [RegExp] that matches whitespace characters that should be escaped.
final _escapeRegExp = new RegExp(
    "[\\x00-\\x07\\x0E-\\x1F${_escapeMap.keys.map(_getHexLiteral).join()}]");

/// Returns [str] with all whitespace characters represented as their escape
/// sequences.
///
/// Backslash characters are escaped as `\\`
String escapeString(String str) {
  str = str.replaceAll('\\', r'\\');
  return str.replaceAllMapped(_escapeRegExp, (match) {
    var mapped = _escapeMap[match[0]];
    if (mapped != null) return mapped;
    return _getHexLiteral(match[0]);
  });
}

/// Given single-character string, return the hex-escaped equivalent.
String _getHexLiteral(String input) {
  int rune = input.runes.single;
  return r'\x' + rune.toRadixString(16).toUpperCase().padLeft(2, '0');
}
