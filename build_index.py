#!/usr/bin/env python3
import glob
import os

pages = sorted(glob.glob("*.html"))
pages = [p for p in pages if p != "index.html"]

items = "\n".join(f'    <a href="{p}">{os.path.splitext(p)[0]}</a><br>' for p in pages)

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Tools</title>
  <style>
    body {{ font-family: sans-serif; max-width: 600px; margin: 2em auto; }}
    a {{ display: block; margin: 0; }}
  </style>
</head>
<body>
  <h1>Tools</h1>
{items}
</body>
</html>
"""

with open("index.html", "w") as f:
    f.write(html)

print(f"Generated index.html with {len(pages)} pages.")
