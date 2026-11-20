#!/usr/bin/env python3
"""Advanced Paste helper: detect clipboard content and convert text between
formats. Offline-first, standard library only.

Two optional modules are used when present (never required):
  - pygments: better code-language detection
  - html2text: higher-quality HTML -> Markdown conversion

Usage (text is read from stdin):
  advanced_paste.py detect
  advanced_paste.py convert <transform>
  advanced_paste.py ai-clean        # strip code fences from an AI answer

Transforms: plain, markdown, json_pretty, json_escape, codeblock,
            shell_escape, upper, lower, title,
            color_hex, color_rgb, color_css, color_hsl, color_flutter
"""

import html
import json
import re
import sys

try:
    import shlex
except ImportError:  # pragma: no cover - shlex is always present
    shlex = None


URL_RE = re.compile(r"^https?://[^\s]+$", re.IGNORECASE)
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
HTML_TAG_RE = re.compile(r"<\s*/?\s*[A-Za-z][A-Za-z0-9]*(\s[^>]*)?>")
KEYVALUE_RE = re.compile(r"^\s*[A-Za-z_][\w.\-]*\s*[=:]\s*")
FENCE_RE = re.compile(r"^\s*```[^\n]*\n?(.*?)\n?```\s*$", re.DOTALL)

# Ordered by how "specific" a detection is; used to pick the primary type.
PRIORITY = ["color", "json", "json_string", "url", "email", "html", "csv", "keyvalue", "code", "markdown", "text"]

HEX_SHORT_RE = re.compile(r"^#([0-9a-fA-F]{3,4})$")
HEX_LONG_RE = re.compile(r"^#([0-9a-fA-F]{6,8})$")
RGB_RE = re.compile(r"^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$", re.I)
HSL_RE = re.compile(r"^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$", re.I)


def _clean_fence(text):
    """Remove a single wrapping markdown code fence if present."""
    match = FENCE_RE.match(text.strip())
    return match.group(1) if match else text


def _guess_language(text):
    """Return a short language name for a code snippet, or None."""
    stripped = text.strip()
    lowered = stripped.lower()

    try:  # optional, higher quality
        from pygments.lexers import guess_lexer
        name = guess_lexer(stripped).name.lower()
        for token, lang in (
            ("python", "python"), ("javascript", "javascript"), ("typescript", "javascript"),
            ("bash", "bash"), ("shell", "bash"), ("sql", "sql"), ("html", "html"),
            ("css", "css"), ("yaml", "yaml"), ("rust", "rust"), ("go", "go"),
            ("c++", "cpp"), ("java", "java"), ("json", "json"), ("xml", "xml"),
            ("markdown", "markdown"),
        ):
            if token in name:
                return lang
    except Exception:
        pass

    # Lightweight keyword heuristics (also the offline fallback).
    if re.search(r"^\s*def\s+\w+\s*\(|^\s*import\s+\w|__name__|\bself\b", stripped, re.M):
        return "python"
    if re.search(r"\b(const|let|var)\s+\w|=>|console\.log|function\s*\w*\s*\(", stripped):
        return "javascript"
    if re.search(r"#include\s*<|int\s+main\s*\(", stripped):
        return "cpp"
    if re.search(r"\bfn\s+main\s*\(|let\s+mut\b|use\s+std::", stripped):
        return "rust"
    if re.search(r"^\s*package\s+main\b|^\s*func\s+\w+\s*\(", stripped, re.M):
        return "go"
    if re.search(r"^\s*(SELECT|INSERT|UPDATE|DELETE|CREATE)\b", stripped, re.I | re.M):
        return "sql"
    if re.search(r"^#!/(bin/)?(ba|z|k)?sh\b|\bsudo\b|\becho\s+", stripped, re.M):
        return "bash"
    if re.search(r"^\s*[\w.\-]+\s*:\s*\S", stripped, re.M) and stripped.count(":") >= 2:
        return "yaml"
    if re.search(r"[.#]?[\w\-]+\s*\{[^}]*:", stripped):
        return "css"
    return None


def _looks_like_code(text):
    stripped = text.strip()
    if "\n" in stripped and re.search(r"[{};]", stripped):
        return True
    if FENCE_RE.match(stripped):
        return True
    return _guess_language(stripped) is not None


def _parse_color(text):
    """Return (r, g, b, a) with 0-255 channels and 0.0-1.0 alpha, or None."""
    value = text.strip()
    short = HEX_SHORT_RE.match(value)
    if short:
        digits = short.group(1)
        if len(digits) == 3:
            r, g, b = (int(c * 2, 16) for c in digits)
            return r, g, b, 1.0
        r, g, b, a = (int(c * 2, 16) for c in digits)
        return r, g, b, round(a / 255, 4)
    long_hex = HEX_LONG_RE.match(value)
    if long_hex:
        digits = long_hex.group(1)
        r, g, b = (int(digits[i:i + 2], 16) for i in (0, 2, 4))
        a = int(digits[6:8], 16) / 255 if len(digits) == 8 else 1.0
        return r, g, b, round(a, 4)
    rgb = RGB_RE.match(value)
    if rgb:
        r, g, b = (int(float(rgb.group(i))) for i in (1, 2, 3))
        a = float(rgb.group(4)) if rgb.group(4) is not None else 1.0
        if a > 1:
            a /= 255
        return r, g, b, round(a, 4)
    hsl = HSL_RE.match(value)
    if hsl:
        h, s, light = float(hsl.group(1)), float(hsl.group(2)), float(hsl.group(3))
        r, g, b = _hsl_to_rgb(h, s, light)
        a = float(hsl.group(4)) if hsl.group(4) is not None else 1.0
        if a > 1:
            a /= 100
        return r, g, b, round(a, 4)
    return None


