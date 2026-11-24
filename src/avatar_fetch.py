"""Fetch somebody's avatar instead of asking them to export it.

The tool needs the avatar's own head, face and neck. Asking a player to find the
site's Export dialog, pick the right format and find the file afterwards is the
step nobody should have to do - and the step that made two days of this project
work on an avatar that was not even theirs.

360sona has two halves of the answer:

  * ``GET /sona/v1/gamertag/{gamertag}?client={app}`` gives the avatar on an Xbox
    account as a 1000-byte manifest, with no sign-in. It needs an app id (free;
    a read-only one is approved at once) and allows 60 lookups an hour.
  * A *model* (GLB) is not served by that API. Their docs list "3D models by
    URL" as planned; today the model comes from the renderer, in a browser,
    through ``rt.glb()``.

So the model is built by the browser the player already has: this module asks
the API for the manifest, serves one small page on 127.0.0.1, opens it, and that
page hands the manifest to 360sona's own runtime, asks it for the GLB and posts
the bytes back to the tool. The tool writes them where the rig pass expects
``MyAvatar.glb`` and the rest of the run is exactly as before. Nothing is
downloaded by hand, and no password or sign-in is involved.

Nothing here imports ``bpy``: ``tools/test_avatar_fetch.py`` drives the lookup
against a stand-in server and the page against a real local POST.
"""

import argparse
import http.server
import json
import os
import socket
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

API = "https://360sona.com/sona/v1"
RUNTIME = "https://360sona.com/sona-runtime.js"

# What the page is served as, and what it posts the model to. The page is on
# 127.0.0.1, so it can talk to this server without a CORS exception, and the
# model never goes through the player's Downloads folder.
SAVE_PATH = "/save"

# How long the player has to let the page finish before the tool gives up. The
# runtime builds the avatar and the model in the page; a slow machine takes a
# few seconds, and a person who has wandered off should not hang the run.
WAIT_SECONDS = 300


class AvatarLookupError(Exception):
    """A lookup that cannot be completed, with what to do about it."""


def app_id(explicit=None):
    """The 360sona app id: the argument, the environment, or ``appid.txt``.

    One id belongs to the tool, not to each player: it is what the lookup route
    asks for so that an app cannot be used anonymously. A read-only app id is
    approved at once at https://360sona.com/devapp.html, and the id itself is
    not a secret - it travels in every lookup URL.
    """
    for value in (explicit, os.environ.get("SONA_APP_ID")):
        if value:
            return value.strip()
    beside = os.path.join(os.path.dirname(os.path.abspath(__file__)), "appid.txt")
    for path in (beside, os.path.join(os.getcwd(), "appid.txt")):
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as handle:
                found = handle.read().strip()
            if found:
                return found
    return None


def lookup_url(gamertag, app):
    """The URL that answers with that avatar's manifest."""
    tag = urllib.parse.quote(gamertag.strip(), safe="")
    return "%s/gamertag/%s?client=%s&missing=empty" % (
        API, tag, urllib.parse.quote(app or "", safe=""))


def _http_get(url, timeout=20):
    """(status, body) for a GET, without raising on an error status."""
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as answer:
            return answer.getcode(), answer.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def lookup(gamertag, app=None, fetch=None, timeout=20):
    """The avatar on that Xbox account, as its base64 manifest.

    ``fetch`` is the ``url -> (status, body)`` call, so the parsing and the
    error text can be tested without the network. Anything the API says is
    passed on: its errors carry ``error`` (written for people) and ``fix``.
    """
    tag = (gamertag or "").strip()
    if not tag:
        raise AvatarLookupError("no gamertag was given")
    if len(tag) > 21:
        raise AvatarLookupError("%r is too long for a gamertag (21 characters at most)" % tag)
    app = app or app_id()
    if not app:
        raise AvatarLookupError(
            "no 360sona app id. Get a free one at https://360sona.com/devapp.html "
            "and put it in appid.txt beside the tool (or set SONA_APP_ID).")
    status, body = (fetch or (lambda url: _http_get(url, timeout=timeout)))(
        lookup_url(tag, app))
    try:
        answer = json.loads(body.decode("utf-8") or "{}")
    except (UnicodeDecodeError, ValueError):
        raise AvatarLookupError("the lookup answered %s with something that is not JSON" % status)
    manifest = answer.get("manifest")
    if status == 200 and manifest:
        return manifest
    why = answer.get("error") or ("the lookup answered %s" % status)
    fix = answer.get("fix")
    raise AvatarLookupError("%s%s" % (why, (" - " + fix) if fix else ""))


