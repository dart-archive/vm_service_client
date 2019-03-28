// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
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

    var isolateRef = (await client.getVM()).isolates.first;
    expect(isolateRef.name, contains('main'));

    var isolate = await isolateRef.loadRunnable();
    expect(start.difference(isolate.startTime).inMinutes, equals(0));
    expect(isolate.livePorts, equals(1));
    expect(isolate.pauseEvent, new TypeMatcher<VMPauseStartEvent>());
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
      other.onGC.listen(neverCalled);

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
      other.onUpdate.listen(neverCalled);

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
      """).catchError((_) {
        // This will throw an error when the client closes, since the evaluate
        // request never got a response.
      });

      var queue = new StreamQueue(main.onPauseOrResume);
      expect(
          queue.next, completion(new TypeMatcher<VMPauseInterruptedEvent>()));
      expect(queue.next, completion(new TypeMatcher<VMResumeEvent>()));

      // We should be properly filtering events to the right isolate.
      var subscription = other.onPauseOrResume.listen(neverCalled);

      await main.pause();
      await main.waitUntilPaused();
      await main.resume();

      await pumpEventQueue();

      // Cancel this so that it doesn't fire due to --pause-isolates-on-exit.
      subscription.cancel();
    });

    test("onBreakpointAdded fires when a breakpoint is added", () async {
      client = await runAndConnect(main: """
        print('here'); // line 8
      """, flags: ["--pause-isolates-on-start", "--pause-isolates-on-exit"]);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      await isolate.waitUntilPaused();

      expect(isolate.onBreakpointAdded.first,
          completion(new TypeMatcher<VMBreakpoint>()));

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
      other.stdout.listen(neverCalled);
      other.stderr.listen(neverCalled);

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

        // Note: this produces a bogus dead code warning (sdk#30243).
        // ignore: dead_code
        expect(other.onExit, completes);
      }, skip: "broken by sdk#28505");
    });

    test("onExtensionAdded fires when an extension is added", () async {
      client = await runAndConnect(main: """
        registerExtension('ext.test', (_, __) {});
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      await isolate.waitUntilPaused();
      await isolate.resume();

      expect(await isolate.onExtensionAdded.first, equals('ext.test'));
    });

    group("onExtensionEvent", () {
      test("emits extension events", () async {
        client = await runAndConnect(main: """
          postEvent('foo', {'bar': 'baz'});
        """, flags: ["--pause-isolates-on-start"]);

        var isolate = await (await client.getVM()).isolates.first.load();
        await isolate.waitUntilPaused();
        var eventFuture = onlyEvent(isolate.onExtensionEvent);
        await isolate.resume();

        var event = await eventFuture;
        expect(event.kind, 'foo');
        expect(event.data, {'bar': 'baz'});
      });
    });

    group("selectExtensionEvents", () {
      test("chooses by extension kind", () async {
        client = await runAndConnect(main: """
          postEvent('foo', {'prefixed': false});
          postEvent('bar.baz', {'prefixed': true});
          postEvent('not.captured', {});
        """, flags: ["--pause-isolates-on-start"]);

        var isolate = await (await client.getVM()).isolates.first.load();

        var unprefixedEvent = onlyEvent(isolate.selectExtensionEvents('foo'));
        var prefixedEvent =
            onlyEvent(isolate.selectExtensionEvents('bar.', prefix: true));

        await isolate.waitUntilPaused();
        await isolate.resume();

        expect((await unprefixedEvent).kind, 'foo');
        expect((await prefixedEvent).kind, 'bar.baz');
      });
    });
  });

  group("waitForExtension", () {
    test("notifies when the extension is already registered", () async {
      client = await runAndConnect(main: """
        registerExtension('ext.test', (_, __) {});
        postEvent('registered', {});
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.load();
      await isolate.waitUntilPaused();
      var whenRegistered = isolate.selectExtensionEvents('registered').first;
      await isolate.resume();
      await whenRegistered;
      expect(isolate.waitForExtension('ext.test'), completes);
    });

    test("notifies when the extension is registered later", () async {
      client = await runAndConnect(main: """
        registerExtension('ext.one', (_, __) async {
          registerExtension('ext.two', (_, __) async {
            return new ServiceExtensionResponse.result('''{
              "ext.two": "is ok"
            }''');
          });

          return new ServiceExtensionResponse.result('null');
        });
      """);

      var isolate = await (await client.getVM()).isolates.first.load();
      isolate.waitForExtension('ext.two').then(expectAsync1((_) {
        expect(isolate.invokeExtension('ext.two'),
            completion(equals({'ext.two': 'is ok'})));
      }));

      await isolate.waitForExtension('ext.one');
      expect(isolate.invokeExtension('ext.one'), completion(isNull));
    });
  });

  group("load", () {
    test("loads extensionRpcs", () async {
      client = await runAndConnect(main: """
        registerExtension('ext.foo', (_, __) {});
        registerExtension('ext.bar', (_, __) {});
      """);

      var isolate = await (await client.getVM()).isolates.first.load();
      expect(isolate.extensionRpcs, unorderedEquals(['ext.foo', 'ext.bar']));
    });
  });

  group("loadRunnable", () {
    test("for an unrunnable isolate", () async {
      client = await runAndConnect(flags: ["--pause-isolates-on-start"]);

      var isolateRef = (await client.getVM()).isolates.first;
      expect(isolateRef, isNot(new TypeMatcher<VMRunnableIsolate>()));

      var isolate = await isolateRef.loadRunnable();
      expect(isolate.rootLibrary, isNotNull);
    });

    test("for a runnable isolate", () async {
      client = await runAndConnect(flags: ["--pause-isolates-on-start"]);

      var isolateRef = (await client.getVM()).isolates.first;
      var isolate = await isolateRef.loadRunnable();
      isolate = await isolate.loadRunnable();
      expect(isolate.rootLibrary, isNotNull);
    });

    test("for an unrunnable reference to a runnable isolate", () async {
      client = await runAndConnect(flags: ["--pause-isolates-on-start"]);

      var isolateRef = (await client.getVM()).isolates.first;
      await isolateRef.loadRunnable();
      var isolate = await isolateRef.loadRunnable();
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

    var onPaused =
        isolate.onPauseOrResume.firstWhere((event) => event is! VMResumeEvent);
    expect(isolate.pause(), completes);
    await onPaused;

    expect((await isolate.load()).pauseEvent,
        new TypeMatcher<VMPauseInterruptedEvent>());
  });

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
      stdout = new StreamQueue(isolate.stdout.transform(lines));
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
      expect(await sourceLine(frame.location), equals(2));
    });

    test("steps over the next function with VMStep.over", () async {
      expect(stdout.next, completion(equals("in inner")));
      stdout.next.then(neverCalled).catchError((_) {});

      await isolate.resume(step: VMStep.over);
      await isolate.waitUntilPaused();

      var frame = (await isolate.getStack()).frames.first;
      expect(await sourceLine(frame.location), equals(9));
    });

    test("steps out of the current function with VMStep.out", () async {
      expect(stdout.next, completion(equals("in inner")));
      expect(stdout.next, completion(equals("after inner")));
      stdout.next.then(neverCalled).catchError((_) {});

      await isolate.resume(step: VMStep.out);
      await isolate.waitUntilPaused();

      var frame = (await isolate.getStack()).frames.first;
      expect(await sourceLine(frame.location), equals(17));
    });
  });

  group("resume(overAsyncSuspension)", () {
    VMIsolateRef isolate;
    setUp(() async {
      client = await runAndConnect(topLevel: r"""
        inner() {
          print("in inner");
          return new Future.delayed(const Duration(milliseconds: 1));
        }

        outer() async {
          debugger();
          await inner(); // line 9
          print("after inner"); // line 10
        }
      """, main: r"""
        await outer();
        print("after outer");
      """);

      isolate = (await client.getVM()).isolates.first;
      await isolate.waitUntilPaused();
    });

    test("steps over the async suspension with VMStep.overAsyncSuspension",
        () async {
      // Step from the `debugger` statement to the await line.
      await isolate.resume(step: VMStep.over);
      await isolate.waitUntilPaused();

      var frame = (await isolate.getStack()).frames.first;
      expect(await sourceLine(frame.location), equals(9));

      expect((await isolate.load()).pauseEvent.atAsyncSuspension, equals(true));

      await isolate.resume(step: VMStep.overAsyncSuspension);
      await isolate.waitUntilPaused();

      frame = (await isolate.getStack()).frames.first;
      expect(await sourceLine(frame.location), equals(10));

      expect((await isolate.load()).pauseEvent.atAsyncSuspension,
          isNot(equals(true)));
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
      expect(await sourceLine(stack.frames.first.location), equals(8));
    });

    test("adds a breakpoint at the given column", () async {
      var client = await runAndConnect(main: r"""
        print("one"); /* line 8, column 21+ */ print("two");
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      var breakpoint =
          await isolate.addBreakpoint(isolate.rootLibrary.uri, 8, column: 22);
      expect(breakpoint.number, equals(1));

      await isolate.resume();
      await isolate.waitUntilPaused();

      var stack = await isolate.getStack();
      var location = stack.frames.first.location;
      var script = await location.script.load();
      var sourceLocation = script.sourceLocation(location.token);
      expect(sourceLocation.line, equals(7));
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

  group("invokeExtension", () {
    test("enforces ext. prefix", () async {
      var client = await runAndConnect();
      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      expect(() => isolate.invokeExtension('noprefix'), throwsArgumentError);
    });

    test("invokes extension", () async {
      var client = await runAndConnect(main: r"""
        registerExtension('ext.ping', (_, __) async {
          return new ServiceExtensionResponse.result('{"type": "pong"}');
        });
      """);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      expect(
          await isolate.invokeExtension('ext.ping'), equals({'type': 'pong'}));
    });

    test("supports non-map return values", () async {
      var client = await runAndConnect(main: r"""
        registerExtension('ext.ping', (_, __) async {
          return new ServiceExtensionResponse.result('"pong"');
        });
      """);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      expect(await isolate.invokeExtension('ext.ping'), equals("pong"));
    });

    test("passes parameters", () async {
      var client = await runAndConnect(main: r"""
        registerExtension('ext.params', (_, params) async {
          return new ServiceExtensionResponse.result('''{
            "foo": "${params['foo']}"
          }''');
        });
      """);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      var response =
          await isolate.invokeExtension('ext.params', {'foo': 'bar'});
      expect(response, equals({'foo': 'bar'}));
    });

    test("returns errors", () async {
      var client = await runAndConnect(main: r"""
        registerExtension('ext.error', (_, __) async {
          return new ServiceExtensionResponse.error(-32013, 'some error');
        });
      """);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();

      expect(isolate.invokeExtension('ext.error'), throwsA(predicate((error) {
        expect(error, new TypeMatcher<rpc.RpcException>());
        expect(error.code, equals(-32013));
        expect(error.data, equals({'details': 'some error'}));
        return true;
      })));
    });
  });
}

/// Starts a client with two unpaused empty isolates.
Future<List<VMIsolateRef>> _twoIsolates() async {
  client = await runAndConnect(topLevel: r"""
    void otherIsolate(_) {}
  """, main: r"""
    Isolate.spawn(otherIsolate, null);
  """, flags: ["--pause-isolates-on-start", "--pause-isolates-on-exit"]);

  var vm = await client.getVM();
  var main = await vm.isolates.first;

  var otherFuture = client.onIsolateRunnable.first;
  await main.resume();
  var other = await otherFuture;
  await other.resume();

  return [main, other];
}
