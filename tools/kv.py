"""Minimal Valve KeyValues parser (for reading reference data during research)."""
import re

TOK = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])|(//[^\n]*)|([^\s{}"]+)')


def parse(text):
    stack = [{}]
    key = None
    for m in TOK.finditer(text):
        s, br, com, bare = m.groups()
        if com is not None:
            continue
        if br == "{":
            d = {}
            stack[-1][key] = d
            stack.append(d)
            key = None
        elif br == "}":
            stack.pop()
            key = None
        else:
            v = s if s is not None else bare
            if key is None:
                key = v
            else:
                stack[-1][key] = v
                key = None
    return stack[0]
