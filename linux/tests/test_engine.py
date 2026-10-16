import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from wordblocker.engine import Engine


def typed(eng, text):
    for i in range(1, len(text) + 1):
        h = eng.match(text[:i])
        if h:
            return h
    return None


E = Engine(["bad", "secret", "forbidden", "bad word"], ["badger", "badge", "password"], {"secret": "Stay focused!"})

def test_exact():            assert typed(E, "this is bad ")[0] == "bad"
def test_delete_count():     assert typed(E, "so bad ")[1] == 4  # word + trailing space
def test_leet():             assert typed(E, "b4d ")[0] == "bad"
def test_elongation():       assert typed(E, "b444aad ")[1] == 8
def test_punct_noise():      assert typed(E, "b.a.d ") is not None
def test_homoglyph():        assert typed(E, "bаd ") is not None  # Cyrillic а
def test_transposition():    assert typed(E, "sceret ")[0] == "secret"
def test_long_typo():        assert typed(E, "forbiden ")[0] == "forbidden"
def test_note():             assert typed(E, "secret")[2] == "Stay focused!"
def test_exception_badger(): assert typed(E, "badger ") is None
def test_exception_badge():  assert typed(E, "badge ") is None
def test_clean_text():       assert typed(E, "hello world, nice day ") is None
def test_short_no_fuzzy():   assert typed(E, "bed ") is None

E2 = Engine(["hate"])
def test_immediate_delete(): assert typed(E2, "i hate")[1] == 4
