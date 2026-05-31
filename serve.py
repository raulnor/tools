#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["livereload"]
# ///

import glob
from build_index import build_index
from livereload import Server


build_index()

server = Server()
for f in glob.glob("*.html"):
    if f != "index.html":
        server.watch(f, build_index)
server.watch("index.html")
server.watch("*.css")
server.watch("*.js")
server.serve(root=".", port=10784)
