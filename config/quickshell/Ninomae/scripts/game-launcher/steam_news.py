#!/usr/bin/env python3
"""A Steam game's official news (the developer's announcements: patch notes, updates, events), for
the game launcher's News sheet. Steam's public news API, no key; cached for an hour.

Usage: steam_news.py <app id> <cache dir>
Prints JSON: {"items": [{"id", "title", "date", "author", "url", "update", "blocks"}]}
"update" says whether it's a game update (patch notes), for the sheet's "Updates" filter: what the
developer chose as its type on Steam's events page (small/regular/major update), or for posts too
old to be listed there, its title (hotfix, patch, a version number…).
Each post's BBCode becomes a list of blocks the launcher lays out itself:
  {"type": "heading", "level": 1-3, "html"}  {"type": "text", "html"}  {"type": "image", "url"}
  {"type": "list", "items": [html]}  {"type": "video", "url"}  {"type": "rule"}
"html" is the small inline subset Qt's StyledText shows: <b> <i> <u> <s> <a href> <br>.
"""
import html
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = ("https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/"
       "?appid={app}&count=15&maxlength=0&feeds=steam_community_announcements&format=json")
EVENTS_API = ("https://store.steampowered.com/events/ajaxgetadjacentpartnerevents/"
              "?appid={app}&count_before=0&count_after=30&lang_list=0")
UPDATE_EVENT_TYPES = {12, 13, 14}  # Small, regular, major update
UPDATE_TITLE_RE = re.compile(r"\b(hotfix|patch|update|changelog)\b|\b\d+\.\d+(\.\d+)+\b", re.I)
CLAN_IMAGES = "https://clan.akamai.steamstatic.com/images"
CLAN_PLACEHOLDER_RE = re.compile(r"\{STEAM_CLAN_(?:LOC_)?IMAGE\}")
CACHE_SECONDS = 3600

# [img]url[/img] or [img src="url"][/img]
IMG = r'\[img(?:\s+src="?(?P<src>[^"\]\s]+)"?)?[^\]]*\](?P<body>.*?)\[/img\]'
# Block-level BBCode, in the order it appears in a post
BLOCK_RE = re.compile(
    r'(?P<img>' + IMG + r')'
    r'|\[previewyoutube="?(?P<yt>[^;"\]]+)[^\]]*\]\s*(?:\[/previewyoutube\])?'
    r'|\[h(?P<hl>[1-6])[^\]]*\](?P<h>.*?)\[/h(?P=hl)\]'
    r'|\[(?P<lt>list|olist)[^\]]*\](?P<list>.*?)\[/(?P=lt)\]'
    r'|\[hr\]\s*(?:\[/hr\])?',
    re.S | re.I)


def inline(text):
    """BBCode inline markup → StyledText HTML. Anything else in [brackets] is dropped."""
    text = html.escape(text.strip(), quote=False)
    subs = [
        (r'\[b\](.*?)\[/b\]', r'<b>\1</b>'),
        (r'\[i\](.*?)\[/i\]', r'<i>\1</i>'),
        (r'\[u\](.*?)\[/u\]', r'<u>\1</u>'),
        (r'\[strike\](.*?)\[/strike\]', r'<s>\1</s>'),
        (r'\[url="?([^"\]]+)"?\](.*?)\[/url\]', r'<a href="\1">\2</a>'),
        (r'\[url\](.*?)\[/url\]', r'<a href="\1">\1</a>'),
    ]
    for pattern, repl in subs:
        text = re.sub(pattern, repl, text, flags=re.S | re.I)
    text = re.sub(r'\[\*\]\s*', '• ', text)  # A point outside any list (old posts): a bullet all the same
    text = re.sub(r'\[/?[a-zA-Z][^\]]*\]', '', text)  # Unknown or unpaired tags
    text = re.sub(r'[ \t]*\n[ \t]*', '<br>', text.strip())
    return text


def plain(text):
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', html.unescape(text))).strip()


