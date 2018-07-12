// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';

import 'utils.dart';

void main() {
  VMServiceClient client;
  VMRunnableIsolate isolate;
  VMScriptRef scriptRef;
  VMScript script;
  VMField foo;
  VMFunction bar;
  VMFunction baz;

  setUp(() async {
    client = await runAndConnect(topLevel: r"""
      final foo = 1; // line 2

      int bar() => 1; // line 4

      int baz() { // line 6
        return 1;
      }
    """, flags: ["--pause-isolates-on-start"]);
    isolate = await (await client.getVM()).isolates.first.load();
    scriptRef = (await isolate.rootLibrary.load()).scripts.single;

    script = await scriptRef.load();
    var library = await isolate.rootLibrary.load();
    foo = await library.fields["foo"].load();
    bar = await library.functions["bar"].load();
    baz = await library.functions["baz"].load();
  });

  tearDown(() {
    if (client != null) client.close();
  });

  test("includes the script's metadata", () {
    expect(scriptRef.uri.scheme, equals("data"));
    expect(script.library.uri, equals(script.uri));
    expect(script.source, contains("final foo = 1;"));
    expect(script.sourceFile.length, equals(script.source.length));
  });

  group("sourceLocation()", () {
    FileLocation fooLocation;
    FileLocation barLocation;
    FileLocation bazLocation;

    setUp(() {
      fooLocation = script.sourceLocation(foo.location.token);
      barLocation = script.sourceLocation(bar.location.token);
      bazLocation = script.sourceLocation(baz.location.token);
    });

    test("looks up a source location", () {
      expect(fooLocation.file, same(script.sourceFile));
      expect(fooLocation.sourceUrl, equals(script.uri));
      expect(fooLocation.line, equals(2));
      expect(fooLocation.column, equals(12));
      expect(fooLocation.offset, equals(149));
    });

    group("compareTo()", () {
      test("is ordered by location", () {
        expect(fooLocation.compareTo(barLocation), lessThan(0));
        expect(barLocation.compareTo(fooLocation), greaterThan(0));
        expect(fooLocation.compareTo(fooLocation), equals(0));
      });

      test("works with foreign locations", () {
        var file = new SourceFile.fromString(script.source, url: script.uri);

        expect(barLocation.compareTo(file.location(fooLocation.offset)),
            greaterThan(0));
        expect(barLocation.compareTo(file.location(barLocation.offset)),
            equals(0));
        expect(barLocation.compareTo(file.location(bazLocation.offset)),
            lessThan(0));
      });

      test("throws for non-matching URLs", () async {
        var library = await isolate.libraries[Uri.parse("dart:core")].load();
        var function = await library.functions["identical"].load();
        var script = await function.location.script.load();
        var span = script.sourceLocation(function.location.token);
        expect(() => fooLocation.compareTo(span), throwsArgumentError);
      });

      test("throws for non-matching URLs on foreign locations", () {
        var file = new SourceFile.fromString(script.source,
            url: Uri.parse("other.dart"));
        expect(() => fooLocation.compareTo(file.location(fooLocation.offset)),
            throwsArgumentError);
      });
    });

    group("operator ==", () {
      test("returns true for matching locations", () {
        expect(fooLocation, equals(fooLocation));
      });

      test("returns true for matching foreign locations", () {
        var file = new SourceFile.fromString(script.source, url: script.uri);
        expect(fooLocation, equals(file.location(fooLocation.offset)));
      });

      test("returns false for non-matching URLs on foreign locations", () {
        var file = new SourceFile.fromString(script.source,
            url: Uri.parse("other.dart"));
        expect(fooLocation, isNot(equals(file.location(fooLocation.offset))));
      });
    });

    test("pointSpan() returns a point span at this location", () {
      var span = fooLocation.pointSpan();
      expect(span.start, equals(fooLocation));
      expect(span.end, equals(fooLocation));
    });
  });

  group("sourceSpan()", () {
    FileSpan fooSpan;
    FileSpan barSpan;
    FileSpan bazSpan;

    setUp(() {
      fooSpan = script.sourceSpan(foo.location);
      barSpan = script.sourceSpan(bar.location);
      bazSpan = script.sourceSpan(baz.location);
    });

    test("looks up a source span", () async {
      expect(barSpan.file, same(script.sourceFile));
      expect(barSpan.sourceUrl, equals(script.uri));
      expect(barSpan.length, equals(barSpan.text.length));
      expect(barSpan.text, equals("int bar() => 1"));
      expect(barSpan.context, equals("      int bar() => 1; // line 4\n"));

      expect(barSpan.start.line, equals(4));
      expect(barSpan.start.column, equals(6));
      expect(barSpan.start.offset, equals(175));

      expect(barSpan.end.line, equals(4));
      expect(barSpan.end.column, equals(20));
      expect(barSpan.end.offset, equals(189));
    });

    test("looks up a multiline source span", () async {
      expect(bazSpan.file, same(script.sourceFile));
      expect(bazSpan.sourceUrl, equals(script.uri));
      expect(bazSpan.length, equals(bazSpan.text.length));

      // Bizarrely, the VM doesn't seem to include the final "}" in the source
      // location.
      expect(
          bazSpan.text,
          equals("int baz() { // line 6\n"
              "        return 1;\n"
              "      "));
      expect(
          bazSpan.context,
          equals("      int baz() { // line 6\n"
              "        return 1;\n"
              "      }\n"));

      expect(bazSpan.start.line, equals(6));
      expect(bazSpan.start.column, equals(6));
      expect(bazSpan.start.offset, equals(208));

      expect(bazSpan.end.line, equals(8));
      expect(bazSpan.end.column, equals(6));
      expect(bazSpan.end.offset, equals(254));
    });

    group("compareTo()", () {
      test("is ordered by start location", () {
        expect(fooSpan.compareTo(barSpan), lessThan(0));
        expect(barSpan.compareTo(fooSpan), greaterThan(0));
        expect(fooSpan.compareTo(fooSpan), equals(0));
      });

      test("works with foreign spans", () {
        var file = new SourceFile.fromString(script.source, url: script.uri);

        expect(
            barSpan
                .compareTo(file.span(fooSpan.start.offset, fooSpan.end.offset)),
            greaterThan(0));
        expect(
            barSpan
                .compareTo(file.span(barSpan.start.offset, barSpan.end.offset)),
            equals(0));
        expect(
            barSpan
                .compareTo(file.span(bazSpan.start.offset, bazSpan.end.offset)),
            lessThan(0));
      });

      test("throws for non-matching URLs", () async {
        var library = await isolate.libraries[Uri.parse("dart:core")].load();
        var function = await library.functions["identical"].load();
        var script = await function.location.script.load();
        var span = script.sourceSpan(function.location);
        expect(() => fooSpan.compareTo(span), throwsArgumentError);
      });

      test("throws for non-matching URLs on foreign spans", () {
        var file = new SourceFile.fromString(script.source,
            url: Uri.parse("other.dart"));
        var span = file.span(fooSpan.start.offset, fooSpan.end.offset);
        expect(() => fooSpan.compareTo(span), throwsArgumentError);
      });
    });

    group("operator ==", () {
      test("returns true for matching spans", () {
        expect(fooSpan, equals(fooSpan));
      });

      test("returns true for matching foreign spans", () {
        var file = new SourceFile.fromString(script.source, url: script.uri);
        expect(fooSpan,
            equals(file.span(fooSpan.start.offset, fooSpan.end.offset)));
      });

      test("returns false for non-matching URLs on foreign spans", () {
        var file = new SourceFile.fromString(script.source,
            url: Uri.parse("other.dart"));
        var span = file.span(fooSpan.start.offset, fooSpan.end.offset);
        expect(fooSpan, isNot(equals(span)));
      });
    });

    group("union()", () {
      test("unions overlapping spans", () {
        var fooBar = fooSpan.expand(barSpan);
        var barBaz = barSpan.expand(bazSpan);

        var unioned = fooBar.union(barBaz);
        expect(unioned.start, equals(fooSpan.start));
        expect(unioned.end, equals(bazSpan.end));

        unioned = barBaz.union(fooBar);
        expect(unioned.start, equals(fooSpan.start));
        expect(unioned.end, equals(bazSpan.end));
      });

      test("unions a script span with a foreign span", () {
        var file = new SourceFile.fromString(script.source, url: script.uri);
        var shiftedSpan =
            file.span(barSpan.start.offset + 1, barSpan.end.offset + 1);

        var unioned = barSpan.union(shiftedSpan);
        expect(unioned.start, equals(barSpan.start));
        expect(unioned.end, equals(shiftedSpan.end));
      });

      test("throws for disjoint spans", () {
        expect(() => fooSpan.union(barSpan), throwsArgumentError);
      });

      test("throws for non-matching URLs", () async {
        var library = await isolate.libraries[Uri.parse("dart:core")].load();
        var function = await library.functions["identical"].load();
        var script = await function.location.script.load();
        var span = script.sourceSpan(function.location);
        expect(() => fooSpan.union(span), throwsArgumentError);
      });

      test("throws for non-matching URLs on foreign spans", () {
        var file = new SourceFile.fromString(script.source,
            url: Uri.parse("other.dart"));
        var span = file.span(fooSpan.start.offset, fooSpan.end.offset);
        expect(() => fooSpan.union(span), throwsArgumentError);
      });
    });

    group("expand()", () {
      test("expands to cover another span", () {
        var expanded = fooSpan.expand(barSpan);
        expect(expanded.start, equals(fooSpan.start));
        expect(expanded.end, equals(barSpan.end));
      });

      test("expands to cover a foreign span", () {
        var file = new SourceFile.fromString(script.source, url: script.uri);
        var span = file.span(barSpan.start.offset, barSpan.end.offset);

        var expanded = fooSpan.expand(span);
        expect(expanded.start, equals(fooSpan.start));
        expect(expanded.end, equals(barSpan.end));
      });

      test("throws for non-matching URLs", () async {
        var library = await isolate.libraries[Uri.parse("dart:core")].load();
        var function = await library.functions["identical"].load();
        var script = await function.location.script.load();
        var span = script.sourceSpan(function.location);
        expect(() => fooSpan.expand(span), throwsArgumentError);
      });

      test("throws for non-matching URLs on foreign spans", () {
        var file = new SourceFile.fromString(script.source,
            url: Uri.parse("other.dart"));
        var span = file.span(barSpan.start.offset, barSpan.end.offset);
        expect(() => fooSpan.expand(span), throwsArgumentError);
      });
    });
  });
}
