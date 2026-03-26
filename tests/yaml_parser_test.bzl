"""Tests for YAML parsing features."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//:yaml.bzl", "yaml")

def _parse_simple_mapping_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
name: app
enabled: true
count: 3
ratio: 3.5
nothing: null
""")
    value = yaml.get_value(doc)

    asserts.true(env, yaml.is_document(doc), "parse() should return a YAML document")
    asserts.equals(env, "app", value["name"])
    asserts.equals(env, True, value["enabled"])
    asserts.equals(env, 3, value["count"])
    asserts.equals(env, 3.5, value["ratio"])
    asserts.equals(env, None, value["nothing"])

    return unittest.end(env)

_parse_simple_mapping_test = unittest.make(_parse_simple_mapping_test_impl)

def _parse_nested_collections_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
service:
  ports:
    - 80
    - 443
  metadata:
    team: platform
    owners:
      - alice
      - bob
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 2, len(root["service"]["ports"]))
    asserts.equals(env, 443, root["service"]["ports"][1])
    asserts.equals(env, "platform", root["service"]["metadata"]["team"])
    asserts.equals(env, "bob", root["service"]["metadata"]["owners"][1])

    return unittest.end(env)

_parse_nested_collections_test = unittest.make(_parse_nested_collections_test_impl)

def _parse_flow_collections_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
list: [1, 2, 3, "x"]
obj: {name: "svc", enabled: false}
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 4, len(root["list"]))
    asserts.equals(env, "x", root["list"][3])
    asserts.equals(env, "svc", root["obj"]["name"])
    asserts.equals(env, False, root["obj"]["enabled"])

    return unittest.end(env)

_parse_flow_collections_test = unittest.make(_parse_flow_collections_test_impl)

def _parse_nested_flow_collections_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
graph: [{name: root, children: [{name: leaf, values: [1, 2, {k: v}]}]}]
""")
    root = yaml.get_value(doc)

    asserts.equals(env, "root", root["graph"][0]["name"])
    asserts.equals(env, "leaf", root["graph"][0]["children"][0]["name"])
    asserts.equals(env, "v", root["graph"][0]["children"][0]["values"][2]["k"])

    return unittest.end(env)

_parse_nested_flow_collections_test = unittest.make(_parse_nested_flow_collections_test_impl)

def _parse_quoted_and_comment_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
plain: hello # trailing comment
single: 'hello # this is data'
double: "line\\nnext"
""")
    root = yaml.get_value(doc)

    asserts.equals(env, "hello", root["plain"])
    asserts.equals(env, "hello # this is data", root["single"])
    asserts.equals(env, "line\nnext", root["double"])

    return unittest.end(env)

_parse_quoted_and_comment_test = unittest.make(_parse_quoted_and_comment_test_impl)

def _parse_scalar_resolution_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
null1: ~
null2: null
hex: 0x10
oct: 0o10
pos_inf: .inf
neg_inf: -.inf
""")
    root = yaml.get_value(doc)

    asserts.equals(env, None, root["null1"])
    asserts.equals(env, None, root["null2"])
    asserts.equals(env, 16, root["hex"])
    asserts.equals(env, 8, root["oct"])
    asserts.true(env, root["pos_inf"] > 1000000.0, "Expected +infinity-like float")
    asserts.true(env, root["neg_inf"] < -1000000.0, "Expected -infinity-like float")

    return unittest.end(env)

_parse_scalar_resolution_test = unittest.make(_parse_scalar_resolution_test_impl)

def _parse_block_scalars_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
literal: |-
  line one
  line two
folded: >-
  hello
  world
""")
    root = yaml.get_value(doc)

    asserts.equals(env, "line one\nline two", root["literal"])
    asserts.equals(env, "hello world", root["folded"])

    return unittest.end(env)

_parse_block_scalars_test = unittest.make(_parse_block_scalars_test_impl)

def _parse_block_scalar_indicators_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
clip_default: |
  a
strip: |-
  b
keep: |+
  c

