// The landing page is static HTML and CSS. This file holds its only two
// behaviours: the hero window's Before/After switch, and the shelf's folder
// tabs.
//
// Both are progressive. The markup ships showing the state the page is arguing
// for — the sorted "after" listing, and Desktop on the shelf — so a visitor
// with no JavaScript still sees the point being made, and the controls simply
// do nothing.

// Each feature gets its own scope. They shared one for a while, and two of
// them declared a function called `show` — the later declaration hoisted over
// the earlier, so every call to reveal a section was really the shelf's
// folder switcher being handed a <div>. It returned immediately, nothing was
// ever revealed, and only the fallback timer in the head kept the page from
// staying blank. Nothing here is worth sharing a scope for.

(function () {
  "use strict";

  // ---- entrance and reveal -------------------------------------------
  //
  // The head script has already put `.js` on the document, so the entrance
  // styles are live and everything marked `data-reveal` is currently hidden.
  // It also armed a timer that shows the lot after 2.2s no matter what, so a
  // failure anywhere below this line costs an animation and never the page.

  var root = document.documentElement;
  var stages = [].slice.call(document.querySelectorAll("[data-reveal]"));

  function reveal(el) { el.classList.add("is-in"); }

  if (!("IntersectionObserver" in window)) {
    // No observer, no staged reveal. Everything at once beats nothing at all.
    root.className += " reveal-all";
  } else {
    // The head armed a timer that reveals everything after 2.2s in case this
    // file never ran. It has run, so stand it down — left alone it would fire
    // mid-scroll and show every remaining section at once, which is the thing
    // it was protecting against doing the damage instead.
    clearTimeout(window.__hootReveal);

    var watcher = new IntersectionObserver(function (entries, self) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        reveal(entry.target);
        // One reveal each. A section that faded back out as you scrolled past
        // it would be an effect rather than an entrance.
        self.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -12% 0px", threshold: 0.08 });

    stages.forEach(function (el) {
      // The first screen is not scrolled to, so it is not the observer's job.
      if (!el.hasAttribute("data-entrance")) watcher.observe(el);
    });

    // The first screen waits for the typefaces. That wait is what makes the
    // entrance feel controlled rather than slow: the headline comes in already
    // set in Figtree instead of arriving in a fallback and jumping when the
    // real face lands. Capped, because a font that never loads must not hold
    // the page hostage — and `document.fonts` is not everywhere.
    var opened = false;
    function openTheCurtain() {
      if (opened) return;
      opened = true;
      stages.forEach(function (el) { if (el.hasAttribute("data-entrance")) reveal(el); });
    }
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(openTheCurtain);
    }
    setTimeout(openTheCurtain, 700);

    // A narrower net than the one just stood down: on load, anything already
    // on screen that the observer has not reported is revealed anyway. It
    // cannot reveal what you have not scrolled to, so it costs nothing if the
    // observer is working and saves the first screen if it is not.
    window.addEventListener("load", function () {
      setTimeout(function () {
        stages.forEach(function (el) {
          if (el.classList.contains("is-in")) return;
          var box = el.getBoundingClientRect();
          if (box.top < window.innerHeight && box.bottom > 0) reveal(el);
        });
      }, 1200);
    });
  }
})();

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

})();

(function () {
  "use strict";

  // ---- "See it in action" --------------------------------------------
  //
  // A self-hosted file, for the reason the privacy section exists: a page that
  // tells people the app reaches nothing cannot hand its visitor to somebody
  // else's player. It is fetched only by a visitor who scrolls this far
  // (`preload="none"`), starts when the section is actually on screen, and
  // stops when it is not — nine megabytes decoding behind you is a warm phone
  // and nothing else.
  //
  // No chrome. It loops, so it restarts itself, and a minute of silent screen
  // recording is not something anybody needs to scrub.
  //
  // Muted and `playsinline`, which is not a style choice: no browser will
  // autoplay a video with sound, and one that asked to would deserve the
  // refusal.

  var video = document.getElementById("demo-video");
  if (!video) return;

  // A video that plays by itself and cannot be stopped is the one case this
  // page would genuinely get wrong for somebody — so where the system has
  // asked for less motion, it does not start, and it gets the browser's own
  // controls instead so it can still be watched on purpose.
  var stillness = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)");
  if (stillness && stillness.matches) {
    video.controls = true;
    video.removeAttribute("loop");
    return;
  }

  function start() {
    // Autoplay can be refused — a browser setting, a data saver, a policy this
    // page does not get to see. The promise rejecting is not an error; it is
    // the visitor's answer, and the poster is already there for it.
    var attempt = video.play();
    if (attempt && attempt.catch) attempt.catch(function () {});
  }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          if (video.preload === "none") video.preload = "auto";
          start();
        } else if (!video.paused) {
          video.pause();
        }
      });
    }, { threshold: 0.45 }).observe(video);
  } else {
    video.preload = "auto";
  }
})();
