// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';

import 'utils.dart';

VMServiceClient client;

void main() {
  tearDown(() {
    if (client != null) client.close();
  });

  test("does not pause on exceptions by default", () async {
    client = await runAndConnect(main: r"""
      throw 'err';

      print('Done!');
    """, flags: ["--pause-isolates-on-start"]);
    final isolate = (await client.getVM()).isolates.first;

    // Pauses-on-start.
    await isolate.waitUntilPaused();

    await isolate.resume();
    await isolate.waitUntilPaused();
    expect((await isolate.load()).pauseEvent, isA<VMPauseExitEvent>());
  });

  test("unhandled pauses only on unhandled exceptions", () async {
    client = await runAndConnect(main: r"""
      try {
        throw 'err2'; // line 8
      } catch (e) {
      }

      throw 'err'; // line 12

      print('Done!');
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    // Pauses-on-start.
    await isolate.waitUntilPaused();
    await isolate.setExceptionPauseMode(VMExceptionPauseMode.unhandled);

    // Except pause on the second throw.
    await isolate.resume();
    await isolate.waitUntilPaused();
    final frame = (await isolate.getStack()).frames.first;
    expect(await sourceLine(frame.location), equals(12));

    // Resume and expect termination.
    await isolate.resume();
    await isolate.waitUntilPaused();
    expect((await isolate.load()).pauseEvent, isA<VMPauseExitEvent>());
  });

  test("all pauses only on all exceptions", () async {
    client = await runAndConnect(main: r"""
      try {
        throw 'err2'; // line 8
      } catch (e) {
      }

      throw 'err'; // line 12

      print('Done!');
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    // Pauses-on-start.
    await isolate.waitUntilPaused();
    await isolate.setExceptionPauseMode(VMExceptionPauseMode.all);

    // Except pause on the first throw.
    await isolate.resume();
    await isolate.waitUntilPaused();
    var frame = (await isolate.getStack()).frames.first;
    expect(await sourceLine(frame.location), equals(8));

    // Except pause on the second throw.
    await isolate.resume();
    await isolate.waitUntilPaused();
    frame = (await isolate.getStack()).frames.first;
    expect(await sourceLine(frame.location), equals(12));

    // Resume and expect termination.
    await isolate.resume();
    await isolate.waitUntilPaused();
    expect((await isolate.load()).pauseEvent, isA<VMPauseExitEvent>());
  });

  test("exception mode can be read and set", () async {
    client = await runAndConnect(flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    // Pauses-on-start.
    await isolate.waitUntilPaused();

    expect((await isolate.load()).exceptionPauseMode.toString(),
        equals(VMExceptionPauseMode.none.toString()));

    await isolate.setExceptionPauseMode(VMExceptionPauseMode.unhandled);
    expect((await isolate.load()).exceptionPauseMode.toString(),
        equals(VMExceptionPauseMode.unhandled.toString()));

    await isolate.setExceptionPauseMode(VMExceptionPauseMode.all);
    expect((await isolate.load()).exceptionPauseMode.toString(),
        equals(VMExceptionPauseMode.all.toString()));

    await isolate.setExceptionPauseMode(VMExceptionPauseMode.none);
    expect((await isolate.load()).exceptionPauseMode.toString(),
        equals(VMExceptionPauseMode.none.toString()));
  });
}