# Some posts mix in HTML: its inline formatting becomes BBCode (escaped and converted like the rest),
# line and paragraph breaks become newlines, and other tags are dropped
HTML_TO_BBCODE = [
    (r'<\s*(b|strong)\s*>', '[b]'), (r'<\s*/\s*(b|strong)\s*>', '[/b]'),
    (r'<\s*(i|em)\s*>', '[i]'), (r'<\s*/\s*(i|em)\s*>', '[/i]'),
    (r'<\s*a\s[^>]*href="([^"]+)"[^>]*>', r'[url="\1"]'), (r'<\s*/\s*a\s*>', '[/url]'),
    (r'<br\s*/?>', '\n'), (r'</?(p|div)\b[^>]*>', '\n\n'), (r'<[^>]+>', ''),
]


def paragraphs(segment):
    """Text between block tags: [p]…[/p] and blank lines separate paragraphs."""
    segment = re.sub(r'\[/?p[^\]]*\]', '\n\n', segment, flags=re.I)
    if '<' in segment:
        for pattern, repl in HTML_TO_BBCODE:
            segment = re.sub(pattern, repl, segment, flags=re.I)
    out = []
    for part in re.split(r'\n\s*\n', segment):
        rendered = inline(part)
        if plain(rendered):
            out.append({"type": "text", "html": rendered})
    return out


# An image inside a list (patch notes with a screenshot under each point): the list is split there, so the
# picture shows under its point and the list goes on after it. These used to be dropped with the list's tags
# (headings with an image in them, below, the same)
INNER_IMG_RE = re.compile(IMG, re.S | re.I)


def image_block(m):
    """An image tag's block, or None: spacer GIFs (data: URLs) and empty tags show nothing"""
    url = (m.group("src") or m.group("body") or "").strip()
    return {"type": "image", "url": url} if url.startswith("http") else None


def list_blocks(body):
    out, pos = [], 0
    def items_of(segment):
        items = [inline(i) for i in re.split(r'\[\*\]', segment)]
        items = [i for i in items if plain(i)]
        if items:
            out.append({"type": "list", "items": items})
    for m in INNER_IMG_RE.finditer(body):
        items_of(body[pos:m.start()])
        pos = m.end()
        out += filter(None, [image_block(m)])
    items_of(body[pos:])
    return out


LIST_TAG_RE = re.compile(r'\[(/?)(list|olist)\b[^\]]*\]', re.I)


def flatten_lists(contents):
    """Steam's lists: [*]item[/*], and lists inside lists. The [/*] ends are dropped (they showed as text), and
    a list inside a list keeps only the outer tags, its points joining the outer one's, so the outer list
    isn't cut short at the inner list's end (the rest of it fell out as loose text)"""
    contents = re.sub(r'\[/\*\]', '', contents)
    out, pos, depth = [], 0, 0
    for m in LIST_TAG_RE.finditer(contents):
        out.append(contents[pos:m.start()])
        pos = m.end()
        if m.group(1):  # Closing
            depth = max(0, depth - 1)
            if depth == 0:
                out.append(m.group(0))
        else:
            depth += 1
            if depth == 1:
                out.append(m.group(0))
    out.append(contents[pos:])
    return "".join(out)


TABLE_RE = re.compile(r'\[table[^\]]*\](.*?)\[/table\]', re.S | re.I)
ROW_RE = re.compile(r'\[tr[^\]]*\](.*?)\[/tr\]', re.S | re.I)
CELL_RE = re.compile(r'\[(th|td)[^\]]*\](.*?)\[/\1\]', re.S | re.I)
LINK_CARD_RE = re.compile(r'\[dynamiclink\s+href="([^"]+)"[^\]]*\](.*?)\[/dynamiclink\]', re.S | re.I)


def table_text(m):
    """A table (a weapon's stats) as one paragraph, a line per row: "[b]MAGAZINE[/b] · 1". Its cells used to
    become a paragraph each, one word apiece"""
    rows = []
    for row in ROW_RE.finditer(m.group(1)):
        cells = []
        for kind, cell in CELL_RE.findall(row.group(1)):
            cell = re.sub(r'\[/?p[^\]]*\]', ' ', cell).strip()
            if cell:
                cells.append(f"[b]{cell}[/b]" if kind.lower() == "th" else cell)
        if cells:
            rows.append("  ·  ".join(cells))
    return "\n\n" + "\n".join(rows) + "\n\n"