def _hsl_to_rgb(hue, saturation, lightness):
    hue = hue % 360 / 360
    saturation /= 100
    lightness /= 100
    if saturation == 0:
        value = round(lightness * 255)
        return value, value, value

    def hue_to_rgb(p, q, t):
        if t < 0:
            t += 1
        if t > 1:
            t -= 1
        if t < 1 / 6:
            return p + (q - p) * 6 * t
        if t < 1 / 2:
            return q
        if t < 2 / 3:
            return p + (q - p) * (2 / 3 - t) * 6
        return p

    q = lightness * (1 + saturation) if lightness < 0.5 else lightness + saturation - lightness * saturation
    p = 2 * lightness - q
    return (
        round(hue_to_rgb(p, q, hue + 1 / 3) * 255),
        round(hue_to_rgb(p, q, hue) * 255),
        round(hue_to_rgb(p, q, hue - 1 / 3) * 255),
    )


def _rgb_to_hsl(red, green, blue):
    r, g, b = red / 255, green / 255, blue / 255
    maximum, minimum = max(r, g, b), min(r, g, b)
    delta = maximum - minimum
    lightness = (maximum + minimum) / 2
    if delta == 0:
        return 0, 0, round(lightness * 100)
    saturation = delta / (1 - abs(2 * lightness - 1))
    if maximum == r:
        hue = ((g - b) / delta) % 6
    elif maximum == g:
        hue = (b - r) / delta + 2
    else:
        hue = (r - g) / delta + 4
    return round(hue * 60), round(saturation * 100), round(lightness * 100)


def detect(text):
    """Return a JSON-serialisable dict describing the clipboard content."""
    result = {"primary": "text", "candidates": [], "language": None, "length": len(text)}
    stripped = _clean_fence(text).strip()
    if not stripped:
        return result

    candidates = result["candidates"]

    try:
        json.loads(stripped)
        candidates.append("json")
    except Exception:
        pass

    if len(stripped) >= 2 and stripped[0] in "\"'" and stripped[-1] == stripped[0]:
        try:
            if isinstance(json.loads(stripped), str):
                candidates.append("json_string")
        except Exception:
            pass

    if _parse_color(stripped) is not None:
        candidates.append("color")
    if URL_RE.match(stripped):
        candidates.append("url")
    if EMAIL_RE.match(stripped):
        candidates.append("email")
    if HTML_TAG_RE.search(stripped):
        candidates.append("html")

    lines = [line for line in stripped.splitlines() if line.strip()]
    if len(lines) >= 2:
        for delim in (",", "\t", ";", "|"):
            counts = [line.count(delim) for line in lines]
            if counts[0] > 0 and all(count == counts[0] for count in counts):
                candidates.append("csv")
                break

    if lines and all(KEYVALUE_RE.match(line) for line in lines):
        candidates.append("keyvalue")

    md_signals = (
        re.search(r"^\s*#{1,6}\s+\S", stripped, re.M),
        re.search(r"\*\*[^*]+\*\*|__[^_]+__", stripped),
        re.search(r"\[[^\]]+\]\([^)]+\)", stripped),
        re.search(r"^\s*[-*+]\s+\S", stripped, re.M),
        re.search(r"^\s*```", stripped, re.M),
        re.search(r"^\s*>\s+\S", stripped, re.M),
    )
    if any(md_signals):
        candidates.append("markdown")

    if _looks_like_code(stripped):
        candidates.append("code")
        result["language"] = _guess_language(stripped)

    for kind in PRIORITY:
        if kind in candidates:
            result["primary"] = kind
            break
    if result["primary"] == "code" and not result["language"]:
        result["language"] = "text"

    return result


