// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:io";

import "package:package_config/package_config.dart";
import "package:path/path.dart" as path;
import "package:test/test.dart";

const emptyDir = <String, Object>{};

main() {
  fileGroup("basic", {
    ".packages": packagesFile,
    ".dart_tool": {
      "package_config.json": packageConfigJsonFile,
    },
    "foo": {".packages": packagesFile},
    "bar": {
      "packages": {"foo": emptyDir, "bar": emptyDir, "baz": emptyDir}
    },
    "baz": {}
  }, (Directory directory) {
    test("find in current dir", () {
      var result = findPackageConfig(directory);
      expect(result.version, 2);
      expect(result.packages.map((x) => x.name),
          unorderedEquals(["foo", "bar", "baz"]));
    });
    var dirUri = new Uri.directory(directory.path);
    PackageContext ctx = PackageContext.findAll(directory);
    PackageContext root = ctx[directory];
    expect(root, same(ctx));
    validatePackagesFile(root.packageConfig, dirUri);
    var fooDir = sub(directory, "foo");
    PackageContext foo = ctx[fooDir];
    expect(identical(root, foo), isFalse);
    validatePackagesFile(foo.packageConfig, dirUri.resolve("foo/"));
    var barDir = sub(directory, "bar");
    PackageContext bar = ctx[sub(directory, "bar")];
    validatePackagesDir(bar.packageConfig, dirUri.resolve("bar/"));
    PackageContext barbar = ctx[sub(barDir, "bar")];
    expect(barbar, same(bar)); // inherited.
    PackageContext baz = ctx[sub(directory, "baz")];
    expect(baz, same(root)); // inherited.

    var map = ctx.asMap();
    expect(map.keys.map((dir) => dir.path),
        unorderedEquals([directory.path, fooDir.path, barDir.path]));
    return null;
  });
}

Directory sub(Directory parent, String dirName) {
  return new Directory(path.join(parent.path, dirName));
}

const packagesFile = """
# A comment
foo:file:///dart/packages/foo/
bar:http://example.com/dart/packages/bar/
baz:packages/baz/
""";

void validatePackagesFile(PackageConfig resolver, Uri location) {
  expect(resolver, isNotNull);
  expect(resolver.resolve(pkg("foo", "bar/baz")),
      equals(Uri.parse("file:///dart/packages/foo/bar/baz")));
  expect(resolver.resolve(pkg("bar", "baz/qux")),
      equals(Uri.parse("http://example.com/dart/packages/bar/baz/qux")));
  expect(resolver.resolve(pkg("baz", "qux/foo")),
      equals(location.resolve("packages/baz/qux/foo")));
  expect(resolver.packages, unorderedEquals(["foo", "bar", "baz"]));
}

void validatePackagesDir(PackageConfig resolver, Uri location) {
  // Expect three packages: foo, bar and baz
  expect(resolver, isNotNull);
  expect(resolver.resolve(pkg("foo", "bar/baz")),
      equals(location.resolve("packages/foo/bar/baz")));
  expect(resolver.resolve(pkg("bar", "baz/qux")),
      equals(location.resolve("packages/bar/baz/qux")));
  expect(resolver.resolve(pkg("baz", "qux/foo")),
      equals(location.resolve("packages/baz/qux/foo")));
  if (location.scheme == "file") {
    expect(resolver.packages, unorderedEquals(["foo", "bar", "baz"]));
  } else {
    expect(() => resolver.packages, throwsUnsupportedError);
  }
}

Uri pkg(String packageName, String packagePath) {
  var path;
  if (packagePath.startsWith('/')) {
    path = "$packageName$packagePath";
  } else {
    path = "$packageName/$packagePath";
  }
  return new Uri(scheme: "package", path: path);
}

/// Create a directory structure from [description] and runs [fileTests].
///
/// Description is a map, each key is a file entry. If the value is a map,
/// it's a sub-dir, otherwise it's a file and the value is the content
/// as a string.
void fileGroup(
    String name, Map<String, Object> description, void fileTests(Directory directory)) {
  group(name, () {
    Directory tempDir = Directory.systemTemp.createTempSync("pkgcfgtest");
    setUp(() {
      _createFiles(tempDir, description);
    });
    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });
    fileTests(tempDir);
  });
}

/// Creates a set of files under a new temporary directory.
/// Returns the temporary directory.
///
/// The [description] is a map from file names to content.
/// If the content is again a map, it represents a subdirectory
/// with the content as description.
/// Otherwise the content should be a string,
/// which is written to the file as UTF-8.
Directory createTestFiles(Map<String, Object> description) {
  var target = Directory.systemTemp.createTempSync("pkgcfgtest");
  _createFiles(target, description);
  return target;
}

// Creates temporary files in the target directory.
void _createFiles(Directory target, Map<String, Object> description) {
  description.forEach((name, content) {
    var entryName = path.join(target.path, name);
    if (content is Map<String, Object>) {
      _createFiles(Directory(entryName)..createSync(), content);
    } else {
      File(entryName).writeAsStringSync(content, flush: true);
    }
  });
}

const String packageConfigJsonFile = r"""
{
  "configVersion": 2,
  "packages": [

  ]
}
""";

const packageConfigJson = {
  "configVersion": 2,
  "packages": [
    {
      "name": "package1",
      "rootUri": "../../bar/",
      "packageUri": "lib/",
    },
  ]
};