def helper_html(manifest, save_path=SAVE_PATH, runtime=RUNTIME):
    """The page that turns a manifest into a GLB using 360sona's own runtime.

    It is served from 127.0.0.1, which is an origin the runtime accepts, so the
    page can load it and talk to the tool. The model is posted back rather than
    downloaded, because a browser cannot write into the tool's folder and a file
    left in Downloads is exactly the hunt this is meant to remove.
    """
    return r"""<!doctype html>
<html><head><meta charset="utf-8"><title>Getting your avatar</title>
<style>
 body{font:16px system-ui,sans-serif;margin:2rem;color:#222}
 #log{white-space:pre-wrap;background:#f4f4f4;padding:1rem;border-radius:6px}
</style></head>
<body>
<h2>Getting your avatar</h2>
<div id="avatar" style="width:320px;height:480px"></div>
<pre id="log">starting...</pre>
<script src="%(runtime)s"></script>
<script>
const MANIFEST = "%(manifest)s";
const log = message => { document.getElementById('log').textContent = message; };
// rt.glb() has been seen to answer with the model itself, a Blob, an
// ArrayBuffer, a data: URL and a bare base64 string. Take whichever it is.
async function asModel(value) {
  if (value instanceof Blob) return value;
  if (value instanceof ArrayBuffer) return new Blob([value], {type: 'model/gltf-binary'});
  if (ArrayBuffer.isView(value)) return new Blob([value.buffer], {type: 'model/gltf-binary'});
  if (typeof value === 'string') {
    if (/^(data:|blob:|https?:)/.test(value)) return await (await fetch(value)).blob();
    const binary = atob(value.replace(/\s/g, ''));
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new Blob([bytes], {type: 'model/gltf-binary'});
  }
  throw new Error('the runtime gave ' + Object.prototype.toString.call(value));
}
(async () => {
  try {
    log('opening the 360sona renderer...');
    const rt = new SonaRuntime(document.getElementById('avatar'));
    await rt.ready;
    log('loading the avatar...');
    await rt.avatar(MANIFEST);
    log('building the 3D model...');
    const answer = await rt.glb();
    const blob = await asModel((answer && answer.glb !== undefined) ? answer.glb : answer);
    const head = await blob.slice(0, 4).text();
    if (head !== 'glTF') {
      const bytes = new Uint8Array(await blob.slice(0, 8).arrayBuffer());
      throw new Error('the runtime gave ' + blob.size + ' bytes that are not a .glb (starts '
        + Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join(' ') + ')');
    }
    log('sending ' + blob.size + ' bytes to the tool...');
    const posted = await fetch('%(save)s', {method: 'POST', body: blob});
    log(posted.ok
      ? 'Done - close this tab and go back to the tool.'
      : 'The tool did not take the model: ' + await posted.text());
  } catch (error) {
    log('Failed: ' + (error && error.message ? error.message : error));
  }
})();
</script>
</body></html>
""" % {"runtime": runtime, "manifest": manifest, "save": save_path}


