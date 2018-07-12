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

  test("includes the breakpoint's metadata", () async {
    client = await runAndConnect(main: r"""
      print("one");
      print("two"); // line 9
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    var stdout = new StreamQueue(isolate.stdout.transform(lines));
    var line1 = new ResultFuture(stdout.next);
    var line2 = new ResultFuture(stdout.next.catchError((_) {}));

    await isolate.waitUntilPaused();
    var library = await (await isolate.loadRunnable()).rootLibrary.load();
    var breakpoint = await library.scripts.single.addBreakpoint(9);
    expect(breakpoint.number, equals(1));
    expect(breakpoint, isNot(new TypeMatcher<VMResolvedBreakpoint>()));
    expect(breakpoint.location, new TypeMatcher<VMUnresolvedSourceLocation>());
    expect(breakpoint.location.uri.scheme, equals('data'));
    expect(breakpoint.toString(), startsWith("breakpoint #1 in data:"));

    await isolate.resume();
    await isolate.waitUntilPaused();

    // Wait long enough for the print to propagate to the future.
    await new Future.delayed(Duration.zero);
    expect(line1.result.asValue.value, equals("one"));
    expect(line2.result, isNull);

    breakpoint = await breakpoint.load();
    expect(breakpoint.number, equals(1));
    expect(breakpoint, new TypeMatcher<VMResolvedBreakpoint>());
    expect(breakpoint.location, new TypeMatcher<VMSourceLocation>());
    expect(breakpoint.location.uri.scheme, equals('data'));

    expect(await sourceLine(breakpoint.location), equals(8));
  });

  test("removes the breakpoint when remove() is called", () async {
    client = await runAndConnect(main: r"""
      print("one");
      print("two"); // line 9
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    var stdout = new StreamQueue(isolate.stdout.transform(lines));
    expect(stdout.next, completion(equals("one")));
    expect(stdout.next, completion(equals("two")));

    await isolate.waitUntilPaused();
    var library = await (await isolate.loadRunnable()).rootLibrary.load();
    var breakpoint = await library.scripts.single.addBreakpoint(9);
    expect(breakpoint.number, equals(1));
    expect(breakpoint, isNot(new TypeMatcher<VMResolvedBreakpoint>()));
    expect(breakpoint.location, new TypeMatcher<VMUnresolvedSourceLocation>());
    expect(breakpoint.location.uri.scheme, equals('data'));
    expect(breakpoint.toString(), startsWith("breakpoint #1 in data:"));

    await breakpoint.remove();

    // Only a single resume event should fire.
    isolate.onPauseOrResume.listen(expectAsync1((event) {
      expect(event, new TypeMatcher<VMResumeEvent>());
    }));

    await isolate.resume();
  });

  test("onPause fires events when the breakpoint is reached", () async {
    client = await runAndConnect(main: r"""
      print("before");
      for (var i = 0; i < 3; i++) {
        print(i); // line 10
      }
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    var stdout = new StreamQueue(isolate.stdout
        .transform(lines)
        .transform(const SingleSubscriptionTransformer()));

    await isolate.waitUntilPaused();
    var library = await (await isolate.loadRunnable()).rootLibrary.load();
    var breakpoint = await library.scripts.single.addBreakpoint(10);
    expect(breakpoint, isNot(new TypeMatcher<VMResolvedBreakpoint>()));
    expect(breakpoint.location, new TypeMatcher<VMUnresolvedSourceLocation>());

    var times = 0;
    breakpoint.onPause.listen(expectAsync1((eventBreakpoint) async {
      expect(eventBreakpoint.number, equals(breakpoint.number));
      var i = (await isolate.getStack()).frames.first.variables['i'].value;
      expect(i, new TypeMatcher<VMIntInstanceRef>());
      expect(i.value, equals(times));
      times++;
      isolate.resume();
    }, count: 3));

    await isolate.resume();
    expect(await stdout.next, equals("before"));
    expect(await stdout.next, equals("0"));
    expect(await stdout.next, equals("1"));
    expect(await stdout.next, equals("2"));
  });

  test("onRemove fires once the breakpoint is removed", () async {
    client = await runAndConnect(main: r"""
      print("one");
      print("two"); // line 9
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    await isolate.waitUntilPaused();
    var library = await (await isolate.loadRunnable()).rootLibrary.load();
    var breakpoint = await library.scripts.single.addBreakpoint(9);

    var onRemoveFuture = breakpoint.onRemove;

    expect((await isolate.load()).breakpoints.first.remove(), completes);

    await onRemoveFuture;
  });

  test("onRemove fires if the breakpoint has already been removed", () async {
    client = await runAndConnect(main: r"""
      print("one");
      print("two"); // line 9
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    await isolate.waitUntilPaused();
    var library = await (await isolate.loadRunnable()).rootLibrary.load();
    var breakpoint = await library.scripts.single.addBreakpoint(9);

    (await isolate.load()).breakpoints.first.remove();

    await breakpoint.onRemove;
  });

  test("loadResolved returns the breakpoint once it becomes resolved",
      () async {
    client = await runAndConnect(main: r"""
      print("one");
      print("two"); // line 9
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    await isolate.waitUntilPaused();
    var library = await (await isolate.loadRunnable()).rootLibrary.load();
    var breakpoint = await library.scripts.single.addBreakpoint(9);
    expect(breakpoint, isNot(new TypeMatcher<VMResolvedBreakpoint>()));
    expect(breakpoint.location, new TypeMatcher<VMUnresolvedSourceLocation>());

    var resolvedFuture = breakpoint.loadResolved();
    await isolate.resume();
    breakpoint = await resolvedFuture;
    expect(breakpoint, new TypeMatcher<VMResolvedBreakpoint>());
    expect(breakpoint.location, new TypeMatcher<VMSourceLocation>());
  });

  test("loadResolved returns an already-resolved breakpoint", () async {
    client = await runAndConnect(main: r"""
      print("one");
      print("two"); // line 9
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = (await client.getVM()).isolates.first;

    await isolate.waitUntilPaused();
    var library = await (await isolate.loadRunnable()).rootLibrary.load();
    var breakpoint = await library.scripts.single.addBreakpoint(9);
    expect(breakpoint, isNot(new TypeMatcher<VMResolvedBreakpoint>()));
    expect(breakpoint.location, new TypeMatcher<VMUnresolvedSourceLocation>());

    await isolate.resume();
    await isolate.waitUntilPaused();
    var resolved = await breakpoint.loadResolved();
    expect(resolved, new TypeMatcher<VMResolvedBreakpoint>());
    expect(resolved.location, new TypeMatcher<VMSourceLocation>());
  });
}