indented: |2
    d
""")
    root = yaml.get_value(doc)

    asserts.equals(env, "a\n", root["clip_default"])
    asserts.equals(env, "b", root["strip"])
    asserts.true(env, root["keep"].startswith("c"), "Keep mode should retain content")
    asserts.equals(env, "  d\n", root["indented"])

    return unittest.end(env)

_parse_block_scalar_indicators_test = unittest.make(_parse_block_scalar_indicators_test_impl)

def _parse_anchors_aliases_and_merge_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
defaults: &defaults
  retries: 3
  timeout: 10
dev:
  <<: *defaults
  timeout: 1
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 3, root["dev"]["retries"])
    asserts.equals(env, 1, root["dev"]["timeout"])

    return unittest.end(env)

_parse_anchors_aliases_and_merge_test = unittest.make(_parse_anchors_aliases_and_merge_test_impl)

def _parse_merge_sequence_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
base_a: &a {x: 1, y: 1}
base_b: &b {x: 2, z: 3}
merged:
  <<: [*a, *b]
  y: 9
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 9, root["merged"]["y"])
    asserts.equals(env, 1, root["merged"]["x"])
    asserts.equals(env, 3, root["merged"]["z"])

    return unittest.end(env)

_parse_merge_sequence_test = unittest.make(_parse_merge_sequence_test_impl)

def _parse_merge_alias_chain_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
base: &base
  retries: 3
mid: &mid
  <<: *base
  timeout: 10
leaf:
  <<: *mid
  timeout: 1
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 3, root["leaf"]["retries"])
    asserts.equals(env, 1, root["leaf"]["timeout"])

    return unittest.end(env)

_parse_merge_alias_chain_test = unittest.make(_parse_merge_alias_chain_test_impl)

def _parse_multiple_merge_keys_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
base_a: &a {x: 1, y: 1}
base_b: &b {x: 2, z: 3}
merged:
  <<: *a
  <<: *b
  y: 9
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 1, root["merged"]["x"])
    asserts.equals(env, 9, root["merged"]["y"])
    asserts.equals(env, 3, root["merged"]["z"])

    return unittest.end(env)

_parse_multiple_merge_keys_test = unittest.make(_parse_multiple_merge_keys_test_impl)

def _parse_sequence_of_mappings_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
items:
  - {name: alpha, enabled: true}
  - {name: beta, enabled: false}
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 2, len(root["items"]))
    asserts.equals(env, "alpha", root["items"][0]["name"])
    asserts.equals(env, False, root["items"][1]["enabled"])

    return unittest.end(env)

_parse_sequence_of_mappings_test = unittest.make(_parse_sequence_of_mappings_test_impl)

def _parse_all_documents_test_impl(ctx):
    env = unittest.begin(ctx)

    docs = yaml.parse_all("""
---
kind: one
...
---
kind: two
""")

    asserts.equals(env, 2, len(docs))
    asserts.equals(env, "one", yaml.get_value(docs[0])["kind"])
    asserts.equals(env, "two", yaml.get_value(docs[1])["kind"])

    return unittest.end(env)

_parse_all_documents_test = unittest.make(_parse_all_documents_test_impl)

def _parse_scientific_float_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: 6.02e2")
    root = yaml.get_value(doc)
    asserts.equals(env, 602.0, root["value"])

    return unittest.end(env)

_parse_scientific_float_test = unittest.make(_parse_scientific_float_test_impl)

def _parse_explicit_key_mapping_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
? apple
: red
? banana
: yellow
""")
    root = yaml.get_value(doc)

    asserts.equals(env, "red", root["apple"])
    asserts.equals(env, "yellow", root["banana"])

    return unittest.end(env)

_parse_explicit_key_mapping_test = unittest.make(_parse_explicit_key_mapping_test_impl)

