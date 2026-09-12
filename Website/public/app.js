// The landing page is static HTML and CSS. This file holds its only behaviour:
// the hero window's Before/After switch.
//
// It is progressive — the markup ships showing the sorted "after" state, so a
// visitor with no JavaScript still sees the thing the page is arguing for, and
// the control simply does nothing.

(function () {
  var listing = document.getElementById("listing");
  var buttons = document.querySelectorAll(".seg button");
  if (!listing || !buttons.length) return;

  function show(view) {
    listing.setAttribute("data-view", view);
    buttons.forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.view === view));
    });
  }

  buttons.forEach(function (b) {
    b.addEventListener("click", function () { show(b.dataset.view); });
  });
})();
