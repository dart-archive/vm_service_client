// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';

final lines = new StreamTransformer(
    (Stream<List<int>> stream, bool cancelOnError) => const LineSplitter()
        .bind(utf8.decoder.bind(stream))
        .listen(null, cancelOnError: cancelOnError));

Future<VMServiceClient> runAndConnect(
    {String topLevel,
    String main,
    List<String> flags,
    bool sync: false}) async {
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

  // Similarly, put the preamble on one line so we can modify it without
  // breaking tests.
  var preamble = """
    /* Wait for a line so the test doesn't print something that could be emitted
     * before "Observatory listening on". */
    stdin.readLineSync();

    /* Don't let the isolate close on its own. */
    new ReceivePort();
  """
      .replaceAll("\n", " ");

  var library = """
$imports;

$topLevel

main() ${sync ? '' : 'async'} {
  $preamble

  $main
}
""";

  var uri = "data:application/dart;charset=utf-8,${Uri.encodeFull(library)}";

  var args = flags.toList()
    ..addAll(['--pause-isolates-on-exit', '--enable-vm-service=0', uri]);
  var process = await Process.start(Platform.resolvedExecutable, args);

  var stdout = new StreamQueue(process.stdout.transform<String>(lines));
  var line = await stdout.next;

  // Start executing main().
  process.stdin.writeln();

  var match = new RegExp('Observatory listening on (.*)').firstMatch(line);
  var client = new VMServiceClient.connect(match[1]);
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

/// Returns the first event on [stream] and asserts that it emits no more events
/// until it closes.
Future onlyEvent(Stream stream) {
  var completer = new Completer.sync();
  stream.listen(expectAsync1(completer.complete, count: 1),
      onError: registerException, onDone: () {
    if (completer.isCompleted) return;
    throw "Expected an event.";
  });

  // Wait a bit to see if any further events are emitted.
  expect(new Future.delayed(new Duration(milliseconds: 200)), completes);
  return completer.future;
}
