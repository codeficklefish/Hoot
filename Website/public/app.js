// The landing page is static HTML and CSS. This file holds its only two
// behaviours: the hero window's Before/After switch, and the shelf's folder
// tabs.
//
// Both are progressive. The markup ships showing the state the page is arguing
// for — the sorted "after" listing, and Desktop on the shelf — so a visitor
// with no JavaScript still sees the point being made, and the controls simply
// do nothing.

(function () {
  "use strict";

  // ---- the hero window -----------------------------------------------

  var listing = document.getElementById("listing");
  var viewButtons = document.querySelectorAll(".seg button");

  if (listing && viewButtons.length) {
    viewButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        listing.setAttribute("data-view", button.dataset.view);
        viewButtons.forEach(function (other) {
          other.setAttribute("aria-pressed", String(other === button));
        });
      });
    });
  }

  // ---- the shelf -----------------------------------------------------
  //
  // Desktop shows a folder opened in place: the row and its two children share
  // one tile, which is what the app does when you press space on a folder —
  // the list underneath never moves. `open` says where a row sits in that
  // tile, and it is the only reason these rows are not all identical.

  var SHELF = {
    Desktop: [
      { name: "Studio brief", icon: "folder", size: "6 items", age: "55m", open: "top" },
      { name: "brief — v3.pdf", icon: "doc", size: "1.1 MB", age: "", open: "mid", child: true },
      { name: "moodboard.png", icon: "photo", size: "4.2 MB", age: "", open: "end", child: true },
      { name: "site-photos", icon: "folder", size: "41 items", age: "4h" },
      { name: "ARCH 210 — final board.pdf", icon: "doc", size: "18.6 MB", age: "2h" },
      { name: "render-test.mov", icon: "film", size: "1.1 GB", age: "1d" }
    ],
    Downloads: [
      { name: "CODEFISH_ISO_FINDINGS.pdf", icon: "doc", size: "2.4 MB", age: "4m" },
      { name: "12312312312312.docx", icon: "doc", size: "48 KB", age: "22m" },
      { name: "Screenshot 2026-09-14 at 11.43.02.png", icon: "photo", size: "2.8 MB", age: "30m" },
      { name: "ASJKDHASDASD.pdf", icon: "doc", size: "880 KB", age: "3h" },
      { name: "archive (1).zip", icon: "archive", size: "64.2 MB", age: "1d" },
      { name: "DaVinci_Resolve_21.0.4_Mac.dmg", icon: "box", size: "3.9 GB", age: "1d" }
    ],
    Documents: [
      { name: "Coursework", icon: "folder", size: "23 items", age: "12h" },
      { name: "Receipts", icon: "folder", size: "58 items", age: "15h" },
      { name: "Patrick Hans Daguno — resume.pdf", icon: "doc", size: "212 KB", age: "46m" },
      { name: "Tax records — 2025.xlsx", icon: "sheet", size: "1.4 MB", age: "2h" },
      { name: "Electricity bill — February 2026.pdf", icon: "doc", size: "184 KB", age: "7h" },
      { name: "lease-2025-signed.pdf", icon: "doc", size: "640 KB", age: "4d" }
    ]
  };

  var CAPTION = {
    Desktop: "Space opened Studio brief where it stands — the list underneath it never moved.",
    Downloads: "This is the folder Hoot watches, so Tidy appears with the number of files it would file.",
    Documents: "Folders lead, the way the Finder lists them. Hoot only ever reads these."
  };

  var shelf = document.getElementById("shelf");
  var shelfCount = document.getElementById("shelf-count");
  var shelfTidy = document.getElementById("shelf-tidy");
  var shelfCaption = document.getElementById("shelf-caption");
  var shelfButtons = document.querySelectorAll(".notch-tabs button");

  if (!shelf) return;

  function row(item) {
    var el = document.createElement("div");
    el.className = "r";
    if (item.icon === "folder") el.classList.add("is-folder");
    if (item.open) el.classList.add("open-" + item.open);
    if (item.child) el.classList.add("child");

    var glyph = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    glyph.setAttribute("width", "13");
    glyph.setAttribute("height", "13");
    glyph.setAttribute("aria-hidden", "true");
    var use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", "#i-" + item.icon);
    glyph.appendChild(use);
    el.appendChild(glyph);

    // textContent throughout: these names contain em dashes and parentheses,
    // and one of them is a filename somebody could have chosen.
    ["n", "s", "a"].forEach(function (cls, i) {
      var span = document.createElement("span");
      span.className = cls;
      span.textContent = [item.name, item.size, item.age][i];
      el.appendChild(span);
    });
    return el;
  }

  function show(folder) {
    var rows = SHELF[folder];
    if (!rows) return;

    shelf.textContent = "";
    rows.forEach(function (item) { shelf.appendChild(row(item)); });

    // What the panel's header counts: files and folders at this level, so a
    // folder opened in place does not have its children counted twice.
    var files = rows.filter(function (r) { return r.icon !== "folder" && !r.child; }).length;
    var dirs = rows.filter(function (r) { return r.icon === "folder"; }).length;
    shelfCount.textContent = dirs
      ? files + " files · " + dirs + (dirs === 1 ? " folder" : " folders")
      : files + " files";

    // Tidy is the organizer's one appearance here, and only for the folder
    // there is a plan for — which is the watched folder and no other.
    shelfTidy.hidden = folder !== "Downloads";
    shelfCaption.textContent = CAPTION[folder];

    shelfButtons.forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.shelf === folder));
    });
  }

  shelfButtons.forEach(function (b) {
    b.addEventListener("click", function () { show(b.dataset.shelf); });
  });

  show("Desktop");

  // ---- "See it in action" --------------------------------------------
  //
  // The design fills this with a sixty-second animation built as a React
  // artboard. That cannot ship on a page with no framework, and an embedded
  // third-party player is refused for the reason the privacy section exists —
  // so the minute is five states of one mock, stepped through by a timeline
  // that the scrubber and the chapter list both drive.
  //
  // Nothing autoplays. A page that starts moving while you are reading it has
  // taken a decision that belongs to the reader, and `prefers-reduced-motion`
  // is people telling us that outright.

  var CHAPTERS = [
    { id: "pile",   label: "The pile",  at: 0,  title: "Downloads",
      caption: "Forty-nine files. Not one of these names says what the file is.",
      foot: "49 items · 214.6 GB available" },
    { id: "review", label: "Review",    at: 12, title: "Hoot — Review",
      caption: "Nothing moves until you say so. Unsure files stay where they are.",
      foot: "4 of 5 selected · nothing has moved yet" },
    { id: "undo",   label: "Undo",      at: 26, title: "Downloads",
      caption: "Approved. And undone again — every file back where it came from.",
      foot: "6 folders · undo available for this batch" },
    { id: "rename", label: "Renaming",  at: 36, title: "Hoot — Review",
      caption: "A new name comes only from words read out of the file itself.",
      foot: "2 renames proposed · each can be refused on its own" },
    { id: "shelf",  label: "The shelf", at: 48, title: "",
      caption: "Space opens a folder where it stands. The list underneath never moves.",
      foot: "" }
  ];
  var RUNTIME = 60;

  var stage = document.getElementById("stage");
  if (!stage) return;

  var win = document.getElementById("win");
  var desk = document.getElementById("desk");
  var cap = document.getElementById("cap");
  var winTitle = document.getElementById("win-title");
  var winFoot = document.getElementById("win-foot");
  var playBtn = document.getElementById("play");
  var playGlyph = document.getElementById("play-glyph");
  var restartBtn = document.getElementById("restart");
  var elapsed = document.getElementById("elapsed");
  var seek = document.getElementById("seek");
  var chapterBar = document.getElementById("chapters");

  var PLAY = "M3.5 2.2 11.8 7l-8.3 4.8z";
  var PAUSE = "M3.4 2.2h2.6v9.6H3.4zM8 2.2h2.6v9.6H8z";

  var at = 0;          // seconds into the minute
  var playing = false;
  var last = 0;

  function chapterAt(t) {
    var found = CHAPTERS[0];
    CHAPTERS.forEach(function (c) { if (t >= c.at) found = c; });
    return found;
  }

  function clock(t) {
    var m = Math.floor(t / 60);
    var rest = t - m * 60;
    var whole = Math.floor(rest);
    var hundredths = Math.floor((rest - whole) * 100);
    return m + ":" + String(whole).padStart(2, "0") + "." + String(hundredths).padStart(2, "0");
  }

  function paint() {
    var c = chapterAt(at);

    stage.dataset.scene = c.id;
    // The shelf is not a window: it hangs off the camera housing, over the
    // desktop. Showing it inside a Finder window would be the one thing about
    // this surface that people get wrong.
    win.hidden = c.id === "shelf";
    desk.hidden = c.id !== "shelf";

    cap.textContent = c.caption;
    winTitle.textContent = c.title;
    winFoot.textContent = c.foot;
    winFoot.hidden = !c.foot;

    elapsed.textContent = clock(at);
    if (document.activeElement !== seek) seek.value = String(at);

    chapterBar.querySelectorAll("button").forEach(function (b) {
      b.setAttribute("aria-current", String(b.dataset.chapter === c.id));
    });
  }

  function tick(now) {
    if (!playing) return;
    at += (now - last) / 1000;
    last = now;
    if (at >= RUNTIME) { at = RUNTIME; pause(); paint(); return; }
    paint();
    requestAnimationFrame(tick);
  }

  function play() {
    if (at >= RUNTIME) at = 0;
    playing = true;
    playGlyph.setAttribute("d", PAUSE);
    playBtn.setAttribute("aria-label", "Pause");
    last = performance.now();
    requestAnimationFrame(tick);
  }

  function pause() {
    playing = false;
    playGlyph.setAttribute("d", PLAY);
    playBtn.setAttribute("aria-label", "Play");
  }

  playBtn.addEventListener("click", function () { playing ? pause() : play(); });
  restartBtn.addEventListener("click", function () { at = 0; paint(); if (!playing) play(); });
  seek.addEventListener("input", function () { at = Number(seek.value); paint(); });

  CHAPTERS.forEach(function (c) {
    var b = document.createElement("button");
    b.type = "button";
    b.dataset.chapter = c.id;
    b.textContent = c.label;
    b.addEventListener("click", function () { at = c.at; paint(); });
    chapterBar.appendChild(b);
  });

  paint();
})();
