// ==UserScript==
// @name         bye-bye vk/feed
// @namespace    http://tampermonkey.net/
// @version      2026-02-08
// @description  Reditect from vk/feed -> vk/im
// @author       sorrtory
// @match        https://vk.com/*
// @match        https://vk.ru/*
// @run-at       document-start
// @grant        none
// @updateURL    https://raw.githubusercontent.com/sorrtory/scripts/refs/heads/master/monkeys/block-vk-feed.js
// @downloadURL  https://raw.githubusercontent.com/sorrtory/scripts/refs/heads/master/monkeys/block-vk-feed.js
// ==/UserScript==

(function () {
    "use strict";
    function checkAndRedirect() {
        const p = location.pathname;
        if (p === "/" || p.startsWith("/feed") || p.startsWith("/al_feed")) {
            location.replace(location.origin + "/im");
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
})();