class _Handler(http.server.BaseHTTPRequestHandler):
    """Serves the page once, takes the model once, then lets the run go on."""

    page = b""
    saved = None
    written = None

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path not in ("/", "/index.html"):
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(self.page)))
        self.end_headers()
        self.wfile.write(self.page)

    def read_model(self):
        """The request body, whether it came measured or chunked.

        A browser posts a Blob with a Content-Length, but a proxy in front of
        the page may stream it chunked instead. Reading only the measured case
        silently produced an empty body, which looked like a bad model.
        """
        if (self.headers.get("Transfer-Encoding") or "").lower().strip() == "chunked":
            parts = []
            while True:
                line = self.rfile.readline().strip()
                if not line:
                    break
                size = int(line.split(b";")[0], 16)
                if size == 0:
                    self.rfile.readline()
                    break
                parts.append(self.rfile.read(size))
                self.rfile.read(2)
            return b"".join(parts)
        size = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(size) if size else b""

    def do_POST(self):
        if self.path != SAVE_PATH:
            self.send_error(404)
            return
        body = self.read_model()
        if not body.startswith(b"glTF"):
            # Say what arrived, so a change in the runtime's answer can be seen
            # from the page instead of guessed at.
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"not a .glb: " + body[:8].hex().encode("ascii"))
            return
        handler = type(self)
        # Write beside the destination and rename, so a half-arrived model is
        # never picked up as the avatar.
        part = handler.saved + ".part"
        with open(part, "wb") as handle:
            handle.write(body)
        os.replace(part, handler.saved)
        handler.written = len(body)
        self.send_response(204)
        self.end_headers()
        handler.done.set()


def serve(manifest, saved, port=0, seconds=WAIT_SECONDS, opener=None, runtime=RUNTIME):
    """Serve the page, open it, and wait for the model. Returns the byte count.

    ``opener`` is ``webbrowser.open`` by default and is passed the page's URL;
    a test hands in its own so nothing opens a window.
    """
    handler = type("PageHandler", (_Handler,), {
        "page": helper_html(manifest, runtime=runtime).encode("utf-8"),
        "saved": saved,
        "written": None,
        "done": threading.Event(),
    })
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    server.daemon_threads = True
    where = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        shown = (opener or webbrowser.open)("http://127.0.0.1:%d/" % where)
        if not handler.done.wait(seconds):
            # ``False`` means the machine has no browser to open: then the page
            # is still there, and saying where is the only way forward.
            hint = (" - open http://127.0.0.1:%d/ in a browser yourself" % where
                    if shown is False else "")
            raise AvatarLookupError(
                "the page did not send a model within %d seconds%s" % (seconds, hint))
        return handler.written
    finally:
        server.shutdown()
        server.server_close()


def fetch_avatar(gamertag, saved, app=None, port=0, seconds=WAIT_SECONDS,
                 opener=None, fetch=None):
    """Look the avatar up and take the model off the page. Returns (manifest, bytes)."""
    manifest = lookup(gamertag, app=app, fetch=fetch)
    size = serve(manifest, saved, port=port, seconds=seconds, opener=opener)
    return manifest, size


def main(argv=None):
    parser = argparse.ArgumentParser(description=(
        "Get an Xbox avatar's 3D model without the site's Export dialog."))
    parser.add_argument("--gamertag", required=True, help="the Xbox account's gamertag")
    parser.add_argument("--out", default="MyAvatar.glb", help="where to write the model")
    parser.add_argument("--app", default=None, help="360sona app id (or appid.txt / SONA_APP_ID)")
    parser.add_argument("--port", type=int, default=0, help="port to serve the page on")
    parser.add_argument("--seconds", type=int, default=WAIT_SECONDS,
                        help="how long to wait for the browser")
    parser.add_argument("--html", default=None,
                        help="only write the page here, for checking it")
    options = parser.parse_args(argv)
    if options.html:
        manifest = lookup(options.gamertag, app=options.app)
        with open(options.html, "w", encoding="utf-8") as handle:
            handle.write(helper_html(manifest))
        print("wrote %s" % options.html)
        return 0
    manifest, size = fetch_avatar(options.gamertag, os.path.abspath(options.out),
                                  app=options.app, port=options.port,
                                  seconds=options.seconds)
    print("wrote %s: %d bytes from a %d-character manifest"
          % (options.out, size, len(manifest)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
