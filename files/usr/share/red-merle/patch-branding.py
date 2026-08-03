#!/usr/bin/env python3
# red-merle GL panel + SSH banner branding, applied by the package postinst.
#
# Single source of truth for every user-visible version string: the caller
# passes the package version, this script rewrites all of them. Idempotent AND
# self-updating -> a reinstall of a newer package refreshes stale versions
# instead of skipping (the "frozen 2.2.0 banner" class of bug).
#
# Usage: patch-branding.py <version>
import glob
import gzip
import json
import os
import re
import shutil
import sys

VER = sys.argv[1] if len(sys.argv) > 1 else "0.0.0"

BANNER = "/etc/banner"
GL_HOME = "/www/gl_home.html"
HOME_GZ = "/www/views/gl-sdk4-ui-home.common.js.gz"
OV_GZ = "/www/views/gl-sdk4-ui-overview.common.js.gz"
I18N = "/www/i18n/gl-sdk4-ui-home.*.json"
LOGO_SRC = "/usr/share/red-merle/logo.svg"
LOGO_DST = "/www/logo.svg"


def log(msg):
    print("red-merle branding: %s" % msg)


def read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_text(path, data):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(data)


def read_gz(path):
    with gzip.open(path, "rb") as fh:
        return fh.read()


def write_gz(path, data):
    # mtime=0 -> byte-stable output, so reinstalling twice is a no-op on disk
    with open(path, "wb") as fh:
        fh.write(gzip.compress(data, compresslevel=9, mtime=0))


# --------------------------------------------------------------------------
# 1. SSH banner: RED MERLE art above the stock OpenWrt logo, both kept.
# --------------------------------------------------------------------------
ART = [
    r" ____  _____ ____    __  __ _____ ____  _     _____ ",
    r"|  _ \| ____|  _ \  |  \/  | ____|  _ \| |   | ____|",
    r"| |_) |  _| | | | | | |\/| |  _| | |_) | |   |  _|  ",
    r"|  _ <| |___| |_| | | |  | | |___|  _ <| |___| |___ ",
    r"|_| \_\_____|____/  |_|  |_|_____|_| \_\_____|_____|",
]
TAGLINE = "      ☢  C E L L U L A R   A N O N Y M I T Y  ☢"
# Unique marker used to find (and drop) a previously injected block.
SENTINEL = "A N O N Y M I T Y"
SUFFIX_RE = re.compile(r"\s*—\s*☢ red-merle\s+\S+\s*$")


def brand_banner():
    lines = read_text(BANNER).splitlines()

    # Drop any block we injected before: it always sits at the very top and
    # ends with the tagline + one blank line. Re-deriving it from the stock
    # banner keeps us correct after a firmware upgrade rewrites the file.
    for i, line in enumerate(lines):
        if SENTINEL in line:
            lines = lines[i + 1:]
            if lines and not lines[0].strip():
                lines.pop(0)
            break

    # Refresh (not append) the version suffix on the OpenWrt release line.
    out = []
    for line in lines:
        if line.lstrip().startswith("OpenWrt "):
            line = SUFFIX_RE.sub("", line) + " — ☢ red-merle " + VER
        out.append(line)

    block = [" " + row for row in ART] + [TAGLINE, ""]
    write_text(BANNER, "\n".join(block + out) + "\n")
    log("banner art + version -> %s" % VER)


# --------------------------------------------------------------------------
# 2. Combined GL.iNet + trefoil logo (copied, never owned -> no opkg clash).
# --------------------------------------------------------------------------
def install_logo():
    if os.path.exists(LOGO_SRC):
        shutil.copy(LOGO_SRC, LOGO_DST)
        log("logo installed")


