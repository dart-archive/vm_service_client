// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:vm_service_client/vm_service_client.dart';

final lines = UTF8.decoder.fuse(const LineSplitter());

Future<VMServiceClient> runAndConnect({String topLevel, String main,
    List<String> flags, bool sync: false}) async {
  if (topLevel == null) topLevel = "";
  if (main == null) main = "";
  if (flags == null) flags = [];

  // Put all imports on the first line so adding more doesn't break tests that
  // depend on specific line numbers.
  var imports = [
    'dart:async',
    'dart:developer',
    'dart:io',
    'dart:isolate',
    'dart:typed_data',
    'dart:mirrors'
  ].map((uri) => 'import "$uri"').join('; ');

  var library = """
$imports;

$topLevel

main() ${sync ? '' : 'async'} {
  // Don't let the isolate close on its own.
  new ReceivePort();
  $main
}
""";

  var uri = "data:application/dart;charset=utf-8,${Uri.encodeFull(library)}";

  var args = flags.toList()..addAll(['--observe=0', uri]);
  var process = await Process.start(Platform.resolvedExecutable, args);

  var stdout = new StreamQueue(process.stdout.transform(lines));
  var line = await stdout.next;
  var match = new RegExp('Observatory listening on (.*)').firstMatch(line);
  var client = await VMServiceClient.connect(match[1]);
  client.done.then((_) => process.kill());

  // Drain the rest of the stdout queue. Otherwise the stdout and stderr streams
  // won't work.
  stdout.rest.listen(null);

  return client;
}

Future<int> sourceLine(VMBreakpointLocation location) async {
  var script = await location.script.load();
  return script.sourceLocation(location.token).line;
}
