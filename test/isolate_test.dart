// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

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
    test("onGC fires when a garbage collection happens", () async {
      var isolates = await _twoIsolates();
      var main = await isolates.first.loadRunnable();
      var other = isolates.last;

      // We should be properly filtering events to the right isolate.
      other.onGC.listen(expectAsync((_) {}, count: 0));

      // Allocate a bunch of data, which should eventually trigger a GC.
      var onGC = new ResultFuture(main.onGC.first);
      while (onGC.result == null) {
        await main.rootLibrary.evaluate("new List(10000)");
      }

      await onGC;
    });

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

    test("onPauseOrResume fires when the isolate pauses or resumes", () async {
      var isolates = await _twoIsolates();
      var main = await isolates.first.loadRunnable();
      var other = isolates.last;

      // Give the isolate something to run. This works around sdk#24349, which
      // causes pause to fail if no code is running.
      main.rootLibrary.evaluate("""
        (() {
          while (true) {}
        })()
      """);

      var queue = new StreamQueue(main.onPauseOrResume);
      expect(queue.next,
          completion(new isInstanceOf<VMPauseInterruptedEvent>()));
      expect(queue.next, completion(new isInstanceOf<VMResumeEvent>()));

      // We should be properly filtering events to the right isolate.
      other.onPauseOrResume.listen(expectAsync((_) {}, count: 0));

      await main.pause();
      await main.waitUntilPaused();
      await main.resume();
    });

    test("onBreakpointAdded fires when a breakpoint is added", () async {
      client = await runAndConnect(main: """
        print('here'); // line 8
      """, flags: ["--pause-isolates-on-start", "--pause-isolates-on-exit"]);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      await isolate.waitUntilPaused();

      expect(isolate.onBreakpointAdded.first,
          completion(new isInstanceOf<VMBreakpoint>()));

      var library = await isolate.rootLibrary.load();
      var breakpoint = await library.scripts.single.addBreakpoint(8);
      await isolate.resume();
      await isolate.waitUntilPaused();
      await breakpoint.remove();
    });

    test("stdout and stderr", () async {
      var isolates = await _twoIsolates();
      var main = await isolates.first.loadRunnable();
      var other = isolates.last;

      // We should be properly filtering events to the right isolate.
      other.stdout.listen(expectAsync((_) {}, count: 0));
      other.stderr.listen(expectAsync((_) {}, count: 0));

      var stdout = new StreamQueue(main.stdout.transform(lines));
      expect(stdout.next, completion(equals("out")));
      expect(stdout.next, completion(equals("print")));
      expect(main.stderr.transform(lines).first, completion(equals("err")));

      // TODO(nweiz): Test stdout when sdk#24351 is fixed.
      await main.rootLibrary.evaluate("stdout.writeln('out')");
      await main.rootLibrary.evaluate("print('print')");
      await main.rootLibrary.evaluate("stderr.writeln('err')");
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
    test("for an unpaused isolate", () async {
      client = await runAndConnect(topLevel: r"""
        var stop = false;
      """, main: r"""
        print('looping');
        while (!stop) {}
        debugger();
      """, flags: ['--pause-isolates-on-start']);

      var isolate = (await client.getVM()).isolates.first;
      isolate.resume();
      expect(await isolate.stdout.transform(lines).first, equals("looping"));

      var waitUntilPaused = isolate.waitUntilPaused();
      await (await isolate.loadRunnable()).rootLibrary.evaluate("stop = true");
      await waitUntilPaused;
    });

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
  }, skip: "Broken by dart-lang/sdk#25379");

  group("resume()", () {
    var isolate;
    var stdout;
    setUp(() async {
      client = await runAndConnect(topLevel: r"""
        inner() { // line 3
          print("in inner");
        }

        outer() {
          debugger();
          inner();
          print("after inner"); // line 10
        }
      """, main: r"""
        outer();
        print("after outer"); // line 18
      """);

      isolate = (await client.getVM()).isolates.first;
      await isolate.waitUntilPaused();
      stdout = new StreamQueue(lines.bind(isolate.stdout));
    });

    test("resumes normal execution by default", () async {
      expect(stdout.next, completion(equals("in inner")));
      expect(stdout.next, completion(equals("after inner")));
      expect(stdout.next, completion(equals("after outer")));

      isolate.resume();
    });

    test("steps into the next function with VMStep.into", () async {
      await isolate.resume(step: VMStep.into);
      await isolate.waitUntilPaused();

      var frame = (await isolate.getStack()).frames.first;
      expect(await sourceLine(frame.location), equals(3));
    });

    test("steps over the next function with VMStep.over", () async {
      expect(stdout.next, completion(equals("in inner")));
      stdout.next.then(expectAsync((_) {}, count: 0)).catchError((_) {});

      await isolate.resume(step: VMStep.over);
      await isolate.waitUntilPaused();

      var frame = (await isolate.getStack()).frames.first;
      expect(await sourceLine(frame.location), equals(10));
    });

    test("steps out of the current function with VMStep.out", () async {
      expect(stdout.next, completion(equals("in inner")));
      expect(stdout.next, completion(equals("after inner")));
      stdout.next.then(expectAsync((_) {}, count: 0)).catchError((_) {});

      await isolate.resume(step: VMStep.out);
      await isolate.waitUntilPaused();

      var frame = (await isolate.getStack()).frames.first;
      expect(await sourceLine(frame.location), equals(18));
    });
  });

  test("setName() sets the isolate's name", () async {
    client = await runAndConnect(flags: ['--pause-isolates-on-start']);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.setName('fblthp');
    expect((await isolate.load()).name, equals('fblthp'));
  });

  group("addBreakpoint", () {
    test("adds a breakpoint at the given line", () async {
      var client = await runAndConnect(main: r"""
        print("one");
        print("two"); // line 9
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      var breakpoint = await isolate.addBreakpoint(isolate.rootLibrary.uri, 9);
      expect(breakpoint.number, equals(1));

      await isolate.resume();
      await isolate.waitUntilPaused();

      var stack = await isolate.getStack();
      expect(await sourceLine(stack.frames.first.location), equals(9));
    });

    test("adds a breakpoint at the given column", () async {
      var client = await runAndConnect(main: r"""
        print("one"); /* line 8, column 21+ */ print("two");
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      var breakpoint = await isolate.addBreakpoint(
          isolate.rootLibrary.uri, 8, column: 22);
      expect(breakpoint.number, equals(1));

      await isolate.resume();
      await isolate.waitUntilPaused();

      var stack = await isolate.getStack();
      var location = stack.frames.first.location;
      var script = await location.script.load();
      var sourceLocation = script.sourceLocation(location.token);
      expect(sourceLocation.line, equals(8));
      expect(sourceLocation.column, greaterThan(21));
    });

    test("works before the isolate is runnable", () async {
      client = await runAndConnect(flags: ['--pause-isolates-on-start']);

      // We should be able to set a breakpoint before the relevant library is
      // loaded, although it may fail to resolve if the line number is bogus.
      var isolate = (await client.getVM()).isolates.first;
      var breakpoint = await isolate.addBreakpoint('my/script.dart', 0);
      expect(breakpoint.number, equals(1));
    });
  });
}

/// Starts a client with two unpaused empty isolates.
Future<List<VMRunnableIsolate>> _twoIsolates() async {
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
