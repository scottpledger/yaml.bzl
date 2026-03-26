"""Tests for YAML serialization."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//:yaml.bzl", "yaml")

def _dump_simple_mapping_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump({
        "name": "svc",
        "enabled": True,
        "count": 2,
    })

    asserts.true(env, "name: svc" in text, "Dump should include plain key/value pairs")
    asserts.true(env, "enabled: true" in text, "Dump should include bool values")
    asserts.true(env, "count: 2" in text, "Dump should include int values")

    return unittest.end(env)

_dump_simple_mapping_test = unittest.make(_dump_simple_mapping_test_impl)

def _dump_nested_structure_test_impl(ctx):
    env = unittest.begin(ctx)

    data = {
        "service": {
            "ports": [8080, 8443],
            "flags": {
                "trace": False,
            },
        },
    }
    text = yaml.dump(data)

    asserts.true(env, "service:" in text, "Dump should contain nested keys")
    asserts.true(env, "ports:" in text, "Dump should contain nested sequence key")
    asserts.true(env, "- 8080" in text, "Dump should contain block sequence values")
    asserts.true(env, "trace: false" in text, "Dump should contain nested booleans")

    return unittest.end(env)

_dump_nested_structure_test = unittest.make(_dump_nested_structure_test_impl)

def _dump_multiline_string_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump({"script": "echo one\necho two"})
    asserts.true(env, "script: |-" in text, "Dump should use literal block scalar for multiline text")
    asserts.true(env, "  echo one" in text, "Dump should emit first multiline content line")
    asserts.true(env, "  echo two" in text, "Dump should emit second multiline content line")

    return unittest.end(env)

_dump_multiline_string_test = unittest.make(_dump_multiline_string_test_impl)

def _dump_quotes_ambiguous_strings_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump({
        "bool_like": "true",
        "null_like": "null",
        "question": "?",
        "colon": ":",
    }, sort_keys = True)

    asserts.true(env, 'bool_like: "true"' in text, "Bool-like string should be quoted")
    asserts.true(env, 'null_like: "null"' in text, "Null-like string should be quoted")
    asserts.true(env, 'question: "?"' in text, "Ambiguous question indicator should be quoted")
    asserts.true(env, 'colon: ":"' in text, "Ambiguous colon indicator should be quoted")

    decoded = yaml.get_value(yaml.parse(text))
    asserts.equals(env, "true", decoded["bool_like"])
    asserts.equals(env, "null", decoded["null_like"])
    asserts.equals(env, "?", decoded["question"])
    asserts.equals(env, ":", decoded["colon"])

    return unittest.end(env)

_dump_quotes_ambiguous_strings_test = unittest.make(_dump_quotes_ambiguous_strings_test_impl)

def _dump_sort_keys_mixed_types_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump({
        "a": "v4",
        2: "v2",
        1.5: "v3",
        False: "v1",
        None: "v0",
    }, sort_keys = True)

    idx_null = text.find("null: v0")
    idx_false = text.find("false: v1")
    idx_two = text.find("2: v2")
    idx_float = text.find("1.5: v3")
    idx_string = text.find("a: v4")

    asserts.true(env, idx_null >= 0, "Null key should be emitted")
    asserts.true(env, idx_false >= 0, "Bool key should be emitted")
    asserts.true(env, idx_two >= 0, "Int key should be emitted")
    asserts.true(env, idx_float >= 0, "Float key should be emitted")
    asserts.true(env, idx_string >= 0, "String key should be emitted")
    asserts.true(env, idx_null < idx_false and idx_false < idx_two and idx_two < idx_float and idx_float < idx_string, "Mixed key sort order should be deterministic")

    decoded = yaml.get_value(yaml.parse(text))
    asserts.equals(env, "v0", decoded[None])
    asserts.equals(env, "v1", decoded[False])
    asserts.equals(env, "v2", decoded[2])
    asserts.equals(env, "v3", decoded[1.5])
    asserts.equals(env, "v4", decoded["a"])

    return unittest.end(env)

_dump_sort_keys_mixed_types_test = unittest.make(_dump_sort_keys_mixed_types_test_impl)

def _dump_flow_style_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump({
        "kind": "svc",
        "ports": [8080, 8443],
    }, flow_style = True)
    asserts.true(env, text.startswith("{"), "Flow-style dump should emit JSON-style flow mapping")
    asserts.true(env, '"ports"' in text, "Flow-style output should include nested keys")

    decoded = yaml.get_value(yaml.parse(text))
    asserts.equals(env, "svc", decoded["kind"])
    asserts.equals(env, 8443, decoded["ports"][1])

    return unittest.end(env)

_dump_flow_style_test = unittest.make(_dump_flow_style_test_impl)

def _dump_roundtrip_test_impl(ctx):
    env = unittest.begin(ctx)

    original = {
        "name": "example",
        "items": [
            {"id": 1, "ok": True},
            {"id": 2, "ok": False},
        ],
        "note": "hello world",
    }
    encoded = yaml.dump(original)
    decoded = yaml.get_value(yaml.parse(encoded))

    asserts.equals(env, "example", decoded["name"])
    asserts.equals(env, 2, len(decoded["items"]))
    asserts.equals(env, False, decoded["items"][1]["ok"])
    asserts.equals(env, "hello world", decoded["note"])

    return unittest.end(env)

_dump_roundtrip_test = unittest.make(_dump_roundtrip_test_impl)

def _dump_all_documents_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump_all([
        {"kind": "one"},
        {"kind": "two"},
    ], explicit_start = True)

    docs = yaml.parse_all(text)
    asserts.equals(env, 2, len(docs))
    asserts.equals(env, "one", yaml.get_value(docs[0])["kind"])
    asserts.equals(env, "two", yaml.get_value(docs[1])["kind"])

    return unittest.end(env)

_dump_all_documents_test = unittest.make(_dump_all_documents_test_impl)

def _dump_all_flow_style_documents_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump_all([
        {"kind": "one"},
        {"kind": "two"},
    ], explicit_start = True, flow_style = True)

    asserts.true(env, "---" in text, "Flow-style stream should still support explicit markers")
    asserts.true(env, '{"kind":"one"}' in text, "First flow-style document should be emitted")
    asserts.true(env, '{"kind":"two"}' in text, "Second flow-style document should be emitted")

    docs = yaml.parse_all(text)
    asserts.equals(env, 2, len(docs))
    asserts.equals(env, "one", yaml.get_value(docs[0])["kind"])
    asserts.equals(env, "two", yaml.get_value(docs[1])["kind"])

    return unittest.end(env)

_dump_all_flow_style_documents_test = unittest.make(_dump_all_flow_style_documents_test_impl)

def _dump_anchor_alias_roundtrip_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump({
        "base": yaml.anchor("cfg", {
            "x": 1,
            "y": 2,
        }),
        "use": yaml.alias("cfg"),
    }, sort_keys = True)

    asserts.true(env, "base: &cfg" in text, "Anchored mapping should emit anchor property")
    asserts.true(env, "use: *cfg" in text, "Alias should emit alias token")

    decoded = yaml.get_value(yaml.parse(text))
    asserts.equals(env, 1, decoded["use"]["x"])
    asserts.equals(env, 2, decoded["use"]["y"])

    return unittest.end(env)

_dump_anchor_alias_roundtrip_test = unittest.make(_dump_anchor_alias_roundtrip_test_impl)

def _dump_tagged_scalars_roundtrip_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump({
        "as_int": yaml.tag("!!int", "42"),
        "as_bool": yaml.tag("!!bool", "true"),
        "as_string": yaml.tag("!!str", "true"),
    }, sort_keys = True)

    asserts.true(env, 'as_int: !!int "42"' in text, "Tagged int scalar should emit explicit tag")
    asserts.true(env, 'as_bool: !!bool "true"' in text, "Tagged bool scalar should emit explicit tag")
    asserts.true(env, 'as_string: !!str "true"' in text, "Tagged string scalar should emit explicit tag")

    decoded = yaml.get_value(yaml.parse(text))
    asserts.equals(env, 42, decoded["as_int"])
    asserts.equals(env, True, decoded["as_bool"])
    asserts.equals(env, "true", decoded["as_string"])

    return unittest.end(env)

_dump_tagged_scalars_roundtrip_test = unittest.make(_dump_tagged_scalars_roundtrip_test_impl)

def _dump_with_directives_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump(
        {
            "custom": yaml.tag("!e!thing", "abc"),
            "kind": "demo",
        },
        sort_keys = True,
        explicit_start = False,
        yaml_version = "1.2",
        tag_directives = {"!e!": "tag:example.com,2026:"},
    )

    asserts.true(env, text.startswith("%YAML 1.2\n%TAG !e! tag:example.com,2026:\n---"), "Directives should be emitted before document start")
    asserts.true(env, "custom: !e!thing abc" in text, "Tagged value should use declared handle")

    doc = yaml.parse(text)
    asserts.false(env, yaml.has_errors(doc), "Directive-emitted document should parse without errors")
    decoded = yaml.get_value(doc)
    asserts.equals(env, "abc", decoded["custom"])
    asserts.equals(env, "demo", decoded["kind"])

    return unittest.end(env)

_dump_with_directives_test = unittest.make(_dump_with_directives_test_impl)

def _dump_all_with_directives_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump_all(
        [
            {"kind": "one"},
            {"kind": "two"},
        ],
        explicit_start = False,
        yaml_version = "1.2",
        tag_directives = [["!e!", "tag:example.com,2026:"]],
    )

    asserts.true(env, text.count("%YAML 1.2") == 2, "Each dumped document should include YAML version directive")
    asserts.true(env, text.count("%TAG !e! tag:example.com,2026:") == 2, "Each dumped document should include TAG directive")
    asserts.true(env, text.count("---") == 2, "Directives should force explicit document starts")
    asserts.true(env, text.count("...") == 2, "Directive documents in a stream should be explicitly terminated")

    docs = yaml.parse_all(text)
    asserts.equals(env, 2, len(docs))
    asserts.equals(env, "one", yaml.get_value(docs[0])["kind"])
    asserts.equals(env, "two", yaml.get_value(docs[1])["kind"])
    asserts.false(env, yaml.has_errors(docs[0]), "First doc should parse cleanly")
    asserts.false(env, yaml.has_errors(docs[1]), "Second doc should parse cleanly")

    return unittest.end(env)

_dump_all_with_directives_test = unittest.make(_dump_all_with_directives_test_impl)

def _validate_dump_directives_ok_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, [], yaml.validate_dump_directives(None, None))
    asserts.equals(env, [], yaml.validate_dump_directives("1.2", None))
    asserts.equals(env, [], yaml.validate_dump_directives(None, {}))
    asserts.equals(env, [], yaml.validate_dump_directives(None, {"!": "tag:yaml.org,2002:"}))
    asserts.equals(env, [], yaml.validate_dump_directives(None, {"!!": "tag:yaml.org,2002:"}))
    asserts.equals(env, [], yaml.validate_dump_directives(None, {"!e!": "tag:example.com,2026:"}))
    asserts.equals(env, [], yaml.validate_dump_directives(None, [["!e!", "tag:example.com,2026:"]]))

    return unittest.end(env)

_validate_dump_directives_ok_test = unittest.make(_validate_dump_directives_ok_test_impl)

def _validate_dump_directives_errors_test_impl(ctx):
    env = unittest.begin(ctx)

    errs = yaml.validate_dump_directives("1.1", None)
    asserts.true(env, len(errs) > 0, "Unsupported yaml_version should error")

    errs = yaml.validate_dump_directives(None, {"handle": "tag:x:"})
    asserts.true(env, len(errs) > 0, "Non-bang handle should error")

    errs = yaml.validate_dump_directives(None, {"!e": "tag:x:"})
    asserts.true(env, len(errs) > 0, "Named handle without trailing ! should error")

    errs = yaml.validate_dump_directives(None, {"!e!": "tag: x"})
    asserts.true(env, len(errs) > 0, "Prefix with whitespace should error")

    errs = yaml.validate_dump_directives(None, {"!e!": 1})
    asserts.true(env, len(errs) > 0, "Non-string prefix should error")

    errs = yaml.validate_dump_directives(None, "not-a-dict")
    asserts.true(env, len(errs) > 0, "Wrong tag_directives type should error")

    errs = yaml.validate_dump_directives(None, [[]])
    asserts.true(env, len(errs) > 0, "Malformed list entry should error")

    return unittest.end(env)

_validate_dump_directives_errors_test = unittest.make(_validate_dump_directives_errors_test_impl)

def _dump_primary_secondary_tag_handles_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump(
        {
            "a": yaml.tag("!int", "5"),
            "b": yaml.tag("!!int", "6"),
        },
        sort_keys = True,
        yaml_version = "1.2",
        tag_directives = {
            "!": "tag:yaml.org,2002:",
            "!!": "tag:yaml.org,2002:",
        },
    )
    doc = yaml.parse(text)
    asserts.false(env, yaml.has_errors(doc), "Primary/secondary TAG handles should parse")
    root = yaml.get_value(doc)
    asserts.equals(env, 5, root["a"])
    asserts.equals(env, 6, root["b"])

    return unittest.end(env)

_dump_primary_secondary_tag_handles_test = unittest.make(_dump_primary_secondary_tag_handles_test_impl)

def _dump_with_explicit_markers_test_impl(ctx):
    env = unittest.begin(ctx)

    text = yaml.dump({"a": 1}, explicit_start = True, explicit_end = True)
    asserts.true(env, text.startswith("---"), "Document should start with explicit marker")
    asserts.true(env, text.endswith("..."), "Document should end with explicit marker")

    return unittest.end(env)

_dump_with_explicit_markers_test = unittest.make(_dump_with_explicit_markers_test_impl)

def yaml_serializer_test_suite(name):
    unittest.suite(
        name,
        _dump_simple_mapping_test,
        _dump_nested_structure_test,
        _dump_multiline_string_test,
        _dump_quotes_ambiguous_strings_test,
        _dump_sort_keys_mixed_types_test,
        _dump_flow_style_test,
        _dump_roundtrip_test,
        _dump_all_documents_test,
        _dump_all_flow_style_documents_test,
        _dump_with_directives_test,
        _dump_all_with_directives_test,
        _validate_dump_directives_ok_test,
        _validate_dump_directives_errors_test,
        _dump_primary_secondary_tag_handles_test,
        _dump_anchor_alias_roundtrip_test,
        _dump_tagged_scalars_roundtrip_test,
        _dump_with_explicit_markers_test,
    )