def _parse_complex_explicit_key_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
? [env, prod]
: enabled
""")
    root = yaml.get_value(doc)

    # Complex keys are normalized to hashable JSON-string form.
    asserts.equals(env, "enabled", root['["env","prod"]'])

    return unittest.end(env)

_parse_complex_explicit_key_test = unittest.make(_parse_complex_explicit_key_test_impl)

def _parse_explicit_tags_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
as_str: !!str 123
as_int: !!int "42"
as_float: !!float 6.5
as_bool: !!bool "true"
as_null: !!null "ignored"
as_seq: !!seq [1, 2]
as_map: !!map {a: 1}
""")
    root = yaml.get_value(doc)

    asserts.equals(env, "123", root["as_str"])
    asserts.equals(env, 42, root["as_int"])
    asserts.equals(env, 6.5, root["as_float"])
    asserts.equals(env, True, root["as_bool"])
    asserts.equals(env, None, root["as_null"])
    asserts.equals(env, 2, len(root["as_seq"]))
    asserts.equals(env, 1, root["as_map"]["a"])

    return unittest.end(env)

_parse_explicit_tags_test = unittest.make(_parse_explicit_tags_test_impl)

def _parse_tag_handle_directive_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
%TAG !e! tag:yaml.org,2002:
---
value: !e!int "7"
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 7, root["value"])

    return unittest.end(env)

_parse_tag_handle_directive_test = unittest.make(_parse_tag_handle_directive_test_impl)

def _parse_yaml_directive_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
%YAML 1.2
---
name: ok
""")
    root = yaml.get_value(doc)
    asserts.equals(env, "ok", root["name"])
    asserts.false(env, yaml.has_errors(doc), "Valid YAML directive should not produce errors")

    return unittest.end(env)

_parse_yaml_directive_test = unittest.make(_parse_yaml_directive_test_impl)

def _parse_multiple_directives_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
%YAML 1.2
%TAG !e! tag:yaml.org,2002:
---
value: !e!int "9"
""")
    root = yaml.get_value(doc)
    asserts.equals(env, 9, root["value"])
    asserts.false(env, yaml.has_errors(doc), "Multiple directives before doc start should parse cleanly")

    return unittest.end(env)

_parse_multiple_directives_test = unittest.make(_parse_multiple_directives_test_impl)

def _line_break_normalization_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("text: |\r\n  a\r\n  b\r\n")
    root = yaml.get_value(doc)
    asserts.equals(env, "a\nb\n", root["text"])

    return unittest.end(env)

_line_break_normalization_test = unittest.make(_line_break_normalization_test_impl)

def _folded_more_indented_lines_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
text: >-
  line
    indented
  next
""")
    root = yaml.get_value(doc)
    asserts.equals(env, "line\n  indented\nnext", root["text"])

    return unittest.end(env)

_folded_more_indented_lines_test = unittest.make(_folded_more_indented_lines_test_impl)

def _parse_flow_quoted_keys_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse('obj: {"a:b": 1, "c,d": 2, "[x]": 3}')
    root = yaml.get_value(doc)

    asserts.equals(env, 1, root["obj"]["a:b"])
    asserts.equals(env, 2, root["obj"]["c,d"])
    asserts.equals(env, 3, root["obj"]["[x]"])

    return unittest.end(env)

_parse_flow_quoted_keys_test = unittest.make(_parse_flow_quoted_keys_test_impl)

def _parse_anchor_override_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
base: &x {v: 1}
override: &x {v: 2}
use: *x
""")
    root = yaml.get_value(doc)
    asserts.equals(env, 2, root["use"]["v"])

    return unittest.end(env)

_parse_anchor_override_test = unittest.make(_parse_anchor_override_test_impl)

def _parse_double_quoted_escapes_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse(r'value: "a\b\t\n\f\r\\\/z"')
    root = yaml.get_value(doc)
    value = root["value"]

    asserts.true(env, "\b" in value, "Should decode \\b")
    asserts.true(env, "\t" in value, "Should decode \\t")
    asserts.true(env, "\n" in value, "Should decode \\n")
    asserts.true(env, "\f" in value, "Should decode \\f")
    asserts.true(env, "\r" in value, "Should decode \\r")
    asserts.true(env, "\\" in value, "Should decode \\\\")
    asserts.true(env, "/" in value, "Should decode \\/")

    return unittest.end(env)

