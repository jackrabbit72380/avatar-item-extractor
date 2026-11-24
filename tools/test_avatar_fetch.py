#!/usr/bin/env python3
"""Checks for src/avatar_fetch.py, the pass that gets the avatar for the player.

Three things are worth testing without the internet and without a person:
the lookup's URL and its reading of the API's answers, the page it serves, and
the local round trip that carries the model back into the tool.
"""

import json
import os
import socket
import sys
import tempfile
import threading
import unittest
import urllib.request
from urllib.parse import unquote

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import avatar_fetch


def answer(status, payload):
    body = json.dumps(payload).encode("utf-8") if isinstance(payload, dict) else payload
    return lambda url: (status, body)


class TheLookup(unittest.TestCase):
    def test_the_gamertag_is_escaped_into_the_route(self):
        url = avatar_fetch.lookup_url("Big Rabit 72", "my-app")
        self.assertEqual(
            url,
            "https://360sona.com/sona/v1/gamertag/Big%20Rabit%2072?client=my-app&missing=empty")
        self.assertEqual(unquote(url.split("/gamertag/")[1].split("?")[0]), "Big Rabit 72")

    def test_a_manifest_is_returned_as_it_came(self):
        manifest = "A" * 1000
        got = avatar_fetch.lookup("Someone", app="my-app",
                                  fetch=answer(200, {"gamertag": "Someone", "manifest": manifest}))
        self.assertEqual(got, manifest)

    def test_a_private_avatar_says_so(self):
        with self.assertRaises(avatar_fetch.AvatarLookupError) as caught:
            avatar_fetch.lookup("Someone", app="my-app", fetch=answer(
                200, {"gamertag": None, "manifest": None,
                      "error": "That account keeps its avatar private."}))
        self.assertIn("private", str(caught.exception))

    def test_the_api_fix_travels_with_the_error(self):
        with self.assertRaises(avatar_fetch.AvatarLookupError) as caught:
            avatar_fetch.lookup("nobody here!", app="my-app", fetch=answer(
                400, {"error": "That is not a gamertag.", "fix": "Letters, digits and spaces, 21 at most."}))
        self.assertIn("not a gamertag", str(caught.exception))
        self.assertIn("21 at most", str(caught.exception))

    def test_a_bad_answer_is_not_taken_for_an_avatar(self):
        with self.assertRaises(avatar_fetch.AvatarLookupError):
            avatar_fetch.lookup("Someone", app="my-app", fetch=answer(502, b"<html>bad gateway"))

    def test_without_an_app_id_it_says_where_to_get_one(self):
        saved = os.environ.pop("SONA_APP_ID", None)
        here = os.getcwd()
        empty = tempfile.mkdtemp()
        try:
            os.chdir(empty)
            with self.assertRaises(avatar_fetch.AvatarLookupError) as caught:
                avatar_fetch.lookup("Someone", app=None, fetch=answer(200, {"manifest": "x"}))
        finally:
            os.chdir(here)
            if saved is not None:
                os.environ["SONA_APP_ID"] = saved
        self.assertIn("devapp.html", str(caught.exception))

    def test_an_empty_gamertag_is_refused_before_any_request(self):
        asked = []
        with self.assertRaises(avatar_fetch.AvatarLookupError):
            avatar_fetch.lookup("   ", app="my-app", fetch=lambda url: asked.append(url))
        self.assertEqual(asked, [])


class ThePage(unittest.TestCase):
    def test_it_hands_the_manifest_to_the_runtime_and_posts_the_model_back(self):
        page = avatar_fetch.helper_html("MANIFEST-BYTES")
        self.assertIn("https://360sona.com/sona-runtime.js", page)
        self.assertIn('const MANIFEST = "MANIFEST-BYTES";', page)
        self.assertIn("new SonaRuntime(", page)
        self.assertIn("await rt.avatar(MANIFEST)", page)
        self.assertIn("await rt.glb()", page)
        self.assertIn("fetch('/save'", page)

    def test_the_model_is_posted_exactly_as_the_runtime_gave_it(self):
        # The terms ask for the credit to be kept inside exported files; the
        # runtime writes it into the GLB's asset block, so a Blob must be posted
        # untouched. The page has to decode only the other shapes rt.glb() has
        # answered with: a data: URL, a bare base64 string, an ArrayBuffer.
        page = avatar_fetch.helper_html("M")
        self.assertIn("if (value instanceof Blob) return value;", page)
        self.assertIn("if (value instanceof ArrayBuffer)", page)
        self.assertIn("if (/^(data:|blob:|https?:)/.test(value))", page)
        self.assertIn("atob(", page)

    def test_a_body_that_is_not_a_model_says_what_arrived(self):
        page = avatar_fetch.helper_html("M")
        self.assertIn("are not a .glb", page)


