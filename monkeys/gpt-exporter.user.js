// ==UserScript==
// @name         GPT Clean PDF/HTML Exporter
// @namespace    local
// @version      6.1
// @description  Export ChatGPT/Claude conversations into clean printable PDF/HTML with TOC, copy buttons, Markdown copying, provider architecture, CSP-safe live export, and local-file HTML runtime.
// @match        https://chatgpt.com/*
// @match        https://chat.openai.com/*
// @match        https://claude.ai/*
// @match        https://claude.com/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(function () {
    "use strict";

    /**********************************************************************
     * Configuration
     **********************************************************************/

    const CONFIG = {
        buttonId: "tm-gpt-clean-pdf-exporter",
        buttonStyleId: "tm-gpt-clean-pdf-exporter-style",

        parserMaxAttempts: 40,
        parserRetryDelayMs: 250,

        defaultTitle: "GPT conversation",

        autoPrint: false,
        autoPrintDelayMs: 350,

        tocPreviewMaxLength: 140,
    };

    /**********************************************************************
     * Provider registry
     **********************************************************************/

    const PROVIDERS = {
        chatGPT: {
            key: "chatGPT",
            name: "ChatGPT",
            hostPatterns: ["chatgpt.com", "chat.openai.com"],
            buttonLabel: "PDF export",
            buttonTitle: "Export this ChatGPT conversation to clean PDF/HTML",
            buttonClass: "provider-chatgpt",

            getRootDocument() {
                return document;
            },

            getThreadRoot(doc) {
                return (
                    doc.querySelector("#thread") ||
                    doc.querySelector("main#main") ||
                    doc.body
                );
            },

            getConversationTitle(doc) {
                const title =
                    doc
                        .querySelector('[data-testid="conversation-title"]')
                        ?.textContent?.trim() ||
                    doc.querySelector("title")?.textContent?.trim() ||
                    CONFIG.defaultTitle;

                return title === "ChatGPT" ? "ChatGPT conversation" : title;
            },

            isInsideComposer(el) {
                return Boolean(
                    el.closest(
                        [
                            "form",
                            "textarea",
                            "#thread-bottom-container",
                            "[data-testid='composer']",
                            "[data-testid='composer-footer-actions']",
                            "[data-composer-surface='true']",
                            ".composer-parent form",
                        ].join(","),
                    ),
                );
            },

            findMessageRoots(threadRoot) {
                let roots = this.findRootsByAuthorRole(threadRoot);

                if (!roots.length) {
                    roots = this.findRootsByMarkdownContainers(threadRoot);
                }

                if (!roots.length) {
                    roots = this.findRootsByRichContentHeuristic(threadRoot);
                }

                return roots.filter(hasExportableContent);
            },

            findRootsByAuthorRole(threadRoot) {
                const roleNodes = Array.from(
                    threadRoot.querySelectorAll("[data-message-author-role]"),
                ).filter((el) => !this.isInsideComposer(el));

                const roots = roleNodes.map((el) => {
                    return (
                        el.closest("[data-message-id]") ||
                        el.closest("[data-testid*='conversation-turn']") ||
                        el.closest("article") ||
                        el
                    );
                });

                return removeNestedDuplicateElements(uniqueElements(roots));
            },

            findRootsByMarkdownContainers(threadRoot) {
                const contentNodes = Array.from(
                    threadRoot.querySelectorAll(
                        ".markdown, .prose, [class*='markdown'], [class*='prose']",
                    ),
                ).filter((el) => !this.isInsideComposer(el));

                const roots = contentNodes.map((el) => {
                    return (
                        el.closest("[data-message-id]") ||
                        el.closest("[data-testid*='conversation-turn']") ||
                        el.closest("article") ||
                        el
                    );
                });

                return removeNestedDuplicateElements(uniqueElements(roots));
            },

            findRootsByRichContentHeuristic(threadRoot) {
                const candidates = Array.from(
                    threadRoot.querySelectorAll("div"),
                )
                    .filter((el) => {
                        if (this.isInsideComposer(el)) return false;

                        const text = getCleanText(el);
                        const hasRichContent = el.querySelector(
                            "p, pre, code, ul, ol, table, blockquote, h1, h2, h3, h4, img, .katex",
                        );

                        return text.length > 40 && hasRichContent;
                    })
                    .filter((el) => {
                        return !Array.from(el.children).some(
                            (child) =>
                                getCleanText(child).length >
                                getCleanText(el).length * 0.8,
                        );
                    });

                return removeNestedDuplicateElements(
                    uniqueElements(candidates),
                );
            },

            inferMessageRole(root, index) {
                const explicitRole =
                    root
                        .querySelector("[data-message-author-role]")
                        ?.getAttribute("data-message-author-role") ||
                    root.getAttribute("data-message-author-role") ||
                    "";

                const normalized = explicitRole.toLowerCase();

                if (normalized === "user") return "User";
                if (normalized === "assistant") return "ChatGPT";
                if (normalized === "tool") return "Tool";

                const label = getCleanText(root).slice(0, 100).toLowerCase();

                if (label.startsWith("you")) return "User";
                if (label.startsWith("chatgpt")) return "ChatGPT";

                return index % 2 === 0 ? "User" : "ChatGPT";
            },
        },

        claude: {
            key: "claude",
            name: "Claude",
            hostPatterns: ["claude.ai", "claude.com"],
            buttonLabel: "Claude PDF",
            buttonTitle: "Export this Claude conversation to clean PDF/HTML",
            buttonClass: "provider-claude",

            getRootDocument() {
                return document;
            },

            getThreadRoot(doc) {
                return (
                    doc.querySelector("#main-content") ||
                    doc.querySelector("[data-autoscroll-container='true']") ||
                    doc.querySelector("main") ||
                    doc.body
                );
            },

            getConversationTitle(doc) {
                const fromHeader =
                    doc
                        .querySelector("[data-testid='chat-title-button']")
                        ?.textContent?.trim() ||
                    doc
                        .querySelector(
                            "button[data-testid='chat-title-button'] div",
                        )
                        ?.textContent?.trim();

                if (fromHeader) return fromHeader;

                const title =
                    doc.querySelector("title")?.textContent?.trim() ||
                    "Claude conversation";

                return (
                    title.replace(/\s*-\s*Claude\s*$/i, "").trim() ||
                    "Claude conversation"
                );
            },

            isInsideComposer(el) {
                return Boolean(
                    el.closest(
                        [
                            "[data-chat-input-container='true']",
                            "[data-testid='chat-input']",
                            ".ProseMirror",
                            "form",
                            "textarea",
                            "[contenteditable='true']",
                            "[data-testid*='composer']",
                        ].join(","),
                    ),
                );
            },

            findMessageRoots(threadRoot) {
                const roots = [];

                threadRoot
                    .querySelectorAll(
                        "[data-user-message-bubble='true'], [data-testid='user-message']",
                    )
                    .forEach((el) => {
                        if (this.isInsideComposer(el)) return;

                        roots.push(
                            el.closest(".mb-1.mt-6.group") ||
                                el.closest("[data-test-render-count]") ||
                                el.closest(".contents") ||
                                el,
                        );
                    });

                threadRoot
                    .querySelectorAll(
                        "[data-is-streaming], .font-claude-response, .standard-markdown, .progressive-markdown",
                    )
                    .forEach((el) => {
                        if (this.isInsideComposer(el)) return;

                        const root =
                            el.closest("[data-is-streaming]") ||
                            el.closest("[data-test-render-count]") ||
                            el.closest(".contents") ||
                            el;

                        if (
                            root.querySelector(
                                ".font-claude-response, .standard-markdown, .progressive-markdown",
                            ) ||
                            root.matches(
                                ".font-claude-response, .standard-markdown, .progressive-markdown",
                            )
                        ) {
                            roots.push(root);
                        }
                    });

                return removeNestedDuplicateElements(uniqueElements(roots))
                    .filter((root) => !this.isInsideComposer(root))
                    .filter(hasExportableContent)
                    .sort(compareElementsInDocumentOrder);
            },

            inferMessageRole(root, index) {
                const srLabel = getCleanTextFromSelector(
                    root,
                    "h2.sr-only",
                ).toLowerCase();

                if (
                    root.querySelector(
                        "[data-user-message-bubble='true'], [data-testid='user-message']",
                    ) ||
                    srLabel.startsWith("you said")
                ) {
                    return "User";
                }

                if (
                    root.querySelector(
                        ".font-claude-response, .standard-markdown, .progressive-markdown",
                    ) ||
                    srLabel.startsWith("claude responded")
                ) {
                    return "Claude";
                }

                return index % 2 === 0 ? "User" : "Claude";
            },

            findBestMessageBodyCandidate(root) {
                return (
                    root.querySelector("[data-testid='user-message']") ||
                    root.querySelector(
                        "[data-user-message-bubble='true'] [data-testid='user-message']",
                    ) ||
                    root.querySelector(".standard-markdown") ||
                    root.querySelector(".progressive-markdown") ||
                    root.querySelector(".font-claude-response")
                );
            },

            extractMessageTimestamp(root) {
                const actionGroup = root.querySelector(
                    "[role='group'][aria-label='Message actions']",
                );

                if (actionGroup) {
                    const timestamp = findClaudeTimestampText(actionGroup);
                    if (timestamp) return timestamp;
                }

                return findClaudeTimestampText(root);
            },
        },
    };

    const ACTIVE_PROVIDER = detectProvider();

    const CHATGPT_MESSAGE_TIMESTAMPS = new Map();
    const CHATGPT_CONVERSATION_FETCHES = new Map();

    installChatGptConversationResponseWatcher();

    function detectProvider() {
        const host = location.hostname;

        return (
            Object.values(PROVIDERS).find((candidate) => {
                return candidate.hostPatterns.some(
                    (pattern) =>
                        host === pattern || host.endsWith(`.${pattern}`),
                );
            }) || PROVIDERS.chatGPT
        );
    }

    function getProvider() {
        return ACTIVE_PROVIDER;
    }

    /**********************************************************************
     * Stage 1: Parent-page UI
     **********************************************************************/

    function injectExportButtonStyles() {
        if (!document.head) return;
        if (document.getElementById(CONFIG.buttonStyleId)) return;

        const style = document.createElement("style");
        style.id = CONFIG.buttonStyleId;

        style.textContent = `
      #${CONFIG.buttonId} {
        position: fixed;
        right: 18px;
        bottom: 18px;
        z-index: 2147483647;

        display: inline-flex;
        align-items: center;
        gap: 8px;

        height: 42px;
        padding: 0 15px;

        border-radius: 9999px;
        border: 1px solid rgba(255,255,255,.16);

        background: #212121;
        color: #f4f4f4;

        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        font-size: 14px;
        font-weight: 500;

        box-shadow: 0 8px 24px rgba(0,0,0,.25);
        cursor: pointer;
      }

      #${CONFIG.buttonId}:hover {
        background: #2f2f2f;
      }

      #${CONFIG.buttonId}.provider-claude {
        background: #2b241f;
      }

      #${CONFIG.buttonId}.provider-claude:hover {
        background: #3a312a;
      }

      #${CONFIG.buttonId} svg {
        width: 16px;
        height: 16px;
      }
    `;

        document.head.appendChild(style);
    }

    function createExportButton() {
        if (!document.body) return;
        if (document.getElementById(CONFIG.buttonId)) return;

        const provider = getProvider();

        const button = document.createElement("button");
        button.id = CONFIG.buttonId;
        button.type = "button";
        button.title = provider.buttonTitle;
        button.classList.add(provider.buttonClass);

        button.innerHTML = `
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path
          fill="currentColor"
          d="M6 2h9l5 5v15H6V2Zm8 1.5V8h4.5L14 3.5ZM8 11v2h8v-2H8Zm0 4v2h8v-2H8Z"
        />
      </svg>
      <span>${escapeHtml(provider.buttonLabel)}</span>
    `;

        button.addEventListener("click", handleExportButtonClick);
        document.body.appendChild(button);
    }

    async function handleExportButtonClick() {
        try {
            await waitForMessageRoots();

            await primeChatGptMessageTimestampsForCurrentConversation();

            const conversation = parseCurrentConversation();
            const exportHtml = buildExportDocument(conversation, {
                includeLocalRuntime: false,
            });

            openExportWindow(exportHtml, conversation);
        } catch (error) {
            alert(error.message || String(error));
        }
    }

    /**********************************************************************
     * Stage 2: Parsing
     **********************************************************************/

    function sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }

    async function waitForMessageRoots() {
        for (let attempt = 0; attempt < CONFIG.parserMaxAttempts; attempt++) {
            const provider = getProvider();
            const doc = provider.getRootDocument();
            const threadRoot = provider.getThreadRoot(doc);
            const roots = provider.findMessageRoots(threadRoot);

            if (roots.length > 0) return;

            await sleep(CONFIG.parserRetryDelayMs);
        }

        throw new Error(
            `Could not find message nodes for ${getProvider().name}. Make sure the conversation messages are visible on screen, then try again.`,
        );
    }

    function parseCurrentConversation() {
        const provider = getProvider();
        const doc = provider.getRootDocument();
        const threadRoot = provider.getThreadRoot(doc);

        const roots = provider.findMessageRoots(threadRoot);

        if (!roots.length) {
            throw new Error("No message nodes found.");
        }

        const messages = roots
            .map((root, index) => parseMessageRoot(root, index, provider))
            .filter(Boolean);

        const dedupedMessages = deduplicateMessages(messages);

        if (!dedupedMessages.length) {
            throw new Error(
                "Message containers were found, but they became empty after cleanup.",
            );
        }

        return {
            providerKey: provider.key,
            providerName: provider.name,
            title: provider.getConversationTitle(doc),
            exportedAt: new Date().toLocaleString(),
            messages: dedupedMessages,
        };
    }

    function parseMessageRoot(root, index, provider) {
        const timestamp = extractMessageTimestamp(root, provider);
        const cleanFragment = extractCleanMessageFragment(root, provider);
        const html = cleanFragment.innerHTML;
        const markdown = domFragmentToMarkdown(cleanFragment).trim();
        const plainText = htmlToPlainText(html);

        if (!plainText && !/<img|<table|<pre|katex/i.test(html)) {
            return null;
        }

        return {
            role: provider.inferMessageRole(root, index),
            timestamp,
            html,
            markdown: markdown || plainText,
        };
    }

    /**********************************************************************
     * Stage 2.5: Timestamps
     **********************************************************************/

    function extractMessageTimestamp(root, provider = getProvider()) {
        if (provider.key === "chatGPT") {
            const messageId = getMessageIdFromRoot(root);

            if (!messageId) return "";

            return CHATGPT_MESSAGE_TIMESTAMPS.get(messageId) || "";
        }

        if (typeof provider.extractMessageTimestamp === "function") {
            return provider.extractMessageTimestamp(root) || "";
        }

        return "";
    }

    function getMessageIdFromRoot(root) {
        return (
            root.getAttribute("data-message-id") ||
            root
                .querySelector("[data-message-id]")
                ?.getAttribute("data-message-id") ||
            ""
        );
    }

    function installChatGptConversationResponseWatcher() {
        if (getProvider().key !== "chatGPT") return;
        if (window.__tmGptCleanPdfTimestampFetchPatched) return;
        if (typeof window.fetch !== "function") return;

        window.__tmGptCleanPdfTimestampFetchPatched = true;

        const originalFetch = window.fetch.bind(window);

        window.fetch = async (...args) => {
            const response = await originalFetch(...args);

            try {
                const url = getFetchResponseUrl(args[0], response);

                if (isChatGptConversationApiUrl(url)) {
                    response
                        .clone()
                        .json()
                        .then(cacheChatGptMessageTimestampsFromConversationJson)
                        .catch(() => {});
                }
            } catch {
                // Never let timestamp extraction interfere with ChatGPT.
            }

            return response;
        };
    }

    function getFetchResponseUrl(input, response) {
        if (response?.url) return response.url;

        if (typeof input === "string") return input;

        if (input instanceof URL) return input.href;

        if (input && typeof input.url === "string") return input.url;

        return "";
    }

    function isChatGptConversationApiUrl(url) {
        try {
            const parsed = new URL(url, location.origin);

            if (
                parsed.hostname !== "chatgpt.com" &&
                parsed.hostname !== "chat.openai.com"
            ) {
                return false;
            }

            return /^\/backend-api\/conversation\/[0-9a-fA-F-]{36}\/?$/.test(
                parsed.pathname,
            );
        } catch {
            return false;
        }
    }

    async function primeChatGptMessageTimestampsForCurrentConversation() {
        if (getProvider().key !== "chatGPT") return;

        const conversationId = getChatGptConversationIdFromUrl();

        if (!conversationId) return;

        if (CHATGPT_CONVERSATION_FETCHES.has(conversationId)) {
            await CHATGPT_CONVERSATION_FETCHES.get(conversationId);
            return;
        }

        const promise = fetchChatGptConversationJson(conversationId)
            .then(cacheChatGptMessageTimestampsFromConversationJson)
            .catch(() => {
                // Internal endpoint can change. Export should continue without timestamps.
            });

        CHATGPT_CONVERSATION_FETCHES.set(conversationId, promise);

        await promise;
    }

    function getChatGptConversationIdFromUrl() {
        const match = location.pathname.match(
            /\/c\/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:\/|$)/,
        );

        return match?.[1] || "";
    }

    async function fetchChatGptConversationJson(conversationId) {
        const response = await fetch(
            `/backend-api/conversation/${conversationId}`,
            {
                method: "GET",
                credentials: "include",
                headers: {
                    accept: "application/json",
                },
            },
        );

        if (!response.ok) {
            throw new Error(
                `Conversation timestamp fetch failed: ${response.status}`,
            );
        }

        return response.json();
    }

    function cacheChatGptMessageTimestampsFromConversationJson(data) {
        const mapping = data?.mapping;

        if (!mapping || typeof mapping !== "object") return;

        for (const node of Object.values(mapping)) {
            const message = node?.message;

            if (!message) continue;

            const messageId = message.id || node.id;
            const timestamp = formatUnixTimestamp(
                message.create_time ?? message.update_time,
            );

            if (messageId && timestamp) {
                CHATGPT_MESSAGE_TIMESTAMPS.set(messageId, timestamp);
            }
        }
    }

    function formatUnixTimestamp(value) {
        if (value === null || value === undefined || value === "") return "";

        const numeric = Number(value);

        if (!Number.isFinite(numeric)) return "";

        const ms = numeric < 1e10 ? numeric * 1000 : numeric;
        const date = new Date(ms);

        if (Number.isNaN(date.getTime())) return "";

        return date.toLocaleString();
    }

    function findClaudeTimestampText(root) {
        const candidates = Array.from(
            root.querySelectorAll("time, [datetime], span, div"),
        );

        for (const el of candidates) {
            const attrValue =
                el.getAttribute("datetime") || el.getAttribute("title") || "";

            if (isClaudeTimestampText(attrValue)) {
                return attrValue.trim();
            }

            const text = getCleanText(el);

            if (isClaudeTimestampText(text)) {
                return text;
            }
        }

        return "";
    }

    function isClaudeTimestampText(value) {
        const text = String(value || "")
            .replace(/\s+/g, " ")
            .trim();

        if (!text || text.length > 48) return false;

        return (
            /^(today|yesterday)$/i.test(text) ||
            /^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+\d{1,2}(?:,\s*\d{4})?$/i.test(
                text,
            ) ||
            /^\d{1,2}:\d{2}(?:\s*[AP]M)?$/i.test(text)
        );
    }

    /**********************************************************************
     * Stage 3: Cleaning and normalization
     **********************************************************************/

    function extractCleanMessageFragment(root, provider = getProvider()) {
        const clone = root.cloneNode(true);

        removeChatUiBloat(clone);
        normalizeCodeBlocks(clone);

        const bestContentNode = findBestMessageBodyCandidate(clone, provider);

        const container = document.createElement("div");

        if (bestContentNode) {
            const cleanedCandidate = bestContentNode.cloneNode(true);
            removeChatUiBloat(cleanedCandidate);
            normalizeCodeBlocks(cleanedCandidate);

            if (getCleanText(cleanedCandidate).length > 0) {
                container.innerHTML = cleanedCandidate.innerHTML;
                return container;
            }
        }

        const text = getCleanText(clone);

        if (!text) {
            return container;
        }

        if (
            !clone.querySelector(
                "p, pre, code, ul, ol, table, blockquote, h1, h2, h3, h4",
            )
        ) {
            container.innerHTML = text
                .split(/\n{2,}/)
                .map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`)
                .join("\n");

            return container;
        }

        container.innerHTML = clone.innerHTML;
        return container;
    }

    function findBestMessageBodyCandidate(root, provider = getProvider()) {
        if (typeof provider.findBestMessageBodyCandidate === "function") {
            const providerCandidate =
                provider.findBestMessageBodyCandidate(root);

            if (providerCandidate) return providerCandidate;
        }

        const candidates = Array.from(
            root.querySelectorAll(
                ".markdown, .prose, [class*='markdown'], [class*='prose'], div",
            ),
        ).filter((el) => {
            const text = getCleanText(el);
            const hasRichContent = el.querySelector(
                "p, pre, code, ul, ol, table, blockquote, h1, h2, h3, h4, img, .katex",
            );

            return text.length > 0 && hasRichContent;
        });

        if (!candidates.length) return null;

        candidates.sort(
            (a, b) => getCleanText(b).length - getCleanText(a).length,
        );

        return candidates[0];
    }

    function removeChatUiBloat(root) {
        const junkSelectors = [
            "script",
            "style",
            "template",
            "button",
            "textarea",
            "input",
            "form",
            "nav",
            "aside",
            "header",
            "footer",
            "iframe",
            "lt-toolbar",
            "[hidden]",
            "[aria-hidden='true']",
            "[role='status']",
            "[aria-live]",
            ".sr-only",
            ".ProseMirror",
            ".intercom-lightweight-app",
            "[data-skip-to-content]",
            "[data-testid='conversation-turn-action-button']",
            "[data-testid='composer']",
            "[data-testid='composer-footer-actions']",
            "[data-testid='thread-header-right-actions-container']",
            "[data-testid='action-bar-copy']",
            "[data-testid='action-bar-retry']",
            "[data-testid='chat-menu-trigger']",
            "[data-testid='pin-sidebar-toggle']",
            "[data-testid='user-menu-button']",
            "[data-testid='model-selector-dropdown']",
            "[data-chat-input-container='true']",
            "[data-disclaimer='true']",
            "[aria-label='Copy']",
            "[aria-label='Copy to clipboard']",
            "[aria-label='Good response']",
            "[aria-label='Bad response']",
            "[aria-label='Give positive feedback']",
            "[aria-label='Give negative feedback']",
            "[aria-label='Read aloud']",
            "[aria-label='Share']",
            "[aria-label='Open conversation options']",
            "[aria-label='Open sidebar']",
            "[aria-label='Close sidebar']",
            "[aria-label='Retry']",
            "[aria-label='Edit']",
        ];

        root.querySelectorAll(junkSelectors.join(",")).forEach((el) =>
            el.remove(),
        );

        removeCodeLanguageLabels(root);
        removeEmptyLayoutWrappers(root);
        stripChatLayoutAttributes(root);

        return root;
    }

    function removeCodeLanguageLabels(root) {
        root.querySelectorAll("pre").forEach((pre) => {
            let sibling = pre.previousElementSibling;

            while (sibling && isCodeLanguageLabelNode(sibling)) {
                const previous = sibling.previousElementSibling;
                sibling.remove();
                sibling = previous;
            }
        });
    }

    function isCodeLanguageLabelNode(el) {
        if (el.querySelector("pre, code, p, ul, ol, table, blockquote")) {
            return false;
        }

        return isCodeLanguageLabel(getCleanText(el));
    }

    function removeEmptyLayoutWrappers(root) {
        const wrappers = Array.from(
            root.querySelectorAll("div, span"),
        ).reverse();

        for (const el of wrappers) {
            const text = getCleanText(el);
            const hasUsefulChild = el.querySelector(
                "p, pre, code, ul, ol, li, table, thead, tbody, tr, td, th, blockquote, h1, h2, h3, h4, img, svg, canvas, .katex",
            );

            if (!text && !hasUsefulChild) {
                el.remove();
            }
        }
    }

    function stripChatLayoutAttributes(root) {
        root.querySelectorAll("*").forEach((el) => {
            el.removeAttribute("class");
            el.removeAttribute("style");
            el.removeAttribute("data-testid");
            el.removeAttribute("data-state");
            el.removeAttribute("data-message-author-role");
            el.removeAttribute("data-message-id");
            el.removeAttribute("data-start");
            el.removeAttribute("data-end");
            el.removeAttribute("data-test-render-count");
            el.removeAttribute("data-is-streaming");
            el.removeAttribute("data-user-message-bubble");
        });
    }

    function normalizeCodeBlocks(root) {
        root.querySelectorAll("pre").forEach((pre) => {
            const text = extractCodeBlockText(pre);

            pre.textContent = text;
            pre.setAttribute("data-export-code", text);
        });

        root.querySelectorAll("code").forEach((code) => {
            code.textContent = code.textContent;
        });

        return root;
    }

    function extractCodeBlockText(pre) {
        const code = pre.querySelector("code");
        const source = code || pre;
        const renderedText = source.innerText || "";
        const rawText = source.textContent || "";
        const text =
            renderedText.length >= rawText.length ? renderedText : rawText;

        return normalizeCodeText(stripCodeLanguageArtifact(text));
    }

    function stripCodeLanguageArtifact(text) {
        const value = String(text || "").replace(/\r\n/g, "\n");
        const lines = value.split("\n");
        const firstLine = (lines[0] || "").trim();

        if (lines.length > 1 && isCodeLanguageLabel(firstLine)) {
            return lines.slice(1).join("\n");
        }

        const lowerValue = value.toLowerCase();
        const labels = getCodeLanguageLabels().sort(
            (a, b) => b.length - a.length,
        );

        for (const label of labels) {
            if (!lowerValue.startsWith(label)) continue;

            const rest = value.slice(label.length);

            if (looksLikeCodeStart(rest)) return rest;
        }

        return value;
    }

    function looksLikeCodeStart(value) {
        return /^(?:<[A-Za-z!/?]|const|let|var|function|class|import|export|return|if|for|while|document|window|#|\.[A-Za-z_-])/.test(
            value,
        );
    }

    function isCodeLanguageLabel(value) {
        const label = String(value || "")
            .trim()
            .toLowerCase();

        return getCodeLanguageLabels().includes(label);
    }

    function getCodeLanguageLabels() {
        return [
            "bash",
            "c",
            "c++",
            "cpp",
            "c#",
            "css",
            "go",
            "html",
            "java",
            "javascript",
            "js",
            "json",
            "jsx",
            "kotlin",
            "markdown",
            "md",
            "php",
            "python",
            "py",
            "ruby",
            "rust",
            "scss",
            "shell",
            "sh",
            "sql",
            "swift",
            "tsx",
            "ts",
            "typescript",
            "xml",
            "yaml",
            "yml",
        ];
    }

    function normalizeCodeText(text) {
        return String(text || "")
            .replace(/\r\n/g, "\n")
            .replace(/\u00a0/g, " ")
            .replace(/\n{4,}/g, "\n\n");
    }

    /**********************************************************************
     * Stage 4: Markdown conversion for copy buttons
     **********************************************************************/

    function domFragmentToMarkdown(root) {
        return Array.from(root.childNodes)
            .map((node) => nodeToMarkdown(node, { depth: 0, listLevel: 0 }))
            .join("")
            .replace(/\n{4,}/g, "\n\n\n")
            .trim();
    }

    function nodeToMarkdown(node, ctx) {
        if (node.nodeType === Node.TEXT_NODE) {
            return normalizeMarkdownText(node.textContent);
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
            return "";
        }

        const tag = node.tagName.toLowerCase();

        switch (tag) {
            case "h1":
                return `# ${childrenInlineMarkdown(node).trim()}\n\n`;
            case "h2":
                return `## ${childrenInlineMarkdown(node).trim()}\n\n`;
            case "h3":
                return `### ${childrenInlineMarkdown(node).trim()}\n\n`;
            case "h4":
                return `#### ${childrenInlineMarkdown(node).trim()}\n\n`;
            case "h5":
                return `##### ${childrenInlineMarkdown(node).trim()}\n\n`;
            case "h6":
                return `###### ${childrenInlineMarkdown(node).trim()}\n\n`;
            case "p":
                return `${childrenInlineMarkdown(node).trim()}\n\n`;
            case "br":
                return "\n";
            case "strong":
            case "b":
                return `**${childrenInlineMarkdown(node).trim()}**`;
            case "em":
            case "i":
                return `*${childrenInlineMarkdown(node).trim()}*`;
            case "code":
                if (node.closest("pre")) return node.textContent || "";
                return inlineCodeMarkdown(node.textContent || "");
            case "pre":
                return codeBlockMarkdown(node);
            case "blockquote":
                return blockquoteMarkdown(node, ctx);
            case "ul":
                return listMarkdown(node, ctx, false);
            case "ol":
                return listMarkdown(node, ctx, true);
            case "li":
                return `${childrenBlockMarkdown(node, ctx).trim()}\n`;
            case "a":
                return linkMarkdown(node);
            case "img":
                return imageMarkdown(node);
            case "table":
                return tableMarkdown(node);
            case "thead":
            case "tbody":
            case "tr":
            case "th":
            case "td":
                return childrenBlockMarkdown(node, ctx);
            case "hr":
                return "\n---\n\n";
            default:
                if (isBlockElement(tag)) {
                    return `${childrenBlockMarkdown(node, ctx).trim()}\n\n`;
                }

                return childrenInlineMarkdown(node);
        }
    }

    function childrenBlockMarkdown(node, ctx) {
        return Array.from(node.childNodes)
            .map((child) => nodeToMarkdown(child, ctx))
            .join("");
    }

    function childrenInlineMarkdown(node) {
        return Array.from(node.childNodes)
            .map((child) => {
                if (child.nodeType === Node.TEXT_NODE) {
                    return normalizeMarkdownText(child.textContent);
                }

                if (child.nodeType !== Node.ELEMENT_NODE) {
                    return "";
                }

                const tag = child.tagName.toLowerCase();

                if (tag === "br") return "\n";
                if (tag === "code" && !child.closest("pre"))
                    return inlineCodeMarkdown(child.textContent || "");
                if (tag === "strong" || tag === "b")
                    return `**${childrenInlineMarkdown(child).trim()}**`;
                if (tag === "em" || tag === "i")
                    return `*${childrenInlineMarkdown(child).trim()}*`;
                if (tag === "a") return linkMarkdown(child);
                if (tag === "img") return imageMarkdown(child);

                return childrenInlineMarkdown(child);
            })
            .join("")
            .replace(/[ \t]+\n/g, "\n");
    }

    function normalizeMarkdownText(text) {
        return String(text || "").replace(/\u00a0/g, " ");
    }

    function inlineCodeMarkdown(text) {
        const value = String(text || "");
        const fence = value.includes("`") ? "``" : "`";
        return `${fence}${value}${fence}`;
    }

    function codeBlockMarkdown(pre) {
        const text = getCodeTextForCopy(pre);
        return `\n\`\`\`\n${text.replace(/\n+$/g, "")}\n\`\`\`\n\n`;
    }

    function getCodeTextForCopy(pre) {
        return normalizeCodeText(
            pre.getAttribute("data-export-code") ||
                pre.innerText ||
                pre.textContent ||
                "",
        );
    }

    function blockquoteMarkdown(node, ctx) {
        const inner = childrenBlockMarkdown(node, ctx).trim();
        const quoted = inner
            .split("\n")
            .map((line) => `> ${line}`)
            .join("\n");

        return `${quoted}\n\n`;
    }

    function listMarkdown(node, ctx, ordered) {
        const items = Array.from(node.children).filter(
            (child) => child.tagName?.toLowerCase() === "li",
        );
        const indent = "  ".repeat(ctx.listLevel || 0);

        const body = items
            .map((li, index) => {
                const marker = ordered ? `${index + 1}.` : "-";
                const childCtx = {
                    ...ctx,
                    listLevel: (ctx.listLevel || 0) + 1,
                };
                const content = childrenBlockMarkdown(li, childCtx).trim();
                const lines = content.split("\n");

                return `${indent}${marker} ${lines[0] || ""}${
                    lines.length > 1
                        ? "\n" +
                          lines
                              .slice(1)
                              .map((line) => `${indent}   ${line}`)
                              .join("\n")
                        : ""
                }`;
            })
            .join("\n");

        return `${body}\n\n`;
    }

    function linkMarkdown(node) {
        const href = node.getAttribute("href") || "";
        const text = childrenInlineMarkdown(node).trim() || href;

        if (!href) return text;

        return `[${text}](${href})`;
    }

    function imageMarkdown(node) {
        const alt = node.getAttribute("alt") || "";
        const src = node.getAttribute("src") || "";

        if (!src) return "";

        return `![${alt}](${src})`;
    }

    function tableMarkdown(table) {
        const rows = Array.from(table.querySelectorAll("tr")).map((tr) => {
            return Array.from(tr.children).map((cell) => {
                return childrenInlineMarkdown(cell)
                    .replace(/\|/g, "\\|")
                    .replace(/\n+/g, " ")
                    .trim();
            });
        });

        if (!rows.length) return "";

        const columnCount = Math.max(...rows.map((row) => row.length));
        const normalizedRows = rows.map((row) => {
            const clone = row.slice();

            while (clone.length < columnCount) clone.push("");

            return clone;
        });

        const header = normalizedRows[0];
        const separator = Array.from({ length: columnCount }, () => "---");
        const bodyRows = normalizedRows.slice(1);

        return (
            [
                `| ${header.join(" | ")} |`,
                `| ${separator.join(" | ")} |`,
                ...bodyRows.map((row) => `| ${row.join(" | ")} |`),
            ].join("\n") + "\n\n"
        );
    }

    function isBlockElement(tag) {
        return [
            "article",
            "section",
            "div",
            "main",
            "header",
            "footer",
            "aside",
            "nav",
            "figure",
            "figcaption",
        ].includes(tag);
    }

    /**********************************************************************
     * Stage 5: Export document building
     **********************************************************************/

    function buildExportDocument(conversation, options = {}) {
        const includeLocalRuntime = Boolean(options.includeLocalRuntime);

        const tocHtml = buildTableOfContentsHtml(conversation.messages);

        const messageHtml = conversation.messages
            .map((message, index) => buildMessageHtml(message, index))
            .join("\n");

        const exportData = {
            title: conversation.title,
            providerKey: conversation.providerKey,
            providerName: conversation.providerName,
            exportedAt: conversation.exportedAt,
            messages: conversation.messages.map((message) => ({
                role: message.role,
                timestamp: message.timestamp,
                html: message.html,
                markdown: message.markdown,
            })),
        };

        return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>${escapeHtml(conversation.title)}</title>
  <style>
    ${buildExportCss()}
  </style>
</head>
<body>
  <main class="page">
    <div class="export-actions no-print" aria-label="Export actions">
      <button type="button" data-action="print">Print / Save PDF</button>
      <button type="button" data-action="save-html">Save HTML</button>
    </div>

    <header class="doc-header">
      <h1 class="doc-title">${escapeHtml(conversation.title)}</h1>
      <div class="doc-meta">
        Exported from ${escapeHtml(conversation.providerName)} · ${escapeHtml(conversation.exportedAt)} · ${conversation.messages.length} messages
      </div>
    </header>

    ${tocHtml}

    ${messageHtml}
  </main>

  ${
      includeLocalRuntime
          ? `<script type="application/json" id="export-data">${escapeHtml(JSON.stringify(exportData))}</script>
${buildLocalHtmlRuntimeScript()}`
          : ""
  }
</body>
</html>`;
    }

    function buildTableOfContentsHtml(messages) {
        const items = messages
            .map((message, index) => {
                const id = getMessageAnchorId(index);
                const preview = getMessagePreview(
                    message.markdown || message.html,
                    CONFIG.tocPreviewMaxLength,
                );
                const roleClass = getRoleClass(message.role);
                const separator =
                    index > 0 && roleClass === "user"
                        ? `
          <tr class="toc-separator" aria-hidden="true">
            <td colspan="3"></td>
          </tr>`
                        : "";

                return `${separator}
          <tr class="toc-row ${roleClass}">
            <td class="toc-id"><a href="#${id}">#${index + 1}</a></td>
            <td class="toc-author"><a href="#${id}">${escapeHtml(message.role)}</a></td>
            <td class="toc-msg"><a href="#${id}">${escapeHtml(preview)}</a></td>
          </tr>
        `;
            })
            .join("\n");

        return `
      <nav class="toc" aria-label="Table of contents">
        <h2 class="toc-title" id="table-of-contents">Table of contents</h2>

        <table class="toc-table">
          <colgroup>
            <col class="toc-col-id">
            <col class="toc-col-author">
            <col class="toc-col-message">
          </colgroup>
          <thead>
            <tr>
              <th scope="col">ID</th>
              <th scope="col">Author</th>
              <th scope="col">Message</th>
            </tr>
          </thead>
          <tbody>
            ${items}
          </tbody>
        </table>
      </nav>
    `;
    }

    function buildMessageHtml(message, index) {
        const roleClass = getRoleClass(message.role);
        const id = getMessageAnchorId(index);

        return `
      <section class="turn ${roleClass}" aria-labelledby="${id}" data-message-index="${index}">
        <h2 class="turn-heading" id="${id}">
          <span class="role">${escapeHtml(message.role)}</span>
          <a class="turn-number" href="#${id}">#${index + 1}</a>
          ${
              message.timestamp
                  ? `<span class="turn-time">${escapeHtml(message.timestamp)}</span>`
                  : ""
          }
          <button type="button" class="copy-message-btn no-print" data-copy-message="${index}">Copy message</button>
        </h2>
        <article class="bubble">
          ${message.html}
        </article>
      </section>
    `;
    }

    function getMessageAnchorId(index) {
        return `message-${index + 1}`;
    }

    function getMessagePreview(source, maxLength) {
        const text = String(source || "")
            .replace(/```[\s\S]*?```/g, "[code]")
            .replace(/[#>*_`~\[\]()|]/g, "")
            .replace(/\s+/g, " ")
            .trim();

        if (text.length <= maxLength) return text;

        return `${text.slice(0, maxLength).trim()}…`;
    }

    function getRoleClass(role) {
        if (role === "User") return "user";
        if (role === "Tool") return "tool";
        return "assistant";
    }

    /**********************************************************************
     * Stage 6: Export document CSS
     **********************************************************************/

    function buildExportCss() {
        return `
      @page {
        size: auto;
        margin: 12mm;
      }

      :root {
        --text: #111111;
        --muted: #666666;
        --border: #d9d9d9;
        --soft-border: #e8e8e8;
        --page-bg: #ffffff;
        --assistant-bg: #ffffff;
        --assistant-border: #d8d8d8;
        --user-bg: #f2f2f2;
        --user-border: #d4d4d4;
        --code-bg: #f6f6f6;
        --inline-code-bg: #eeeeee;
        --tool-bg: #fff8e8;
        --tool-border: #ead9aa;
        --button-bg: #222222;
        --button-text: #ffffff;
      }

      *,
      *::before,
      *::after {
        box-sizing: border-box;
      }

      html,
      body {
        width: 100%;
        max-width: 100%;
        overflow-x: hidden;
        background: var(--page-bg);
        color: var(--text);
      }

      body {
        margin: 0;
        font-family: Arial, sans-serif;
        font-size: 12.5px;
        line-height: 1.42;
      }

      .page {
        width: 100%;
        max-width: 820px;
        margin: 0 auto;
        overflow-x: hidden;
      }

      .turn,
      .bubble,
      .bubble *,
      .toc,
      .toc * {
        max-width: 100%;
        min-width: 0;
      }

      .user,
      .assistant,
      .tool {
        max-width: 100%;
        min-width: 0;
      }

      .bubble {
        overflow: hidden;
      }

      p,
      li,
      blockquote,
      div,
      span,
      a {
        max-width: 100%;
        overflow-wrap: anywhere;
        word-break: break-word;
      }

      .export-actions {
        position: sticky;
        top: 0;
        z-index: 10;

        display: flex;
        justify-content: flex-end;
        gap: 8px;

        padding: 8px 0;
        margin-bottom: 8px;

        background: rgba(255, 255, 255, 0.92);
        backdrop-filter: blur(4px);
      }

      .export-actions button,
      .copy-message-btn,
      .copy-code-btn {
        border: 1px solid #d0d0d0;
        border-radius: 999px;
        background: #ffffff;
        color: #111111;
        font-family: Arial, sans-serif;
        font-size: 10.5px;
        line-height: 1;
        padding: 5px 8px;
        cursor: pointer;
      }

      .export-actions button {
        background: var(--button-bg);
        color: var(--button-text);
        border-color: var(--button-bg);
        font-size: 11.5px;
        padding: 7px 10px;
      }

      .copy-message-btn:hover,
      .copy-code-btn:hover {
        background: #f3f3f3;
      }

      .doc-header {
        border-bottom: 2px solid #222222;
        margin-bottom: 14px;
        padding-bottom: 10px;
      }

      .doc-title {
        margin: 0 0 5px;
        font-size: 20px;
        line-height: 1.2;
        font-weight: 700;
      }

      .doc-meta {
        color: var(--muted);
        font-size: 10.5px;
      }

      .toc {
        margin: 0 0 18px;
        padding: 11px 13px;
        border: 1px solid var(--border);
        border-radius: 10px;
        background: #fafafa;
      }

      .toc-title {
        margin: 0 0 8px;
        font-size: 15px;
        line-height: 1.2;
        font-weight: 700;
      }

      .toc-table {
        width: 100%;
        table-layout: fixed;
        border-collapse: collapse;
        font-size: 10.8px;
        line-height: 1.35;
      }

      .toc-table th {
        padding: 0 8px 6px 0;
        border-bottom: 1px solid #e6e6e6;
        color: #777777;
        font-size: 9.5px;
        font-weight: 700;
        letter-spacing: 0.03em;
        text-align: left;
        text-transform: uppercase;
      }

      .toc-table td {
        padding: 4px 8px 4px 0;
        border-top: 1px solid #eeeeee;
        vertical-align: top;
      }

      .toc-table tbody tr:first-child td {
        border-top: 0;
      }

      .toc-separator td {
        padding: 9px 0 7px;
        border-top: 0;
      }

      .toc-separator td::before {
        content: "";
        display: block;
        border-top: 2px solid #d5d5d5;
      }

      .toc-separator + .toc-row td {
        border-top: 0;
      }

      .toc-table a {
        display: block;
        min-width: 0;
        overflow: hidden;
        color: #111111;
        text-decoration: none;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .toc-col-id {
        width: 42px;
      }

      .toc-col-author {
        width: 82px;
      }

      .toc-author {
        font-weight: 700;
      }

      .toc-id a {
        color: #555555;
        font-variant-numeric: tabular-nums;
      }

      .toc-msg a {
        color: #333333;
      }

      .turn {
        margin: 0 0 12px;
        break-inside: auto;
        page-break-inside: auto;
      }

      .turn-heading {
        display: flex;
        align-items: center;
        gap: 8px;

        margin: 0 0 4px;
        font-size: 10.5px;
        line-height: 1.2;
        font-weight: 400;
        color: var(--muted);

        break-after: avoid-page;
        page-break-after: avoid;
      }

      .role {
        display: inline-block;
        font-weight: 700;
        letter-spacing: 0.01em;
        color: #222222;
      }

      .turn-number {
        color: #777777;
        text-decoration: none;
        font-variant-numeric: tabular-nums;
      }

      .turn-time {
        color: #777777;
        font-variant-numeric: tabular-nums;
      }

      .copy-message-btn {
        margin-left: auto;
      }

      .user .copy-message-btn {
        margin-left: 0;
      }

      .bubble {
        padding: 10px 12px;
        border-radius: 10px;
        border: 1px solid var(--assistant-border);
        background: var(--assistant-bg);
        break-inside: auto;
        page-break-inside: auto;
      }

      .assistant {
        padding-right: 4%;
      }

      .assistant .bubble {
        border-left: 4px solid #9a9a9a;
      }

      .assistant .role::before {
        content: "● ";
      }

      .user {
        padding-left: 8%;
      }

      .user .turn-heading {
        justify-content: flex-end;
      }

      .user .bubble {
        background: var(--user-bg);
        border-color: var(--user-border);
        border-right: 4px solid #555555;
      }

      .user .role::before {
        content: "◆ ";
      }

      .tool .bubble {
        background: var(--tool-bg);
        border-color: var(--tool-border);
        border-left: 4px solid #c79a2d;
      }

      .tool .role::before {
        content: "■ ";
      }

      .bubble > *:first-child,
      .bubble div > *:first-child {
        margin-top: 0 !important;
      }

      .bubble > *:last-child,
      .bubble div > *:last-child {
        margin-bottom: 0 !important;
      }

      p {
        margin: 0.3em 0 0.52em;
      }

      ul,
      ol {
        margin: 0.35em 0 0.55em;
        padding-left: 1.4em;
      }

      li {
        margin: 0.14em 0;
      }

      h1,
      h2,
      h3,
      h4 {
        margin: 0.75em 0 0.35em;
        line-height: 1.2;
        break-after: avoid-page;
        page-break-after: avoid;
      }

      h1 { font-size: 18px; }
      h2 { font-size: 16px; }
      h3 { font-size: 14px; }
      h4 { font-size: 13px; }

      blockquote {
        border-left: 3px solid #bbbbbb;
        margin: 0.65em 0;
        padding-left: 0.85em;
        color: #333333;
      }

      hr {
        border: 0;
        border-top: 1px solid var(--soft-border);
        margin: 0.8em 0;
      }

      pre,
      code {
        font-family: Menlo, Consolas, Monaco, "Courier New", monospace;
        max-width: 100%;
      }

      .code-shell {
        position: relative;
        max-width: 100%;
      }

      .copy-code-btn {
        position: absolute;
        top: 6px;
        right: 6px;
        z-index: 2;
        background: rgba(255, 255, 255, 0.92);
      }

      pre {
        display: block;
        width: 100%;
        max-width: 100%;

        white-space: pre-wrap;
        overflow-wrap: anywhere;
        word-break: break-word;

        background: var(--code-bg);
        color: #111111;

        border: 1px solid #d7d7d7;
        border-radius: 7px;

        padding: 9px 10px;
        margin: 7px 0;

        font-size: 10px;
        line-height: 1.34;

        overflow-x: hidden;
        overflow-y: visible;

        break-inside: auto;
        page-break-inside: auto;
      }

      .code-shell pre {
        padding-top: 28px;
      }

      pre code {
        display: block;
        width: 100%;
        max-width: 100%;

        white-space: pre-wrap;
        overflow-wrap: anywhere;
        word-break: break-word;

        background: transparent;
        padding: 0;
        border-radius: 0;
        font-size: inherit;
      }

      code {
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        word-break: break-word;

        background: var(--inline-code-bg);
        color: #111111;

        border-radius: 4px;
        padding: 0.08em 0.25em;
        font-size: 0.92em;
      }

      table {
        width: 100%;
        max-width: 100%;
        table-layout: fixed;
        border-collapse: collapse;
        font-size: 11px;
        margin: 0.55em 0;
      }

      th,
      td {
        border: 1px solid #d8d8d8;
        padding: 4px 6px;
        vertical-align: top;

        white-space: normal;
        overflow-wrap: anywhere;
        word-break: break-word;
      }

      th {
        background: #f4f4f4;
        font-weight: 700;
      }

      img,
      svg,
      canvas {
        max-width: 100%;
        height: auto;
        break-inside: avoid-page;
        page-break-inside: avoid;
      }

      .katex,
      .katex * {
        font-family: KaTeX_Main, "Times New Roman", serif !important;
      }

      a {
        color: #000000;
        text-decoration: underline;
        text-decoration-thickness: 0.5px;
      }

      .turn-number,
      .toc-table a {
        text-decoration: none;
      }

      @media print {
        html,
        body {
          print-color-adjust: exact;
          -webkit-print-color-adjust: exact;
        }

        .no-print,
        .copy-message-btn,
        .copy-code-btn,
        .export-actions {
          display: none !important;
        }

        .doc-header {
          break-after: avoid-page;
          page-break-after: avoid;
        }

        .toc {
          break-inside: avoid-page;
          page-break-inside: avoid;
        }

        .toc-table th,
        .toc-table td {
          padding-right: 6px;
        }

        .toc-col-author {
          width: 64px;
        }

        .turn {
          margin-bottom: 10px;
        }

        .bubble {
          box-shadow: none;
        }

        .user {
          padding-left: 4%;
        }

        .assistant {
          padding-right: 2%;
        }

        .code-shell pre {
          padding-top: 9px;
        }
      }
    `;
    }

    /**********************************************************************
     * Stage 7: CSP-safe export window runtime
     **********************************************************************/

    function openExportWindow(html, conversation) {
        const exportWindow = window.open("", "_blank");

        if (!exportWindow) {
            throw new Error(
                "Popup blocked. Allow popups for this site, then try again.",
            );
        }

        exportWindow.document.open();
        exportWindow.document.write(html);
        exportWindow.document.close();

        initializeExportWindow(exportWindow, conversation);
    }

    function initializeExportWindow(exportWindow, conversation) {
        const exportData = {
            title: conversation.title,
            providerKey: conversation.providerKey,
            providerName: conversation.providerName,
            exportedAt: conversation.exportedAt,
            messages: conversation.messages.map((message) => ({
                role: message.role,
                timestamp: message.timestamp,
                html: message.html,
                markdown: message.markdown,
            })),
        };

        const run = () => {
            addCodeCopyButtonsToExportWindow(exportWindow);
            bindMessageCopyButtonsInExportWindow(exportWindow, exportData);
            bindExportActionsInExportWindow(
                exportWindow,
                exportData,
                conversation,
            );

            if (CONFIG.autoPrint) {
                exportWindow.setTimeout(() => {
                    exportWindow.print();
                }, CONFIG.autoPrintDelayMs);
            }
        };

        if (exportWindow.document.readyState === "complete") {
            run();
        } else {
            exportWindow.addEventListener("load", run, { once: true });
        }
    }

    function addCodeCopyButtonsToExportWindow(exportWindow) {
        const doc = exportWindow.document;

        doc.querySelectorAll("pre").forEach((pre, index) => {
            if (pre.closest(".code-shell")) return;

            const shell = doc.createElement("div");
            shell.className = "code-shell";

            const button = doc.createElement("button");
            button.type = "button";
            button.className = "copy-code-btn no-print";
            button.textContent = "Copy code";
            button.setAttribute("data-copy-code", String(index));

            pre.parentNode.insertBefore(shell, pre);
            shell.appendChild(button);
            shell.appendChild(pre);

            button.addEventListener("click", () => {
                copyTextFromExportWindow(
                    exportWindow,
                    getCodeTextForCopy(pre),
                    button,
                );
            });
        });
    }

    function bindMessageCopyButtonsInExportWindow(exportWindow, exportData) {
        const doc = exportWindow.document;

        doc.querySelectorAll("[data-copy-message]").forEach((button) => {
            button.addEventListener("click", () => {
                const index = Number(button.getAttribute("data-copy-message"));
                const message = exportData.messages[index];

                copyTextFromExportWindow(
                    exportWindow,
                    message?.markdown || "",
                    button,
                );
            });
        });
    }

    function bindExportActionsInExportWindow(
        exportWindow,
        exportData,
        conversation,
    ) {
        const doc = exportWindow.document;

        doc.querySelector("[data-action='print']")?.addEventListener(
            "click",
            () => {
                exportWindow.print();
            },
        );

        doc.querySelector("[data-action='save-html']")?.addEventListener(
            "click",
            () => {
                saveExportWindowAsHtml(exportWindow, exportData, conversation);
            },
        );
    }

    async function copyTextFromExportWindow(exportWindow, text, button) {
        try {
            await exportWindow.navigator.clipboard.writeText(text || "");
            flashExportButton(exportWindow, button, "Copied");
        } catch {
            fallbackCopyTextFromExportWindow(exportWindow, text || "");
            flashExportButton(exportWindow, button, "Copied");
        }
    }

    function fallbackCopyTextFromExportWindow(exportWindow, text) {
        const doc = exportWindow.document;

        const textarea = doc.createElement("textarea");
        textarea.value = text;
        textarea.setAttribute("readonly", "");
        textarea.style.position = "fixed";
        textarea.style.left = "-9999px";
        textarea.style.top = "-9999px";

        doc.body.appendChild(textarea);
        textarea.select();

        doc.execCommand("copy");
        textarea.remove();
    }

    function flashExportButton(exportWindow, button, label) {
        if (!button) return;

        const old = button.textContent;
        button.textContent = label;

        exportWindow.setTimeout(() => {
            button.textContent = old;
        }, 1000);
    }

    function saveExportWindowAsHtml(exportWindow, exportData, conversation) {
        const localHtml = buildExportDocument(conversation, {
            includeLocalRuntime: true,
        });
        const blob = new Blob([localHtml], { type: "text/html;charset=utf-8" });
        const url = URL.createObjectURL(blob);

        const safeTitle = String(exportData.title || "gpt-export")
            .replace(/[\\/:*?"<>|]+/g, "-")
            .replace(/\s+/g, " ")
            .trim()
            .slice(0, 120);

        const link = exportWindow.document.createElement("a");
        link.href = url;
        link.download = `${safeTitle}.html`;

        exportWindow.document.body.appendChild(link);
        link.click();
        link.remove();

        setTimeout(() => URL.revokeObjectURL(url), 1000);
    }

    /**********************************************************************
     * Stage 8: Local-file runtime script
     **********************************************************************/

    function buildLocalHtmlRuntimeScript() {
        return `<script>
(function () {
  "use strict";

  function getExportData() {
    var node = document.getElementById("export-data");

    if (!node) {
      return { title: "gpt-export", messages: [] };
    }

    try {
      return JSON.parse(node.textContent || "{}");
    } catch (error) {
      return { title: "gpt-export", messages: [] };
    }
  }

  function addCodeCopyButtons() {
    document.querySelectorAll("pre").forEach(function (pre, index) {
      if (pre.closest(".code-shell")) return;

      var shell = document.createElement("div");
      shell.className = "code-shell";

      var button = document.createElement("button");
      button.type = "button";
      button.className = "copy-code-btn no-print";
      button.textContent = "Copy code";
      button.setAttribute("data-copy-code", String(index));

      pre.parentNode.insertBefore(shell, pre);
      shell.appendChild(button);
      shell.appendChild(pre);

      button.addEventListener("click", function () {
        copyText(getCodeTextForCopy(pre), button);
      });
    });
  }

  function getCodeTextForCopy(pre) {
    return String(
      pre.getAttribute("data-export-code") ||
        pre.innerText ||
        pre.textContent ||
        "",
    )
      .replace(/\\r\\n/g, "\\n")
      .replace(/\\u00a0/g, " ");
  }

  function bindMessageCopyButtons(exportData) {
    document.querySelectorAll("[data-copy-message]").forEach(function (button) {
      button.addEventListener("click", function () {
        var index = Number(button.getAttribute("data-copy-message"));
        var message = exportData.messages[index];

        copyText((message && message.markdown) || "", button);
      });
    });
  }

  function bindExportActions(exportData) {
    var printButton = document.querySelector("[data-action='print']");
    var saveButton = document.querySelector("[data-action='save-html']");

    if (printButton) {
      printButton.addEventListener("click", function () {
        window.print();
      });
    }

    if (saveButton) {
      saveButton.addEventListener("click", function () {
        saveThisHtml(exportData);
      });
    }
  }

  async function copyText(text, button) {
    try {
      await navigator.clipboard.writeText(text || "");
      flashButton(button, "Copied");
    } catch (error) {
      fallbackCopyText(text || "");
      flashButton(button, "Copied");
    }
  }

  function fallbackCopyText(text) {
    var textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.left = "-9999px";
    textarea.style.top = "-9999px";

    document.body.appendChild(textarea);
    textarea.select();

    document.execCommand("copy");
    textarea.remove();
  }

  function flashButton(button, label) {
    if (!button) return;

    var old = button.textContent;
    button.textContent = label;

    setTimeout(function () {
      button.textContent = old;
    }, 1000);
  }

  function saveThisHtml(exportData) {
    var html = "<!doctype html>\\n" + document.documentElement.outerHTML;
    var blob = new Blob([html], { type: "text/html;charset=utf-8" });
    var url = URL.createObjectURL(blob);

    var safeTitle = String(exportData.title || "gpt-export")
      .replace(/[\\\\/:*?"<>|]+/g, "-")
      .replace(/\\s+/g, " ")
      .trim()
      .slice(0, 120);

    var link = document.createElement("a");
    link.href = url;
    link.download = safeTitle + ".html";

    document.body.appendChild(link);
    link.click();
    link.remove();

    setTimeout(function () {
      URL.revokeObjectURL(url);
    }, 1000);
  }

  function init() {
    var exportData = getExportData();

    addCodeCopyButtons();
    bindMessageCopyButtons(exportData);
    bindExportActions(exportData);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();
<\/script>`;
    }

    /**********************************************************************
     * Shared utilities
     **********************************************************************/

    function getCleanText(el) {
        return (el?.innerText || el?.textContent || "")
            .replace(/\u00a0/g, " ")
            .replace(/[ \t]+\n/g, "\n")
            .replace(/\n{3,}/g, "\n\n")
            .trim();
    }

    function getCleanTextFromSelector(root, selector) {
        return getCleanText(root.querySelector(selector) || {});
    }

    function htmlToPlainText(html) {
        return String(html || "")
            .replace(/<[^>]+>/g, " ")
            .replace(/\s+/g, " ")
            .trim();
    }

    function uniqueElements(elements) {
        return Array.from(new Set(elements)).filter(Boolean);
    }

    function removeNestedDuplicateElements(elements) {
        return elements.filter((root) => {
            return !elements.some(
                (other) => other !== root && other.contains(root),
            );
        });
    }

    function compareElementsInDocumentOrder(a, b) {
        if (a === b) return 0;

        return a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_PRECEDING
            ? 1
            : -1;
    }

    function hasExportableContent(root) {
        const text = getCleanText(root);
        const hasMediaOrStructuredContent = root.querySelector(
            "img, canvas, table, pre, code, .katex",
        );

        return text.length > 0 || Boolean(hasMediaOrStructuredContent);
    }

    function deduplicateMessages(messages) {
        const seen = new Set();
        const deduped = [];

        for (const message of messages) {
            const normalizedHtml = message.html.replace(/\s+/g, " ").trim();
            const key = `${message.role}:${normalizedHtml.slice(0, 2000)}`;

            if (seen.has(key)) continue;

            seen.add(key);
            deduped.push(message);
        }

        return deduped;
    }

    function escapeHtml(str) {
        return String(str)
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;");
    }

    /**********************************************************************
     * Entrypoint
     **********************************************************************/

    function init() {
        injectExportButtonStyles();
        createExportButton();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init, { once: true });
    } else {
        init();
    }

    const observer = new MutationObserver(() => {
        if (!document.getElementById(CONFIG.buttonId)) {
            createExportButton();
        }

        if (!document.getElementById(CONFIG.buttonStyleId)) {
            injectExportButtonStyles();
        }
    });

    const startObserver = () => {
        if (!document.documentElement) return;

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
        });
    };

    if (document.documentElement) {
        startObserver();
    } else {
        document.addEventListener("DOMContentLoaded", startObserver, {
            once: true,
        });
    }
})();