_parse_double_quoted_escapes_test = unittest.make(_parse_double_quoted_escapes_test_impl)

def _parse_merge_duplicate_key_interaction_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
base: &base
  x: 1
obj:
  x: 2
  <<: *base
""")
    root = yaml.get_value(doc)
    asserts.equals(env, 2, root["obj"]["x"])
    asserts.false(env, yaml.has_errors(doc), "Merge should not report duplicate key when explicit key already exists")

    return unittest.end(env)

_parse_merge_duplicate_key_interaction_test = unittest.make(_parse_merge_duplicate_key_interaction_test_impl)

def _quoted_merge_key_not_merge_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
base: &base {x: 1}
obj:
  "<<": *base
""")
    root = yaml.get_value(doc)
    asserts.true(env, "<<" in root["obj"], "Quoted merge key should be preserved as literal key")
    asserts.false(env, "x" in root["obj"], "Quoted merge key should not trigger merge behavior")

    return unittest.end(env)

_quoted_merge_key_not_merge_test = unittest.make(_quoted_merge_key_not_merge_test_impl)

def _parse_multiline_block_plain_scalar_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
msg: this is
  a multiline
  plain scalar
""")
    root = yaml.get_value(doc)
    asserts.equals(env, "this is a multiline plain scalar", root["msg"])

    return unittest.end(env)

_parse_multiline_block_plain_scalar_test = unittest.make(_parse_multiline_block_plain_scalar_test_impl)

def _parse_multiline_block_plain_sequence_item_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
items:
  - first line
    second line
  - next
""")
    root = yaml.get_value(doc)
    asserts.equals(env, "first line second line", root["items"][0])
    asserts.equals(env, "next", root["items"][1])

    return unittest.end(env)

_parse_multiline_block_plain_sequence_item_test = unittest.make(_parse_multiline_block_plain_sequence_item_test_impl)

def _parse_multiline_block_plain_blank_runs_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
msg: top

  mid


  end
""")
    root = yaml.get_value(doc)
    asserts.equals(env, "top\nmid\n\nend", root["msg"])

    return unittest.end(env)

_parse_multiline_block_plain_blank_runs_test = unittest.make(_parse_multiline_block_plain_blank_runs_test_impl)

def _parse_multiline_block_plain_comment_separator_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
msg: alpha
  # comment separator
  beta
""")
    root = yaml.get_value(doc)
    asserts.equals(env, "alpha\nbeta", root["msg"])

    return unittest.end(env)

_parse_multiline_block_plain_comment_separator_test = unittest.make(_parse_multiline_block_plain_comment_separator_test_impl)

def _parse_quoted_reserved_indicator_scalar_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: '@ok'")
    root = yaml.get_value(doc)
    asserts.equals(env, "@ok", root["value"])
    asserts.false(env, yaml.has_errors(doc), "Quoted reserved indicator should be accepted")

    return unittest.end(env)

_parse_quoted_reserved_indicator_scalar_test = unittest.make(_parse_quoted_reserved_indicator_scalar_test_impl)

def _parse_quoted_ambiguous_plain_scalars_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
qmark: '?'
colon: ':'
""")
    root = yaml.get_value(doc)
    asserts.equals(env, "?", root["qmark"])
    asserts.equals(env, ":", root["colon"])
    asserts.false(env, yaml.has_errors(doc), "Quoted ambiguous scalars should parse")

    return unittest.end(env)

_parse_quoted_ambiguous_plain_scalars_test = unittest.make(_parse_quoted_ambiguous_plain_scalars_test_impl)

def _parse_consistent_mixed_indentation_structure_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
root:
  - name: alpha
    values:
      - 1
      - 2
  - name: beta
    values:
      - 3
""")
    root = yaml.get_value(doc)
    asserts.equals(env, "alpha", root["root"][0]["name"])
    asserts.equals(env, 2, root["root"][0]["values"][1])
    asserts.equals(env, 3, root["root"][1]["values"][0])
    asserts.false(env, yaml.has_errors(doc), "Consistent indentation should not error")

    return unittest.end(env)

