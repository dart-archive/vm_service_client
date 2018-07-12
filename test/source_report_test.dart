// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';

import 'utils.dart';

const _mainContent = r"""
  print("one");
  print("two");

  if (false) {
    print("three");
    print("four");
  }

  Isolate.current.kill();
""";

void main() {
  VMServiceClient client;
  VMIsolateRef isolate;

  tearDown(() {
    if (client != null) client.close();
  });

  group('getSourceReport for a script with one range', () {
    setUp(() async {
      client = await runAndConnect(main: _mainContent);

      isolate = (await client.getVM()).isolates.single;

      await isolate.waitUntilPaused();
    });

    test("returns a valid source report", () async {
      var report = await isolate.getSourceReport(
          includeCoverageReport: false, includePossibleBreakpoints: false);

      expect(report.ranges, hasLength(greaterThan(1)));

      var range = report.ranges.singleWhere((range) =>
          range.script.uri.toString().startsWith('data:application/dart'));

      expect(range.compiled, isTrue);

      var script = await range.script.load();

      var runnableIsolate = await isolate.loadRunnable();

      var rootLib = await runnableIsolate.rootLibrary.load();
      var mainFunction = await rootLib.functions['main'].load();

      var mainLocation = script.sourceSpan(mainFunction.location);

      var startLocation = script.sourceLocation(range.location.token);
      expect(startLocation, mainLocation.start);

      var endLocation = script.sourceLocation(range.location.end);
      expect(endLocation, mainLocation.end);

      expect(range.hits, isNull);
      expect(range.misses, isNull);
      expect(range.possibleBreakpoints, isNull);
    });

    test("reports accurate coverage information", () async {
      var report =
          await isolate.getSourceReport(includePossibleBreakpoints: false);

      var range = report.ranges.singleWhere((range) =>
          range.script.uri.toString().startsWith('data:application/dart'));
      expect(range.possibleBreakpoints, isNull);

      var script = await range.script.load();

      var hitLines =
          range.hits.map((token) => script.sourceLocation(token).line).toSet();
      expect(hitLines, [
        4, 5, // preamble
        7, //    print("one");
        8, //    print("two");
        15, //   Isolate.current.kill();
      ]);

      // The line that are not executed – two within the `if (false)` block
      var missedLines =
          range.misses.map((token) => script.sourceLocation(token).line);
      expect(missedLines, [11, 12]);
    });

    test("reports accurate breakpoint information", () async {
      var report = await isolate.getSourceReport(includeCoverageReport: false);

      var range = report.ranges.singleWhere((range) =>
          range.script.uri.toString().startsWith('data:application/dart'));

      expect(range.hits, isNull);
      expect(range.misses, isNull);

      var script = await range.script.load();
      expect(range.possibleBreakpoints, isNotEmpty);

      // represents the unique set of lines that can have breakpoints
      var breakPointLines = range.possibleBreakpoints
          .map((token) => script.sourceLocation(token).line)
          .toSet();
      expect(breakPointLines, [
        4, //  main entry point
        5, //  preamble
        7, //  print("one");
        8, //  print("two");
        11, // print("three");
        12, // print("four");
        15, // Isolate.current.kill();
        17 //  VM considers the last line of an async function breakpoint-able
      ]);
    });

    test("behaves correctly including coverage and breakpoints", () async {
      var report = await isolate.getSourceReport(
          includeCoverageReport: true, includePossibleBreakpoints: true);

      var range = report.ranges.singleWhere((range) =>
          range.script.uri.toString().startsWith('data:application/dart'));

      expect(range.hits, isNotEmpty);
      expect(range.misses, isNotEmpty);
      expect(range.possibleBreakpoints, isNotEmpty);
    });
  });

  group('getSourceReport with a multi-range script', () {
    VMScript script;
    VMLibrary rootLib;
    VMSourceLocation mainLocation;
    FileSpan mainFunctionSpan;
    VMSourceLocation unusedFieldLocation;

    setUp(() async {
      client = await runAndConnect(topLevel: r'''final unusedField = 5;

int unusedFunction(a, b) {
  return a + b;
}

void unusedFunction2(value) {
  print(value);
}''', main: _mainContent);

      isolate = (await client.getVM()).isolates.single;

      await isolate.waitUntilPaused();

      var runnableIsolate = await isolate.loadRunnable();
      rootLib = await runnableIsolate.rootLibrary.load();
      script = await rootLib.scripts.single.load();

      var mainFunction = await rootLib.functions['main'].load();
      mainLocation = mainFunction.location;
      mainFunctionSpan = script.sourceSpan(mainLocation);

      var unusedFieldRef = rootLib.fields['unusedField'];
      var unusedField = await unusedFieldRef.load();
      unusedFieldLocation = unusedField.location;
    });

    test("reports valid data with default arguments", () async {
      var report = await script.getSourceReport();

      expect(report.ranges, hasLength(3));

      var firstRange = report.ranges.first;
      expect(firstRange.compiled, isFalse);
      expect(firstRange.hits, isNull);
      expect(firstRange.misses, isNull);
      expect(firstRange.possibleBreakpoints, isNull);

      // TODO(kevmoo): it'd be nice if pkg/matcher had isBefore, isAfter
      // https://github.com/dart-lang/matcher/issues/34
      expect(script.sourceSpan(firstRange.location).compareTo(mainFunctionSpan),
          isNegative);

      var lastRange = report.ranges.last;
      expect(lastRange.compiled, isTrue);
      expect(script.sourceSpan(lastRange.location), equals(mainFunctionSpan));
    });

    test("reports all ranged compiled with forceCompile: true", () async {
      var report = await script.getSourceReport(forceCompile: true);

      expect(report.ranges, hasLength(3));

      var firstRange = report.ranges.first;
      expect(firstRange.compiled, isTrue);

      var secondRange = report.ranges.last;
      expect(secondRange.compiled, isTrue);
    });

    test("reports a valid subrange with the location argument", () async {
      var report = await script.getSourceReport(location: mainLocation);

      expect(script.sourceSpan(report.ranges.single.location),
          equals(mainFunctionSpan));
    });

    test("throws if a zero-length location is used", () async {
      expect(script.getSourceReport(location: unusedFieldLocation),
          throwsArgumentError);
    });
  });
}
