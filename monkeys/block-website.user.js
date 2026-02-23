// ==UserScript==
// @name         Website Blocker (Redirect)
// @namespace    https://example.com/
// @version      1.0
// @description  Redirects away from blocked domains (including subdomains).
// @match        *://*/*
// @run-at       document-start
// @grant        none
// @updateURL    https://raw.githubusercontent.com/sorrtory/scripts/refs/heads/master/monkeys/block-website.user.js
// @downloadURL  https://raw.githubusercontent.com/sorrtory/scripts/refs/heads/master/monkeys/block-website.user.js
// ==/UserScript==

(() => {
  "use strict";

  // ✅ Where to send the user if a site is blocked:
  const REDIRECT_TO = "https://github.com/sorrtory";

  // ✅ Domains to block (base domains only). Subdomains are blocked automatically.
  // Examples: "facebook.com" blocks facebook.com, www.facebook.com, m.facebook.com, etc.
    const BLOCKED_DOMAINS = [
        "facebook.com",
        "instagram.com",
        "tiktok.com",
        "x.com",
        "twitter.com",
        "snapchat.com",
        "pinterest.com",

        "twitch.tv",
        "kick.com",
        "rumble.com",
        "streamable.com",
        "vimeo.com",
        "dailymotion.com",
        "9gag.com",

        "4chan.org",
        "2ch.org",
        "resetera.com",

        "news.google.com",
        "cnn.com",
        "bbc.com",
        "nytimes.com",
        "theguardian.com",
        "foxnews.com",
        "reuters.com",
        "bloomberg.com",

        "ebay.com",
        "aliexpress.com",
        "temu.com",
        "shein.com",
        "walmart.com",
        "bestbuy.com",
        "target.com",

        "steampowered.com",
        "store.steampowered.com",
        "epicgames.com",
        "battle.net",
        "ea.com",
        "riotgames.com",
        "roblox.com",
        "chess.com",

        "pornhub.com",
        "xvideos.com",
        "xnxx.com",
        "onlyfans.com",
    ];


  const hostname = (location.hostname || "").toLowerCase();

  function isBlockedHost(host, blockedDomains) {
    // Block exact domain OR any subdomain of it.
    // e.g. host="a.b.example.com" matches "example.com"
    return blockedDomains.some((domain) => {
      domain = domain.toLowerCase().trim();
      return host === domain || host.endsWith("." + domain);
    });
  }

  // Allow on sunday
  const isWeekend = () => new Date().getDay() === 0;

  if (!isWeekend() && isBlockedHost(hostname, BLOCKED_DOMAINS)) {
    // Avoid infinite redirect loop if your redirect page is on a blocked domain.
    const redirectHost = new URL(REDIRECT_TO).hostname.toLowerCase();
    const redirectIsBlocked = isBlockedHost(redirectHost, BLOCKED_DOMAINS);

    if (!redirectIsBlocked) {
      // Replace so back button doesn't return to the blocked site
      location.replace(REDIRECT_TO);
    }
  }
})();

