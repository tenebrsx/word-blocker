"""Matching engine: a Python port of the macOS WordBlocker engine.

Catches exact words, leetspeak, homoglyphs, punctuation noise, elongations
and (for longer words) typos/transpositions, while honoring an exceptions list.
"""
import unicodedata

LEET = {"0": "o", "1": "i", "!": "i", "|": "i", "3": "e", "€": "e", "4": "a",
        "@": "a", "^": "a", "5": "s", "$": "s", "7": "t", "+": "t", "8": "b", "9": "g"}
HOMOGLYPHS = {"а": "a", "в": "b", "е": "e", "к": "k", "м": "m", "н": "h", "о": "o",
              "р": "p", "с": "c", "т": "t", "у": "y", "х": "x", "α": "a", "ο": "o", "ρ": "p"}


def canon_char(c):
    c = c.lower()
    if c in LEET:
        return LEET[c]
    if c in HOMOGLYPHS:
        return HOMOGLYPHS[c]
    d = unicodedata.normalize("NFKD", c)
    base = "".join(ch for ch in d if not unicodedata.combining(ch))
    return base[0] if base else c


def _fold(chars, maxrun):
    out, run = [], 0
    for ch in chars:
        if out and out[-1] == ch:
            if run < maxrun:
                out.append(ch); run += 1
        else:
            out.append(ch); run = 1
    return "".join(out)


def canon_target(word):
    chars = [canon_char(c) for c in word.strip().lower()]
    return "".join(chars), _fold(chars, 1)


def tokens(raw):
    """Return (text, raw_start, raw_end) candidates for each whitespace-separated token."""
    out, cur = [], []
    def flush():
        if not cur:
            return
        start, end = cur[0][1], cur[-1][1]
        clean = [c for c, _ in cur if c.isalnum()]
        if clean:
            seen = []
            for t in ("".join(clean), _fold(clean, 1), _fold(clean, 2)):
                if t not in seen:
                    seen.append(t); out.append((t, start, end))
        cur.clear()
    for i, ch in enumerate(raw):
        c = canon_char(ch)
        if c.isspace():
            flush()
        else:
            cur.append((c, i))
    flush()
    return out


def dl_distance(a, b):
    m, n = len(a), len(b)
    if not m or not n:
        return m or n
    d = [[0] * (n + 1) for _ in range(m + 1)]
    for i in range(m + 1): d[i][0] = i
    for j in range(n + 1): d[0][j] = j
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            cost = 0 if a[i-1] == b[j-1] else 1
            v = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
            if i > 1 and j > 1 and a[i-1] == b[j-2] and a[i-2] == b[j-1]:
                v = min(v, d[i-2][j-2] + cost)
            d[i][j] = v
    return d[m][n]


def allowed_distance(n):
    return 0 if n <= 4 else (1 if n <= 7 else 2)


class Engine:
    def __init__(self, words=(), exceptions=(), notes=None, fuzzy=True):
        self.words = {w.strip().lower() for w in words if w.strip()}
        self.exceptions = {w.strip().lower() for w in exceptions if w.strip()}
        self.notes = {k.lower(): v for k, v in (notes or {}).items()}
        self.fuzzy = fuzzy

    def match(self, raw):
        """Check the typed buffer. Returns (word, chars_to_delete, note) or None."""
        if not self.words or not raw:
            return None
        lower = raw.lower()
        boundary = raw[-1].isspace() or (not raw[-1].isalnum())
        cur = lower.split()[-1] if lower.split() and not raw[-1].isspace() else ""
        if cur in self.exceptions:
            return None
        if not boundary and any(e.startswith(cur) and e != cur for e in self.exceptions):
            return None
        for w in self.words:
            if lower.endswith(w):
                if not boundary and any(e.startswith(w) and e != w for e in self.exceptions):
                    continue
                return w, len(w), self.notes.get(w)
        if not self.fuzzy:
            return None
        toks = tokens(raw)
        for w in self.words:
            tc, tcol = canon_target(w)
            for text, start, end in reversed(toks):
                if text in self.exceptions or end < len(raw) - 2:
                    continue
                if not boundary and any(e.startswith(text) and e != text for e in self.exceptions):
                    continue
                maxd = allowed_distance(len(tc))
                if text == tc or text == tcol or (maxd and dl_distance(text, tc) <= maxd):
                    return w, len(raw) - start, self.notes.get(w)
        return None
