ublock.js text/javascript
(function () {
    "use strict";
    console.log("Hello World from injected script! 2");
    // function checkAndRedirect() {
    //   console.log("Redirecting: vk/feed -> vk/im");
    //   const p = location.pathname;
    //   if (p === "/" || p.startsWith("/feed")) {
    //     location.replace("https://vk.com/im");
    //   }
    // }

    // // Initial load
    // checkAndRedirect();

    // // Listen for back/forward navigation
    // window.addEventListener("popstate", checkAndRedirect);

    // // Hook pushState & replaceState to detect in-page navigation
    // const origPushState = history.pushState;
    // history.pushState = function (...args) {
    //   origPushState.apply(this, args);
    //   checkAndRedirect();
    // };

    // const origReplaceState = history.replaceState;
    // history.replaceState = function (...args) {
    //   origReplaceState.apply(this, args);
    //   checkAndRedirect();
    // };
})();