# --------------------------------------------------------------------------
# 3. gl_home.html: header brand + sidebar entry.
#
# The panel's CSS is Vue-scoped (.versions[data-v-13fae0b2]{font-size:12px...}),
# so a hand-written class="versions" gets no styling at all -> we clone GL's own
# nodes and inherit their data-v attribute. That gives native size, colour and
# spacing for free, and keeps working if the theme changes.
# --------------------------------------------------------------------------
SCRIPT = """<script id="redmerle-brand-js">
window.addEventListener("load", function () {
  var RM_VER = "__VER__";
  var RM_URL = "https://github.com/franckferman/red-merle";
  var tries = 0;
  var iv = setInterval(function () {
    var done = 0;
    var desc = document.querySelector("span.desc.capitalize");
    if (desc) {
      if (!document.getElementById("redmerle-brand")) {
        var after = desc;
        var div = document.querySelector(".divide-left");
        if (div) {
          var dc = div.cloneNode(false);
          /* the stock divider only carries margin-right: it sits after the
             logo, which brings its own margin. Ours follows a text run, so
             without a left margin it ends up glued to "v4.0". */
          dc.style.marginLeft = "18px";
          after.parentNode.insertBefore(dc, after.nextSibling);
          after = dc;
        }
        var brand = desc.cloneNode(false);   /* keeps class + data-v scope */
        brand.id = "redmerle-brand";
        var a = document.createElement("a");
        a.href = RM_URL;
        a.target = "_blank";
        a.rel = "noopener noreferrer";
        a.textContent = "Red Merle";
        a.style.cssText = "color:inherit;text-decoration:none;";
        brand.appendChild(a);
        var nv = desc.querySelector(".versions");
        var v = nv ? nv.cloneNode(false) : document.createElement("span");
        if (!nv) {
          v.className = "versions";
          v.style.cssText = "font-size:12px;margin-left:6px;opacity:.7;";
        }
        v.id = "redmerle-version";
        v.style.cursor = "default";
        brand.appendChild(v);
        after.parentNode.insertBefore(brand, after.nextSibling);
      }
      var cur = document.getElementById("redmerle-version");
      if (cur) cur.textContent = "v" + RM_VER;   /* refresh on every load */
      done++;
    }
    /* Footer credit: the i18n string is rendered as a text node, so markup in
       it would show up literally. Inject real anchors instead, cloned from the
       footer's own link so they inherit its scoped (data-v) styling. */
    var foot = document.querySelector(".footer");
    if (foot && !document.getElementById("redmerle-credit")) {
      var walker = document.createTreeWalker(foot, NodeFilter.SHOW_TEXT, null, false);
      var node, target = null;
      while ((node = walker.nextNode())) {
        if (node.nodeValue.indexOf("Franck Ferman") !== -1) { target = node; break; }
      }
      if (target) {
        var proto = foot.querySelector("a");
        var mkLink = function (href, text, id) {
          var a = proto ? proto.cloneNode(false) : document.createElement("a");
          a.removeAttribute("class");
          if (id) a.id = id;
          a.href = href;
          a.target = "_blank";
          a.rel = "noopener noreferrer";
          a.textContent = text;
          if (!proto) a.style.cssText = "color:var(--primary);text-decoration:none;";
          return a;
        };
        var parts = target.nodeValue.split("Franck Ferman / red-merle");
        var frag = document.createDocumentFragment();
        frag.appendChild(document.createTextNode(parts[0]));
        frag.appendChild(mkLink("https://github.com/franckferman", "Franck Ferman", "redmerle-credit"));
        frag.appendChild(document.createTextNode(" / "));
        frag.appendChild(mkLink("https://github.com/franckferman/red-merle", "red-merle"));
        if (parts.length > 1 && parts[1]) frag.appendChild(document.createTextNode(parts[1]));
        target.parentNode.replaceChild(frag, target);
      }
    }
    if (document.getElementById("redmerle-credit")) done++;
    var menu = document.querySelector("ul.el-menu");
    if (menu && !document.getElementById("redmerle-menu-item")) {
      var li = document.createElement("li");
      li.id = "redmerle-menu-item";
      li.className = "el-menu-item";
      /* A real anchor, not a click handler: the panel's own entries are Vue
         router links, but ours points at a plain URL, so middle-click and
         ctrl-click should open it in a tab like any other link. */
      li.innerHTML = '<a href="/redmerle/" style="display:flex;align-items:center;'
        + 'width:100%;height:100%;color:inherit;text-decoration:none">'
        + '<span style="color:#e03e2d;margin-right:4px">☢</span><span>RED MERLE</span></a>';
      menu.appendChild(li);
    }
    if (menu && document.getElementById("redmerle-menu-item")) done++;
    if (done === 2 || ++tries > 80) clearInterval(iv);
  }, 250);
});
</script>
</head>"""