_parse_consistent_mixed_indentation_structure_test = unittest.make(_parse_consistent_mixed_indentation_structure_test_impl)

def _parse_unicode_escapes_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse(r'value: "\x41-\u0042-\U00000043-\U0001f600"')
    root = yaml.get_value(doc)
    value = root["value"]

    asserts.true(env, value.startswith("A-B-C-"), "Should decode x/u/U escapes")
    asserts.true(env, len(value) >= 7, "Should include high-plane codepoint")

    return unittest.end(env)

_parse_unicode_escapes_test = unittest.make(_parse_unicode_escapes_test_impl)

def _parse_numeric_separators_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
dec: 1_000
hex: 0x1f_f0
oct: 0o7_1
flt: 12_3.4_5
sci: 1_2.5e1_0
""")
    root = yaml.get_value(doc)

    asserts.equals(env, 1000, root["dec"])
    asserts.equals(env, 8176, root["hex"])
    asserts.equals(env, 57, root["oct"])
    asserts.equals(env, 123.45, root["flt"])
    asserts.equals(env, 125000000000.0, root["sci"])

    return unittest.end(env)

_parse_numeric_separators_test = unittest.make(_parse_numeric_separators_test_impl)

def _type_helpers_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("root: [1, 2]")
    value = yaml.get_value(doc)

    asserts.true(env, yaml.is_mapping(value), "Top-level value should be mapping")
    asserts.true(env, yaml.is_sequence(value["root"]), "root should be a sequence")
    asserts.true(env, yaml.is_scalar(value["root"][0]), "sequence element should be scalar")

    return unittest.end(env)

_type_helpers_test = unittest.make(_type_helpers_test_impl)

def _empty_document_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("")
    asserts.equals(env, None, yaml.get_value(doc))
    asserts.false(env, yaml.has_errors(doc), "empty document should not produce parser errors")

    return unittest.end(env)

_empty_document_test = unittest.make(_empty_document_test_impl)

def yaml_parser_test_suite(name):
    unittest.suite(
        name,
        _parse_simple_mapping_test,
        _parse_nested_collections_test,
        _parse_flow_collections_test,
        _parse_nested_flow_collections_test,
        _parse_quoted_and_comment_test,
        _parse_scalar_resolution_test,
        _parse_block_scalars_test,
        _parse_block_scalar_indicators_test,
        _parse_anchors_aliases_and_merge_test,
        _parse_merge_sequence_test,
        _parse_merge_alias_chain_test,
        _parse_multiple_merge_keys_test,
        _parse_sequence_of_mappings_test,
        _parse_all_documents_test,
        _parse_scientific_float_test,
        _parse_explicit_key_mapping_test,
        _parse_complex_explicit_key_test,
        _parse_explicit_tags_test,
        _parse_tag_handle_directive_test,
        _parse_yaml_directive_test,
        _parse_multiple_directives_test,
        _line_break_normalization_test,
        _folded_more_indented_lines_test,
        _parse_flow_quoted_keys_test,
        _parse_anchor_override_test,
        _parse_double_quoted_escapes_test,
        _parse_unicode_escapes_test,
        _parse_numeric_separators_test,
        _parse_merge_duplicate_key_interaction_test,
        _quoted_merge_key_not_merge_test,
        _parse_multiline_block_plain_scalar_test,
        _parse_multiline_block_plain_sequence_item_test,
        _parse_multiline_block_plain_blank_runs_test,
        _parse_multiline_block_plain_comment_separator_test,
        _parse_quoted_reserved_indicator_scalar_test,
        _parse_quoted_ambiguous_plain_scalars_test,
        _parse_consistent_mixed_indentation_structure_test,
        _type_helpers_test,
        _empty_document_test,
    )
