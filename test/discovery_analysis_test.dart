// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:io";

import "package:package_config_x/package_config.dart";
import "package:test/test.dart";

import "src/util.dart";

const emptyDir = <String, Object>{};

main() {
  return;
  fileGroup("basic", {
    ".packages": packagesFile,
    ".dart_tool": {
      "package_config.json": packageConfigJsonFile,
    },
    "foo": {
      ".packages": packagesFile,
      ".dart_tool": emptyDir,
    },
    "bar": {
      "packages": {
        // Package directory no longer supported.
        "foo": emptyDir,
        "bar": emptyDir,
        "baz": emptyDir,
      }
    },
    "packages": {
      "foo": emptyDir,
      "bar": emptyDir,
      "baz": emptyDir,
    },
    "baz": emptyDir,
  }, (Directory directory) {
    test("find in current dir", () {
      var result = findPackageConfig(directory);
      expect(result.version, 2);
      expect(result.packages.map((x) => x.name),
          unorderedEquals(["foo", "bar", "baz"]));
    });

    test("find from subdir", () {
      var subdir = subDir(directory, "baz");
      // Should find the same configuration as the previous test.
      var result = findPackageConfig(subdir);
      expect(result.version, 2);
      expect(result.packages.map((x) => x.name),
          unorderedEquals(["foo", "bar", "baz"]));
    });

    var dirUri = new Uri.directory(directory.path);
    PackageContext ctx = PackageContext.findAll(directory);
    PackageContext root = ctx[directory];
    expect(root, same(ctx));
    validatePackagesFile(root.packageConfig, dirUri);
    var fooDir = subDir(directory, "foo");
    PackageContext foo = ctx[fooDir];
    expect(identical(root, foo), isFalse);
    validatePackagesFile(foo.packageConfig, dirUri.resolve("foo/"));
    var barDir = subDir(directory, "bar");
    PackageContext bar = ctx[subDir(directory, "bar")];
    validatePackagesDir(bar.packageConfig, dirUri.resolve("bar/"));
    PackageContext barbar = ctx[subDir(barDir, "bar")];
    expect(barbar, same(bar)); // inherited.
    PackageContext baz = ctx[subDir(directory, "baz")];
    expect(baz, same(root)); // inherited.

    var map = ctx.asMap();
    expect(map.keys.map((dir) => dir.path),
        unorderedEquals([directory.path, fooDir.path, barDir.path]));
    return null;
  });
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

const String packageConfigJsonFile = r"""
{
  "configVersion": 2,
  "packages": [

  ]
}
""";

const packageConfigJson = r"""
{
  "configVersion": 2,
  "packages": [
    {
      "name": "package1",
      "rootUri": "../../bar/",
      "packageUri": "lib/",
    },
  ]
}
""";