def brand_gl_home():
    html = read_text(GL_HOME)
    # Remove every previous injection (older builds had no id on the tag).
    html = re.sub(r"<script[^>]*>.*?redmerle-brand.*?</script>\n?", "", html, flags=re.S)
    if "</head>" not in html:
        log("gl_home skipped: no </head> (firmware changed?)")
        return
    write_text(GL_HOME, html.replace("</head>", SCRIPT.replace("__VER__", VER), 1))
    log("gl_home header + sidebar -> %s" % VER)


# --------------------------------------------------------------------------
# 4. Theme dropdown entries (minified bundle, guarded single replace).
# --------------------------------------------------------------------------
def patch_theme_dropdown():
    data = read_gz(HOME_GZ)
    old = b',{label:this.$t("home.dark"),value:"dark"}'
    new = (old
           + b',{label:this.$t("home.redmerle"),value:"redmerle"}'
           + b',{label:this.$t("home.redmerlehacker"),value:"redmerle-hacker"}')
    if data.count(old) == 1 and b"home.redmerle" not in data:
        write_gz(HOME_GZ, data.replace(old, new))
        log("theme dropdown patched")
    elif b"home.redmerle" not in data:
        log("theme dropdown skipped: anchor changed (firmware bump?)")


# --------------------------------------------------------------------------
# 5. i18n: theme names + footer (keys are nested under "home").
# --------------------------------------------------------------------------
def patch_i18n():
    for path in glob.glob(I18N):
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            doc.pop("redmerle", None)          # stray root key from old builds
            home = doc.get("home")
            if not isinstance(home, dict):
                continue
            home["redmerle"] = "Red Merle"
            home["redmerlehacker"] = "Red Merle Hacker"
            if isinstance(home.get("footer"), dict):
                home["footer"]["desc"] = (
                    "All Rights Reserved · ☢ 2026 Franck Ferman / red-merle")
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(doc, fh, ensure_ascii=False)
        except Exception as exc:
            log("i18n %s skipped: %s" % (os.path.basename(path), exc))
    log("i18n theme names + footer done")


# --------------------------------------------------------------------------
# 6. System Info "Red Merle version" row + red chart colours.
# --------------------------------------------------------------------------
def patch_overview():
    data = read_gz(OV_GZ)
    anchor = b"t.systemInfo.board_info.kernel_version))])])]:t._e()"
    row = (b"t.systemInfo.board_info.kernel_version))])]),"
           b'e("li",[e("div",[t._v("Red Merle version")]),'
           b'e("div",[t._v("\\u2622 v' + VER.encode() + b'")])])])]:t._e()')
    if b"Red Merle version" in data:
        # Row already there: only refresh the version (lambda repl, a plain
        # bytes replacement would choke on the \u escape).
        data = re.sub(rb"\\u2622 v[0-9]+\.[0-9]+\.[0-9]+",
                      lambda m: b"\\u2622 v" + VER.encode(), data)
        log("sysinfo row -> %s" % VER)
    elif data.count(anchor) == 1:
        data = data.replace(anchor, row)
        log("sysinfo row added (%s)" % VER)
    else:
        log("sysinfo row skipped: anchor changed (firmware bump?)")

    for old, new in [
        (b'borderColor:"#425BC6",backgroundColor:"rgba(66, 91, 198, 0.1)"',
         b'borderColor:"#c41a0e",backgroundColor:"rgba(196, 26, 14, 0.18)"'),
        (b'borderColor:["#343160","#0292A8"],backgroundColor:["rgba(155,156,194,0.20)","rgba(2,182,210,0.1)"]',
         b'borderColor:["#c41a0e","#d9a13b"],backgroundColor:["rgba(196,26,14,0.25)","rgba(217,161,59,0.20)"]'),
    ]:
        if data.count(old) == 1:
            data = data.replace(old, new)
            log("chart colours patched")
    write_gz(OV_GZ, data)


# Each step is independent: a firmware change breaking one must not skip the
# rest, and none of them may ever fail the package install.
for name, step in [
    ("banner", brand_banner),
    ("logo", install_logo),
    ("gl_home", brand_gl_home),
    ("dropdown", patch_theme_dropdown),
    ("i18n", patch_i18n),
    ("overview", patch_overview),
]:
    try:
        step()
    except Exception as exc:
        log("%s skipped: %s" % (name, exc))
