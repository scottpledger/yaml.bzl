"""Tests for YAML parser error handling."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//:yaml.bzl", "yaml")

def _unknown_alias_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: *missing")
    asserts.true(env, yaml.has_errors(doc), "Unknown alias should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_UNKNOWN_ALIAS:
            found = True
    asserts.true(env, found, "Expected unknown alias error type")

    return unittest.end(env)

_unknown_alias_error_test = unittest.make(_unknown_alias_error_test_impl)

def _tab_indentation_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("root:\n\tchild: true")
    asserts.true(env, yaml.has_errors(doc), "Tab indentation should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_INDENTATION:
            found = True
    asserts.true(env, found, "Expected indentation error type")

    return unittest.end(env)

_tab_indentation_error_test = unittest.make(_tab_indentation_error_test_impl)

def _flow_mapping_syntax_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("obj: {name}")
    asserts.true(env, yaml.has_errors(doc), "Invalid flow mapping should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_flow_mapping_syntax_error_test = unittest.make(_flow_mapping_syntax_error_test_impl)

def _unterminated_flow_collection_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("obj: {a: [1, 2}")
    asserts.true(env, yaml.has_errors(doc), "Unterminated flow collection should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_unterminated_flow_collection_error_test = unittest.make(_unterminated_flow_collection_error_test_impl)

def _invalid_tag_value_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: !!int abc")
    asserts.true(env, yaml.has_errors(doc), "Invalid tagged scalar should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_invalid_tag_value_error_test = unittest.make(_invalid_tag_value_error_test_impl)

def _unknown_tag_handle_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: !x!int 1")
    asserts.true(env, yaml.has_errors(doc), "Unknown tag handle should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_unknown_tag_handle_error_test = unittest.make(_unknown_tag_handle_error_test_impl)

def _unsupported_yaml_version_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
%YAML 1.1
---
name: bad
""")
    asserts.true(env, yaml.has_errors(doc), "Unsupported YAML version should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_unsupported_yaml_version_error_test = unittest.make(_unsupported_yaml_version_error_test_impl)

def _directive_requires_doc_start_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
%TAG !e! tag:yaml.org,2002:
value: !e!int 1
""")
    asserts.true(env, yaml.has_errors(doc), "Directive without --- should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_directive_requires_doc_start_error_test = unittest.make(_directive_requires_doc_start_error_test_impl)

def _directive_after_content_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
name: first
%YAML 1.2
""")
    asserts.true(env, yaml.has_errors(doc), "Directive after content should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_directive_after_content_error_test = unittest.make(_directive_after_content_error_test_impl)

def _duplicate_block_key_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
a: 1
a: 2
""")
    asserts.true(env, yaml.has_errors(doc), "Duplicate block key should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_DUPLICATE_KEY:
            found = True
    asserts.true(env, found, "Expected duplicate key error type")

    return unittest.end(env)

_duplicate_block_key_error_test = unittest.make(_duplicate_block_key_error_test_impl)

def _duplicate_flow_key_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("obj: {a: 1, a: 2}")
    asserts.true(env, yaml.has_errors(doc), "Duplicate flow key should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_DUPLICATE_KEY:
            found = True
    asserts.true(env, found, "Expected duplicate key error type")

    return unittest.end(env)

_duplicate_flow_key_error_test = unittest.make(_duplicate_flow_key_error_test_impl)

def _duplicate_complex_explicit_key_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
? [a, b]
: 1
? [a, b]
: 2
""")
    asserts.true(env, yaml.has_errors(doc), "Duplicate complex explicit key should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_DUPLICATE_KEY:
            found = True
    asserts.true(env, found, "Expected duplicate key error type")

    return unittest.end(env)

_duplicate_complex_explicit_key_error_test = unittest.make(_duplicate_complex_explicit_key_error_test_impl)

def _invalid_flow_plain_scalar_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("items: [ok, b{c}]")
    asserts.true(env, yaml.has_errors(doc), "Invalid flow plain scalar should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_invalid_flow_plain_scalar_error_test = unittest.make(_invalid_flow_plain_scalar_error_test_impl)

def _invalid_unicode_escape_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse(r'value: "\u00ZZ"')
    asserts.true(env, yaml.has_errors(doc), "Invalid unicode escape should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_invalid_unicode_escape_error_test = unittest.make(_invalid_unicode_escape_error_test_impl)

def _unicode_out_of_range_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse(r'value: "\U11000000"')
    asserts.true(env, yaml.has_errors(doc), "Out-of-range unicode codepoint should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_unicode_out_of_range_error_test = unittest.make(_unicode_out_of_range_error_test_impl)

def _invalid_numeric_separator_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: 1__2")

    # Invalid numeric separator should fall back to plain scalar, no parser error.
    asserts.false(env, yaml.has_errors(doc), "Invalid numeric separator should remain scalar string")
    root = yaml.get_value(doc)
    asserts.equals(env, "1__2", root["value"])

    return unittest.end(env)

_invalid_numeric_separator_error_test = unittest.make(_invalid_numeric_separator_error_test_impl)

def _invalid_merge_source_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
obj:
  <<: [1, 2]
""")
    asserts.true(env, yaml.has_errors(doc), "Invalid merge sources should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_invalid_merge_source_error_test = unittest.make(_invalid_merge_source_error_test_impl)

def _invalid_merge_scalar_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
obj:
  <<: 1
""")
    asserts.true(env, yaml.has_errors(doc), "Scalar merge source should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_invalid_merge_scalar_error_test = unittest.make(_invalid_merge_scalar_error_test_impl)

def _empty_implicit_key_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse(": value")
    asserts.true(env, yaml.has_errors(doc), "Empty implicit key should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_empty_implicit_key_error_test = unittest.make(_empty_implicit_key_error_test_impl)

def _unknown_double_quote_escape_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse(r'value: "\q"')
    asserts.true(env, yaml.has_errors(doc), "Unknown escape should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_unknown_double_quote_escape_error_test = unittest.make(_unknown_double_quote_escape_error_test_impl)

def _invalid_plain_scalar_indicator_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: @bad")
    asserts.true(env, yaml.has_errors(doc), "Reserved indicator plain scalar should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_invalid_plain_scalar_indicator_error_test = unittest.make(_invalid_plain_scalar_indicator_error_test_impl)

def _ambiguous_plain_qmark_scalar_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: ?")
    asserts.true(env, yaml.has_errors(doc), "Unquoted '?' plain scalar should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_ambiguous_plain_qmark_scalar_error_test = unittest.make(_ambiguous_plain_qmark_scalar_error_test_impl)

def _ambiguous_plain_colon_scalar_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("value: :")
    asserts.true(env, yaml.has_errors(doc), "Unquoted ':' plain scalar should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_ambiguous_plain_colon_scalar_error_test = unittest.make(_ambiguous_plain_colon_scalar_error_test_impl)

def _invalid_flow_qmark_scalar_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("items: [?]")
    asserts.true(env, yaml.has_errors(doc), "Flow plain '?' scalar should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_SYNTAX:
            found = True
    asserts.true(env, found, "Expected syntax error type")

    return unittest.end(env)

_invalid_flow_qmark_scalar_error_test = unittest.make(_invalid_flow_qmark_scalar_error_test_impl)

def _inconsistent_sequence_indentation_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
root:
  - one
   - two
""")
    asserts.true(env, yaml.has_errors(doc), "Inconsistent sequence indentation should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_INDENTATION:
            found = True
    asserts.true(env, found, "Expected indentation error type")

    return unittest.end(env)

_inconsistent_sequence_indentation_error_test = unittest.make(_inconsistent_sequence_indentation_error_test_impl)

def _inconsistent_mapping_indentation_error_test_impl(ctx):
    env = unittest.begin(ctx)

    doc = yaml.parse("""
root:
  a: 1
   b: 2
""")
    asserts.true(env, yaml.has_errors(doc), "Inconsistent mapping indentation should produce error")

    found = False
    for err in yaml.get_errors(doc):
        if err.type == yaml.ERROR_INDENTATION:
            found = True
    asserts.true(env, found, "Expected indentation error type")

    return unittest.end(env)

_inconsistent_mapping_indentation_error_test = unittest.make(_inconsistent_mapping_indentation_error_test_impl)

def yaml_error_test_suite(name):
    unittest.suite(
        name,
        _unknown_alias_error_test,
        _tab_indentation_error_test,
        _flow_mapping_syntax_error_test,
        _unterminated_flow_collection_error_test,
        _invalid_tag_value_error_test,
        _unknown_tag_handle_error_test,
        _unsupported_yaml_version_error_test,
        _directive_requires_doc_start_error_test,
        _directive_after_content_error_test,
        _duplicate_block_key_error_test,
        _duplicate_flow_key_error_test,
        _duplicate_complex_explicit_key_error_test,
        _invalid_flow_plain_scalar_error_test,
        _invalid_unicode_escape_error_test,
        _unicode_out_of_range_error_test,
        _invalid_numeric_separator_error_test,
        _invalid_merge_source_error_test,
        _invalid_merge_scalar_error_test,
        _empty_implicit_key_error_test,
        _unknown_double_quote_escape_error_test,
        _invalid_plain_scalar_indicator_error_test,
        _ambiguous_plain_qmark_scalar_error_test,
        _ambiguous_plain_colon_scalar_error_test,
        _invalid_flow_qmark_scalar_error_test,
        _inconsistent_sequence_indentation_error_test,
        _inconsistent_mapping_indentation_error_test,
    )
