"""Argument-validation tests for backend.py. No Hyprland needed: hyprctl is mocked."""
import importlib.util, io, os, sys, unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("backend", os.path.join(HERE, "..", "backend.py"))
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

A, B = "0xaaaa", "0xbbbb"


def client(addr, ws=1, **kw):
    c = {"address": addr, "workspace": {"id": ws}, "floating": False, "fullscreen": 0,
         "grouped": [], "at": [0, 0], "size": [100, 100]}
    c.update(kw)
    return c


class PlaceValidation(unittest.TestCase):
    def setUp(self):
        p = mock.patch.object(backend, "query", side_effect=AssertionError("query must not run"))
        self.query = p.start(); self.addCleanup(p.stop)
        e = mock.patch.object(backend, "evaluate", side_effect=AssertionError("evaluate must not run"))
        self.evaluate = e.start(); self.addCleanup(e.stop)

    def test_rejects_bad_addresses(self):
        for a, b in [("abc", B), (A, "0xzz"), ("0x", B), (A + ";rm", B), ("", B)]:
            with self.assertRaises(ValueError):
                backend.place(a, b, "l")

    def test_rejects_same_window(self):
        with self.assertRaises(ValueError):
            backend.place(A, A, "l")

    def test_rejects_bad_direction(self):
        for d in ["", "left", "u", "L", "l;"]:
            with self.assertRaises(ValueError):
                backend.place(A, B, d)


class PlaceLookups(unittest.TestCase):
    def test_unknown_window(self):
        with mock.patch.object(backend, "query", return_value=[client(A)]):
            with self.assertRaises(ValueError):
                backend.place(A, B, "r")

    def test_invalid_destination_workspace(self):
        with mock.patch.object(backend, "query", return_value=[client(A), client(B, ws=-99)]):
            with self.assertRaises(ValueError):
                backend.place(A, B, "r")

    def test_floating_target_falls_back(self):
        clients = [client(A, ws=1), client(B, ws=2, floating=True)]
        calls = []
        def fake_query(name):
            return [dict(c) for c in clients] if name == "clients" else []
        def fake_eval(code):
            calls.append(code)
            clients[0]["workspace"] = {"id": 2}
        with mock.patch.object(backend, "query", side_effect=fake_query), \
             mock.patch.object(backend, "evaluate", side_effect=fake_eval):
            self.assertEqual(backend.place(A, B, "l"), {"result": "fallback", "reason": "floating"})
        self.assertEqual(len(calls), 1)
        self.assertIn('address:' + A, calls[0])


class Main(unittest.TestCase):
    def test_usage(self):
        for argv in (["backend.py"], ["backend.py", "place", A, B], ["backend.py", "nope", A, B, "l"]):
            with mock.patch.object(sys, "argv", argv), self.assertRaises(ValueError):
                backend.main()


class WorkspaceMode(unittest.TestCase):
    def test_reads_last_mode(self):
        import tempfile, pathlib
        with tempfile.TemporaryDirectory() as d:
            base = pathlib.Path(d) / "omarchy/workspace-layouts"; base.mkdir(parents=True)
            (base / "3.lua").write_text('mode = "scrolling"\n')
            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": d}):
                self.assertEqual(backend.workspace_mode(3, []), "scrolling")
                self.assertEqual(backend.workspace_mode(4, [{"id": 4, "tiledLayout": "floating"}]), "floating")
                self.assertEqual(backend.workspace_mode(9, []), "dwindle")


if __name__ == "__main__":
    unittest.main()
