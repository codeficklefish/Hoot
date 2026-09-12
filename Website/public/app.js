// The landing page is static HTML and CSS. This file holds the only behaviour
// it has: keeping the demo recording from playing on when nobody is looking.
//
// Everything else people see — the layout, the hover states, the theme — is
// CSS, and deliberately so. Nothing here is required for the page to make its
// argument: with this file absent the video still plays, it just keeps playing
// after you scroll away.

(function () {
  var video = document.querySelector(".demo-video");
  if (!video || !("IntersectionObserver" in window)) return;

  // The recording is 30 seconds with no audio track, so a viewer who starts it
  // and scrolls on has no way of noticing it is still running. Pause it when it
  // leaves the viewport, and leave it paused — resuming something the viewer
  // scrolled away from would be presumptuous.
  var watcher = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting && !video.paused) video.pause();
      });
    },
    { threshold: 0.2 }
  );

  watcher.observe(video);
})();
