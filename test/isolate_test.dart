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

    isolate = await isolate.loadRunnable();
    expect(start.difference(isolate.startTime).inMinutes, equals(0));
    expect(isolate.livePorts, equals(1));
    expect(isolate.pauseEvent, new isInstanceOf<VMPauseStartEvent>());
    expect(isolate.error, isNull);
    expect(isolate.breakpoints, isEmpty);
    expect(isolate.rootLibrary.uri.scheme, equals('data'));
    expect(isolate.libraries, isNotEmpty);
  });

  group("events:", () {
    test("onUpdate fires when the Isolate's name changes", () async {
      var isolates = await _twoIsolates();
      var main = await isolates.first.loadRunnable();
      var other = isolates.last;

      expect(main.onUpdate.first.then((updated) => updated.name),
          completion(equals('fblthp')));

      // We should be properly filtering events to the right isolate.
      other.onUpdate.listen(expectAsync((_) {}, count: 0));

      await main.setName('fblthp');
    });

    group("onExit", () {
      test("onExit for a live isolate", () async {
        var isolates = await _twoIsolates();
        var main = await isolates.first.loadRunnable();
        var other = await isolates.last.loadRunnable();

        var mainExited = false;
        main.onExit.then((_) => mainExited = true);

        var onExitFuture = other.onExit;
        await other.waitUntilPaused();
        await other.resume();
        await onExitFuture;
        expect(mainExited, isFalse);
      });

      test("onExit for a dead isolate", () async {
        var isolates = await _twoIsolates();
        var main = await isolates.first.loadRunnable();
        var other = await isolates.last.loadRunnable();

        await other.waitUntilPaused();
        await other.resume();

        // Wait until we know other is dead without calling onExit.
        while (true) {
          try {
            await other.load();
          } on VMSentinelException catch (_) {
            break;
          }
        }

        expect(other.onExit, completes);
      });
    });
  });

  group("loadRunnable", () {
    test("for an unrunnable isolate", () async {
      client = await runAndConnect(flags: ["--pause-isolates-on-start"]);

      var isolate = (await client.getVM()).isolates.first;
      expect(isolate, isNot(new isInstanceOf<VMRunnableIsolate>()));

      isolate = await isolate.loadRunnable();
      expect(isolate.rootLibrary, isNotNull);
    });

    test("for a runnable isolate", () async {
      client = await runAndConnect(flags: ["--pause-isolates-on-start"]);

      var isolate = (await client.getVM()).isolates.first;
      isolate = await isolate.loadRunnable();
      isolate = await isolate.loadRunnable();
      expect(isolate.rootLibrary, isNotNull);
    });

    test("for an unrunnable reference to a runnable isolate", () async {
      client = await runAndConnect(flags: ["--pause-isolates-on-start"]);

      var isolate = (await client.getVM()).isolates.first;
      await isolate.loadRunnable();
      isolate = await isolate.loadRunnable();
      expect(isolate.rootLibrary, isNotNull);
    });
  });

  group("waitUntilPaused", () {
    test("for a paused isolate", () async {
      client = await runAndConnect(main: r"""
        print('pausing');
        debugger();
      """, flags: ['--pause-isolates-on-start']);

      var isolate = (await client.getVM()).isolates.first;
      isolate.resume();
      expect(await isolate.stdout.transform(lines).first, equals("pausing"));

      // Give a little bit of a grace period to be sure the isolate is paused.
      await new Future.delayed(new Duration(milliseconds: 50));

      await isolate.waitUntilPaused();
    });
  });

  test("pause() pauses the isolate", () async {
    client = await runAndConnect(topLevel: r"""
      var stop = false;
    """, main: r"""
      print('looping');
      while (!stop) {}
    """, flags: ['--pause-isolates-on-start']);

    var isolate = (await client.getVM()).isolates.first;
    isolate.resume();
    expect(await isolate.stdout.transform(lines).first, equals("looping"));

    await isolate.pause();
    expect((await isolate.load()).pauseEvent,
        new isInstanceOf<VMPauseInterruptedEvent>());
  });

  test("setName() sets the isolate's name", () async {
    client = await runAndConnect(flags: ['--pause-isolates-on-start']);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.setName('fblthp');
    expect((await isolate.load()).name, equals('fblthp'));
  });

  group("addBreakpoint", () {
    test("works before the isolate is runnable", () async {
      client = await runAndConnect(flags: ['--pause-isolates-on-start']);

      // We should be able to set a breakpoint before the relevant library is
      // loaded, although it may fail to resolve if (as in this case) the line
      // number is bogus.
      var isolate = (await client.getVM()).isolates.first;
      var breakpoint = await isolate.addBreakpoint('dart:async', 0);
      expect(breakpoint.number, equals(1));
    });
  });
}

/// Starts a client with two unpaused empty isolates.
Future<List<Isolate>> _twoIsolates() async {
  client = await runAndConnect(topLevel: r"""
    void otherIsolate(_) {}
  """, main: r"""
    Isolate.spawn(otherIsolate, null);
  """, flags: ["--pause-isolates-on-start", "--pause-isolates-on-exit"]);

  var vm = await client.getVM();
  var main = vm.isolates.first;

  var otherFuture = client.onIsolateRunnable.first;
  await main.resume();
  var other = await otherFuture;
  await other.resume();

  return [main, other];
}
