#!/usr/bin/env python3
"""Offline unit tests for scripts/clipboard/advanced_paste.py.

No network, clipboard, Wayland session or external Python modules required.
Run with:  python3 -m unittest discover -s tests -p 'test_advanced_paste.py'
"""

import importlib.util
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKEND = os.path.join(REPO, "scripts", "clipboard", "advanced_paste.py")

spec = importlib.util.spec_from_file_location("advanced_paste", BACKEND)
ap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ap)


class DetectTests(unittest.TestCase):
    def test_json(self):
        result = ap.detect('{"a": 1, "b": [2, 3]}')
        self.assertEqual(result["primary"], "json")
        self.assertIn("json", result["candidates"])

    def test_json_string(self):
        result = ap.detect('"a \\"quoted\\" string"')
        self.assertIn("json_string", result["candidates"])

    def test_url(self):
        self.assertEqual(ap.detect("https://example.com/path?q=1")["primary"], "url")

    def test_email(self):
        self.assertEqual(ap.detect("someone@example.com")["primary"], "email")

    def test_html(self):
        self.assertEqual(ap.detect("<h1>Hi</h1><p>there</p>")["primary"], "html")

    def test_csv(self):
        result = ap.detect("a,b,c\n1,2,3\n4,5,6")
        self.assertEqual(result["primary"], "csv")

    def test_keyvalue(self):
        result = ap.detect("KEY=value\nOTHER=thing")
        self.assertEqual(result["primary"], "keyvalue")

    def test_markdown(self):
        result = ap.detect("# Title\n\nSome **bold** text")
        self.assertEqual(result["primary"], "markdown")

    def test_python_code(self):
        result = ap.detect("def hello(name):\n    print(name)\n    return True")
        self.assertEqual(result["primary"], "code")
        self.assertEqual(result["language"], "python")

    def test_plain_text(self):
        self.assertEqual(ap.detect("just some ordinary words")["primary"], "text")

    def test_empty(self):
        self.assertEqual(ap.detect("   ")["primary"], "text")

    def test_color(self):
        for value in ("#f00", "#ff0000", "rgb(255, 0, 0)", "hsl(0, 100%, 50%)"):
            with self.subTest(value=value):
                self.assertEqual(ap.detect(value)["primary"], "color")


class ConvertTests(unittest.TestCase):
    def test_plain_strips_markdown(self):
        self.assertEqual(ap.convert("# Title\n\n**bold** text", "plain"), "Title\n\nbold text")

    def test_plain_strips_html(self):
        self.assertEqual(ap.convert("<p>Hello <b>world</b></p>", "plain"), "Hello world")

    def test_markdown_from_html(self):
        output = ap.convert("<h1>Title</h1><p>Hello <strong>world</strong></p>", "markdown")
        self.assertIn("# Title", output)
        self.assertIn("**world**", output)

    def test_json_pretty(self):
        self.assertEqual(ap.convert('{"a":1}', "json_pretty"), '{\n  "a": 1\n}')

    def test_json_escape(self):
        self.assertEqual(ap.convert('hello "world"', "json_escape"), '"hello \\"world\\""')

    def test_codeblock_language(self):
        output = ap.convert("def f():\n    return 1", "codeblock")
        self.assertTrue(output.startswith("```python\n"))
        self.assertTrue(output.endswith("\n```"))

    def test_codeblock_json(self):
        output = ap.convert('{"a":1}', "codeblock")
        self.assertTrue(output.startswith("```json\n"))

    def test_shell_escape(self):
        self.assertEqual(ap.convert("hello world's", "shell_escape"), "'hello world'\"'\"'s'")

    def test_case_transforms(self):
        self.assertEqual(ap.convert("hello world", "upper"), "HELLO WORLD")
        self.assertEqual(ap.convert("HELLO WORLD", "lower"), "hello world")
        self.assertEqual(ap.convert("hello world", "title"), "Hello World")

    def test_ai_clean(self):
        self.assertEqual(ap._clean_fence("```json\n{\"a\":1}\n```"), '{"a":1}')

    def test_color_transforms(self):
        self.assertEqual(ap.convert("#ff0000", "color_hex"), "#FF0000")
        self.assertEqual(ap.convert("#f00", "color_rgb"), "rgb(255, 0, 0)")
        self.assertEqual(ap.convert("rgb(255, 0, 0)", "color_hsl"), "hsl(0, 100%, 50%)")
        self.assertEqual(ap.convert("#ff000080", "color_flutter"), "Color(0x80FF0000)")
        self.assertEqual(ap.convert("#ff0000", "color_css"), "rgba(255, 0, 0, 1)")
        self.assertEqual(ap.convert("hsl(240, 100%, 50%)", "color_hex"), "#0000FF")


if __name__ == "__main__":
    unittest.main()
