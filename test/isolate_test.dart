// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';

import 'utils.dart';

VMServiceClient client;

void main() {
  tearDown(() {
    if (client != null) client.close();
  });

  test("includes the isolate's metadata", () async {
    var start = new DateTime.now();
    client = await runAndConnect(flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;
    expect(isolate.name, endsWith(r'$main'));

    isolate = await isolate.load();
    expect(start.difference(isolate.startTime).inMinutes, equals(0));
    expect(isolate.livePorts, equals(1));
  });

  test("setName() sets the isolate's name", () async {
    client = await runAndConnect(flags: ['--pause-isolates-on-start']);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.setName('fblthp');
    expect((await isolate.load()).name, equals('fblthp'));
  });
}