class TheRoundTrip(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.saved = os.path.join(self.folder, "MyAvatar.glb")

    def _page(self, body, path="/save"):
        """A stand-in for the browser: post the model to the served page."""
        def opener(url):
            def post():
                request = urllib.request.Request(
                    url.rstrip("/") + path, data=body, method="POST")
                try:
                    urllib.request.urlopen(request, timeout=10).read()
                except Exception:
                    pass
            threading.Thread(target=post, daemon=True).start()
        return opener

    def test_the_model_arrives_where_the_rig_pass_expects_it(self):
        model = b"glTF" + bytes(range(256)) * 4
        size = avatar_fetch.serve("MANIFEST", self.saved, seconds=20,
                                  opener=self._page(model))
        self.assertEqual(size, len(model))
        with open(self.saved, "rb") as handle:
            self.assertEqual(handle.read(), model)
        self.assertFalse(os.path.exists(self.saved + ".part"))

    def test_a_chunked_body_is_read_like_a_measured_one(self):
        # A proxy in front of the page streams the model chunked, without a
        # Content-Length; reading only the measured case took in nothing and
        # the tool then blamed the model.
        model = b"glTF" + b"Z" * 100

        def opener(url):
            port = int(url.split(":")[-1].strip("/"))
            pieces = b"".join(b"%x\r\n%s\r\n" % (len(piece), piece)
                             for piece in (model[:40], model[40:]))
            request = (b"POST /save HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                       b"Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                       + pieces + b"0\r\n\r\n")
            connection = socket.create_connection(("127.0.0.1", port), timeout=10)
            connection.sendall(request)
            connection.recv(4096)
            connection.close()

        size = avatar_fetch.serve("MANIFEST", self.saved, seconds=20, opener=opener)
        self.assertEqual(size, len(model))
        with open(self.saved, "rb") as handle:
            self.assertEqual(handle.read(), model)

    def test_something_that_is_not_a_model_is_refused(self):
        with self.assertRaises(avatar_fetch.AvatarLookupError):
            avatar_fetch.serve("MANIFEST", self.saved, seconds=1,
                               opener=self._page(b"<html>nope</html>"))
        self.assertFalse(os.path.exists(self.saved))

    def test_a_page_nobody_opened_says_where_to_go(self):
        def opener(url):
            self.opened = url
        got = {}
        with self.assertRaises(avatar_fetch.AvatarLookupError) as caught:
            # opener not passed as ``opener``: the run thinks it opened nothing
            avatar_fetch.serve("MANIFEST", self.saved, seconds=1)
        del got
        self.assertIn("did not send a model", str(caught.exception))

    def test_the_page_is_actually_served(self):
        seen = {}

        def opener(url):
            def get():
                with urllib.request.urlopen(url, timeout=10) as reply:
                    seen["page"] = reply.read().decode("utf-8")
                request = urllib.request.Request(
                    url.rstrip("/") + "/save", data=b"glTF1234", method="POST")
                urllib.request.urlopen(request, timeout=10).read()
            threading.Thread(target=get, daemon=True).start()

        avatar_fetch.serve("A-MANIFEST", self.saved, seconds=20, opener=opener)
        self.assertIn("A-MANIFEST", seen["page"])


class TheEndToEnd(unittest.TestCase):
    def test_a_lookup_then_a_page_gives_a_file(self):
        folder = tempfile.mkdtemp()
        saved = os.path.join(folder, "MyAvatar.glb")
        model = b"glTF" + b"\0" * 100

        def opener(url):
            def post():
                request = urllib.request.Request(
                    url.rstrip("/") + "/save", data=model, method="POST")
                urllib.request.urlopen(request, timeout=10).read()
            threading.Thread(target=post, daemon=True).start()

        manifest, size = avatar_fetch.fetch_avatar(
            "Someone", saved, app="my-app", seconds=20, opener=opener,
            fetch=answer(200, {"manifest": "M" * 1000}))
        self.assertEqual(len(manifest), 1000)
        self.assertEqual(size, len(model))
        self.assertTrue(os.path.exists(saved))


if __name__ == "__main__":
    unittest.main(verbosity=2)