def _html_to_markdown(text):
    """Minimal, dependency-free HTML -> Markdown conversion."""
    try:
        import html2text
        converter = html2text.HTML2Text()
        converter.body_width = 0
        return converter.handle(text).strip()
    except Exception:
        pass

    value = text
    value = re.sub(r"(?is)<\s*(script|style)\b.*?<\s*/\s*\1\s*>", "", value)
    value = re.sub(r"(?i)<\s*br\s*/?\s*>", "\n", value)
    value = re.sub(r"(?is)<\s*pre\b[^>]*>(.*?)<\s*/\s*pre\s*>",
                   lambda m: "```\n" + html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip() + "\n```", value)
    for level in range(1, 7):
        value = re.sub(r"(?is)<\s*h%d\b[^>]*>(.*?)<\s*/\s*h%d\s*>" % (level, level),
                       lambda m: "\n" + "#" * level + " " + html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip() + "\n", value)
    value = re.sub(r"(?is)<\s*(strong|b)\b[^>]*>(.*?)<\s*/\s*\1\s*>",
                   lambda m: "**" + m.group(2).strip() + "**", value)
    value = re.sub(r"(?is)<\s*(em|i)\b[^>]*>(.*?)<\s*/\s*\1\s*>",
                   lambda m: "*" + m.group(2).strip() + "*", value)
    value = re.sub(r"(?is)<\s*code\b[^>]*>(.*?)<\s*/\s*code\s*>",
                   lambda m: "`" + html.unescape(m.group(1)) + "`", value)
    value = re.sub(r"(?is)<\s*a\b[^>]*href\s*=\s*['\"]([^'\"]+)['\"][^>]*>(.*?)<\s*/\s*a\s*>",
                   lambda m: "[%s](%s)" % (re.sub(r"<[^>]+>", "", m.group(2)).strip(), m.group(1)), value)
    value = re.sub(r"(?is)<\s*li\b[^>]*>(.*?)<\s*/\s*li\s*>", lambda m: "\n- " + m.group(1).strip(), value)
    value = re.sub(r"(?is)<\s*p\b[^>]*>(.*?)<\s*/\s*p\s*>", lambda m: "\n\n" + m.group(1).strip() + "\n", value)
    value = re.sub(r"<[^>]+>", "", value)
    value = html.unescape(value)
    value = re.sub(r"[ \t]+\n", "\n", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def _markdown_to_plain(text):
    value = _clean_fence(text)
    value = re.sub(r"(?m)^\s*#{1,6}\s*", "", value)
    value = re.sub(r"\*\*([^*]+)\*\*|__([^_]+)__", lambda m: m.group(1) or m.group(2), value)
    value = re.sub(r"(?<!\w)\*([^*]+)\*(?!\w)|(?<!\w)_([^_]+)_(?!\w)", lambda m: m.group(1) or m.group(2), value)
    value = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", value)
    value = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", value)
    value = re.sub(r"(?m)^\s*>\s?", "", value)
    value = re.sub(r"(?m)^\s*[-*+]\s+", "", value)
    value = re.sub(r"`([^`]+)`", r"\1", value)
    return value.strip()


def convert(text, transform):
    """Apply a transform to text and return the output string."""
    if transform.startswith("color_"):
        color = _parse_color(text)
        if color is None:
            raise ValueError("not a recognizable color: %s" % text)
        r, g, b, a = color
        if transform == "color_hex":
            result = "#%02X%02X%02X" % (r, g, b)
            return result + "%02X" % round(a * 255) if a < 1 else result
        if transform == "color_rgb":
            return "rgb(%d, %d, %d)" % (r, g, b)
        if transform == "color_css":
            return "rgba(%d, %d, %d, %s)" % (r, g, b, ("%.2f" % a).rstrip("0").rstrip("."))
        if transform == "color_hsl":
            h, s, light = _rgb_to_hsl(r, g, b)
            return "hsl(%d, %d%%, %d%%)" % (h, s, light)
        if transform == "color_flutter":
            alpha = round(a * 255)
            return "Color(0x%02X%02X%02X%02X)" % (alpha, r, g, b)
        raise ValueError("unknown color transform: %s" % transform)

    if transform == "plain":
        info = detect(text)
        if "html" in info["candidates"] or "html" == info["primary"]:
            return _markdown_to_plain(_html_to_markdown(text))
        return _markdown_to_plain(text)

    if transform == "markdown":
        info = detect(text)
        if "html" in info["candidates"] or "html" == info["primary"]:
            return _html_to_markdown(text)
        return text.strip()

    if transform == "json_pretty":
        cleaned = _clean_fence(text).strip()
        return json.dumps(json.loads(cleaned), indent=2, ensure_ascii=False)

    if transform == "json_escape":
        return json.dumps(text, ensure_ascii=False)

    if transform == "codeblock":
        info = detect(text)
        language = info.get("language") or ""
        if info.get("primary") == "json":
            language = "json"
        elif info.get("primary") == "html":
            language = "html"
        return "```%s\n%s\n```" % (language, text.strip("\n"))

    if transform == "shell_escape":
        if shlex is not None:
            return shlex.quote(text)
        return "'" + text.replace("'", "'\\''") + "'"

    if transform == "upper":
        return text.upper()
    if transform == "lower":
        return text.lower()
    if transform == "title":
        return text.title()

    raise ValueError("unknown transform: %s" % transform)


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2

    command = argv[1]
    text = sys.stdin.read()

    try:
        if command == "detect":
            sys.stdout.write(json.dumps(detect(text), ensure_ascii=False))
        elif command == "convert":
            if len(argv) < 3:
                sys.stderr.write("convert requires a transform name\n")
                return 2
            sys.stdout.write(convert(text, argv[2]))
        elif command == "ai-clean":
            sys.stdout.write(_clean_fence(text).strip())
        else:
            sys.stderr.write("unknown command: %s\n" % command)
            return 2
    except Exception as exc:
        sys.stderr.write("advanced_paste: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
