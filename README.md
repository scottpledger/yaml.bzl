# yaml.bzl

A pure Starlark YAML parser/serializer for Bazel.

## Features

- Parse YAML into native Starlark values (`dict`, `list`, scalars)
- Multi-document support (`---` / `...`)
- Block and flow styles
- Block scalars (`|` / `>`) including chomping indicators
- Anchors, aliases, and mapping merge key (`<<`)
- Round-trip friendly serializer
- Error collection with optional strict mode

## Installation

### With bzlmod

```starlark
bazel_dep(name = "yaml.bzl", version = "<version>")
```

### With WORKSPACE

```starlark
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "yaml.bzl",
    sha256 = "<sha256>",
    strip_prefix = "yaml.bzl-<version>",
    url = "https://github.com/scottpledger/yaml.bzl/releases/download/v<version>/yaml.bzl-v<version>.tar.gz",
)
```

## Usage

```starlark
load("@yaml.bzl//:yaml.bzl", "yaml")

doc = yaml.parse("""
service:
  name: demo
  ports: [8080, 8443]
""")

data = yaml.get_value(doc)
print(data["service"]["name"])  # demo

out = yaml.dump(data, sort_keys = True)
print(out)
```

## API

Load:

```starlark
load("@yaml.bzl//:yaml.bzl", "yaml")
```

Available members on `yaml`:

- `parse(yaml_string, strict = False) -> document`
- `parse_all(yaml_string, strict = False) -> [document]`
- `dump(value, indent = 0, indent_str = "  ", explicit_start = False, explicit_end = False, sort_keys = False, flow_style = False, yaml_version = None, tag_directives = None) -> string`
- `dump_all(values, indent = 0, indent_str = "  ", explicit_start = True, explicit_end = False, sort_keys = False, flow_style = False, yaml_version = None, tag_directives = None) -> string`
- `validate_dump_directives(yaml_version, tag_directives) -> [string]` (empty if `dump`/`dump_all` would accept those arguments)
- `tag(tag, value) -> tagged_node`
- `anchor(name, value) -> anchored_node`
- `alias(name) -> alias_node`
- `get_value(document) -> any`
- `has_errors(document) -> bool`
- `get_errors(document) -> [error]`
- `is_document(node) -> bool`
- `is_mapping(value) -> bool`
- `is_sequence(value) -> bool`
- `is_scalar(value) -> bool`

Error constants:

- `yaml.ERROR_SYNTAX`
- `yaml.ERROR_INDENTATION`
- `yaml.ERROR_UNKNOWN_ALIAS`