def link_card_text(m):
    """Steam's link cards (a store page, another post, a stream) have no text of their own: a link named
    after what it opens. They used to vanish"""
    url, text = m.group(1), m.group(2).strip()
    if not text:
        store = re.match(r'https?://store\.steampowered\.com/(app|bundle|sub)/\d+/([^/?#]+)', url)
        if store:
            text = store.group(2).replace("_", " ")
        elif re.match(r'https?://(store\.steampowered\.com/news|steamcommunity\.com/games/[^/]+/announcements)', url):
            text = "Steam post"
        else:
            text = re.sub(r'^www\.', '', urllib.parse.urlparse(url).netloc) or url
    return f'\n\n[url="{url}"]{text}[/url]\n\n'


def blocks_for(contents):
    # Both placeholders: posts made with Steam's localized editor (Deadlock's, most new ones) use the LOC one,
    # which points at the same images
    contents = CLAN_PLACEHOLDER_RE.sub(CLAN_IMAGES, contents)
    contents = flatten_lists(contents)
    contents = TABLE_RE.sub(table_text, contents)
    contents = LINK_CARD_RE.sub(link_card_text, contents)
    blocks, pos = [], 0
    for m in BLOCK_RE.finditer(contents):
        blocks += paragraphs(contents[pos:m.start()])
        pos = m.end()
        if m.group("img"):
            blocks += filter(None, [image_block(m)])
        elif m.group("yt"):
            blocks.append({"type": "video", "url": "https://www.youtube.com/watch?v=" + m.group("yt").strip()})
        elif m.group("hl"):
            # An image inside the heading (a banner under the section title): the heading, then it
            head = m.group("h")
            text = inline(INNER_IMG_RE.sub("", head))
            if plain(text):
                blocks.append({"type": "heading", "level": min(3, int(m.group("hl"))), "html": text})
            blocks += filter(None, map(image_block, INNER_IMG_RE.finditer(head)))
        elif m.group("lt"):
            blocks += list_blocks(m.group("list"))
        else:
            blocks.append({"type": "rule"})
    blocks += paragraphs(contents[pos:])
    return blocks


def get_json(url, timeout):
    req = urllib.request.Request(url, headers={"User-Agent": "Ninomae-Shell"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def fetch(app):
    return get_json(API.format(app=app), 10).get("appnews", {}).get("newsitems", [])


def event_types(app):
    """Post title → its type on Steam's events page; {} when that can't be had (the titles decide)."""
    try:
        events = get_json(EVENTS_API.format(app=app), 8).get("events", [])
    except Exception:
        return {}
    return {e.get("event_name", "").strip().lower(): e.get("event_type") for e in events}


def is_update(title, types):
    key = title.strip().lower()
    if key in types:  # The developer's own choice wins ("1.4.5 launch date revealed" is news)
        return types[key] in UPDATE_EVENT_TYPES
    return bool(UPDATE_TITLE_RE.search(title))


def main():
    app, cache_dir = sys.argv[1], sys.argv[2]
    cache = os.path.join(cache_dir, "news", f"{app}.json")
    # Fresh, and made by this version of the script (a change to how posts are read redoes them at once)
    made = os.path.getmtime(cache) if os.path.isfile(cache) else 0
    if made > os.path.getmtime(__file__) and time.time() - made < CACHE_SECONDS:
        with open(cache, encoding="utf-8") as f:
            print(f.read())
        return
    with ThreadPoolExecutor(2) as pool:  # Both at once: the types don't hold the news up
        types_job = pool.submit(event_types, app)
        news_job = pool.submit(fetch, app)
    try:
        news = news_job.result()
    except Exception as e:  # Offline: an older copy beats nothing
        if os.path.isfile(cache):
            with open(cache, encoding="utf-8") as f:
                print(f.read())
        else:
            print(json.dumps({"items": [], "error": str(e)}))
        return
    types = types_job.result()
    items = []
    for n in news:
        title = html.unescape(n.get("title", ""))
        items.append({
            "id": str(n.get("gid", "")),
            "title": title,
            "date": int(n.get("date", 0)),
            "author": n.get("author", ""),
            "url": n.get("url", ""),
            "update": is_update(title, types),
            "blocks": blocks_for(n.get("contents", "")),
        })
    out = json.dumps({"items": items}, ensure_ascii=False)
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    with open(cache + ".tmp", "w", encoding="utf-8") as f:
        f.write(out)
    os.replace(cache + ".tmp", cache)
    print(out)


if __name__ == "__main__":
    main()
