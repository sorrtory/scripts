ublock.js text/javascript
(function () {
 alert("HELLO " + document.location.href);

  document.addEventListener("DOMContentLoaded", function () {
    alert("Loaded: " + document.location.href);
    if ( /(^|\.)vk\.(com|ru)$/.test(document.location.hostname) === false ) { return; }
    console.log("Redirecting: vk/feed -> vk/im");

    function checkAndRedirect() {
      const p = location.pathname;
      if (p === "/" || p.startsWith("/feed")) {
        location.replace("https://vk.com/im");
      }
    }

    // Initial load
    checkAndRedirect();

    // Listen for back/forward navigation
    window.addEventListener("popstate", checkAndRedirect);

    // Hook pushState & replaceState to detect in-page navigation
    const origPushState = history.pushState;
    history.pushState = function (...args) {
      origPushState.apply(this, args);
      checkAndRedirect();
    };

    const origReplaceState = history.replaceState;
    history.replaceState = function (...args) {
      origReplaceState.apply(this, args);
      checkAndRedirect();
    };
  });
})();

// ==UserScript==
// @name         bye-bye vk/feed
// @namespace    http://tampermonkey.net/
// @version      2025-08-26
// @description  Reditect from vk/feed -> vk/im
// @author       You
// @match        https://vk.com/*
// @run-at       document-start
// @icon         data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==
// @grant        none
// ==/UserScript==
