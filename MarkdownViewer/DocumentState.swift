import Combine
import CoreGraphics
import Foundation
import Markdown

class DocumentState: ObservableObject {
    @Published var htmlContent: String = ""
    @Published var title: String = "Markdown Viewer"
    @Published var fileChanged: Bool = false
    @Published var outlineItems: [OutlineItem] = []
    @Published var reloadToken: UUID?
    @Published var zoomLevel: CGFloat = 1.0
    @Published var isShowingFindBar: Bool = false
    @Published var findQuery: String = ""
    @Published var findRequest: FindRequest?
    @Published var findFocusToken: UUID = UUID()
    var currentURL: URL?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var lastModificationDate: Date?
    private let recentFilesStore: RecentFilesStore

    init(recentFilesStore: RecentFilesStore = .shared) {
        self.recentFilesStore = recentFilesStore
    }

    deinit {
        stopMonitoring()
    }

    func loadFile(at url: URL) {
        currentURL = url
        fileChanged = false
        startMonitoring(url: url)
        recentFilesStore.add(url)
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let (frontMatter, content) = parseFrontMatter(markdown)
            let document = Document(parsing: content)
            var renderer = MarkdownRenderer()
            let rendered = renderer.render(document)
            let frontMatterHTML = renderFrontMatter(frontMatter)
            htmlContent = wrapInHTML(frontMatterHTML + rendered.html, title: url.lastPathComponent)
            title = url.lastPathComponent
            outlineItems = normalizedOutline(rendered.outline)
        } catch {
            htmlContent = wrapInHTML("<p>Error loading file: \(error.localizedDescription)</p>", title: "Error")
            title = "Error"
            outlineItems = []
        }
    }

    private func parseFrontMatter(_ markdown: String) -> ([(String, String)], String) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---" else { return ([], markdown) }

        var frontMatter: [(String, String)] = []
        var endIndex = 0

        for (index, line) in lines.dropFirst().enumerated() {
            if line == "---" {
                endIndex = index + 2
                break
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    frontMatter.append((key, value))
                }
            }
        }

        let content = lines.dropFirst(endIndex).joined(separator: "\n")
        return (frontMatter, content)
    }

    private func renderFrontMatter(_ frontMatter: [(String, String)]) -> String {
        guard !frontMatter.isEmpty else { return "" }

        var html = """
        <div class=\"front-matter\">
        <table class=\"front-matter-table\">
        """
        for (key, value) in frontMatter {
            let displayKey = key.replacingOccurrences(of: "_", with: " ").capitalized
            html += "<tr><td class=\"fm-key\">\(escapeHTML(displayKey))</td><td class=\"fm-value\">\(escapeHTML(value))</td></tr>\n"
        }
        html += "</table></div>\n"
        return html
    }

    private func normalizedOutline(_ items: [OutlineItem]) -> [OutlineItem] {
        let h1Count = items.filter { $0.level == 1 }.count
        guard h1Count == 1 else { return items }

        return items.compactMap { item in
            if item.level == 1 {
                return nil
            }
            return OutlineItem(title: item.title, level: max(1, item.level - 1), anchorID: item.anchorID)
        }
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func reload() {
        guard let url = currentURL else { return }
        reloadToken = UUID()
        loadFile(at: url)
    }

    func zoomIn() {
        zoomLevel = min(zoomLevel + 0.1, 3.0)
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel - 0.1, 0.5)
    }

    func resetZoom() {
        zoomLevel = 1.0
    }

    func showFindBar() {
        let wasShowing = isShowingFindBar
        isShowingFindBar = true
        findFocusToken = UUID()
        if !wasShowing {
            updateFindResults()
        }
    }

    func hideFindBar() {
        isShowingFindBar = false
        clearFindHighlights()
    }

    func updateFindResults() {
        requestFind(direction: .forward, reset: true)
    }

    func findNext() {
        requestFind(direction: .forward, reset: false)
    }

    func findPrevious() {
        requestFind(direction: .backward, reset: false)
    }

    private func startMonitoring(url: URL) {
        stopMonitoring()

        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        lastModificationDate = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        fileMonitor?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let newModDate = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            if newModDate != self.lastModificationDate {
                self.fileChanged = true
            }
        }

        fileMonitor?.setCancelHandler {
            close(fileDescriptor)
        }

        fileMonitor?.resume()
    }

    private func stopMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    private func requestFind(direction: FindDirection, reset: Bool) {
        let trimmed = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findRequest = FindRequest(query: "", direction: .forward, token: UUID(), reset: true)
            return
        }
        findRequest = FindRequest(query: trimmed, direction: direction, token: UUID(), reset: reset)
    }

    private func clearFindHighlights() {
        findRequest = FindRequest(query: "", direction: .forward, token: UUID(), reset: true)
    }

    private func wrapInHTML(_ body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset=\"UTF-8\">
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
            <title>\(title)</title>
            <link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css\" media=\"(prefers-color-scheme: light)\">
            <link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css\" media=\"(prefers-color-scheme: dark)\">
            <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js\"></script>
            <style>
                :root {
                    color-scheme: light dark;
                    --color-fg-default: #1f2328;
                    --color-fg-muted: #656d76;
                    --color-canvas-default: #ffffff;
                    --color-canvas-subtle: #f6f8fa;
                    --color-border-default: #d0d7de;
                    --color-border-muted: hsla(210,18%,87%,1);
                    --color-accent-fg: #0969da;
                    --color-danger-fg: #d1242f;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --color-fg-default: #e6edf3;
                        --color-fg-muted: #8d96a0;
                        --color-canvas-default: #0d1117;
                        --color-canvas-subtle: #161b22;
                        --color-border-default: #30363d;
                        --color-border-muted: #21262d;
                        --color-accent-fg: #4493f8;
                        --color-danger-fg: #f85149;
                    }
                }
                * { box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.5;
                    word-wrap: break-word;
                    max-width: 980px;
                    margin: 0 auto;
                    padding: 32px 28px;
                    background-color: var(--color-canvas-default);
                    color: var(--color-fg-default);
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid var(--color-border-muted); }
                h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid var(--color-border-muted); }
                h3 { font-size: 1.25em; }
                h4 { font-size: 1em; }
                h5 { font-size: 0.875em; }
                h6 { font-size: 0.85em; color: var(--color-fg-muted); }
                p { margin-top: 0; margin-bottom: 10px; }
                a {
                    color: var(--color-accent-fg);
                    text-decoration: none;
                }
                a:hover { text-decoration: underline; }
                code {
                    font-family: ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace;
                    font-size: 85%;
                    padding: 0.2em 0.4em;
                    margin: 0;
                    background-color: var(--color-canvas-subtle);
                    border-radius: 6px;
                }
                pre {
                    margin-top: 0;
                    margin-bottom: 16px;
                    padding: 16px;
                    overflow: auto;
                    font-size: 85%;
                    line-height: 1.45;
                    background-color: var(--color-canvas-subtle);
                    border-radius: 6px;
                }
                pre code {
                    display: block;
                    padding: 0;
                    margin: 0;
                    overflow: visible;
                    line-height: inherit;
                    word-wrap: normal;
                    background-color: transparent;
                    border: 0;
                    font-size: 100%;
                }
                blockquote {
                    margin: 0 0 16px 0;
                    padding: 0 1em;
                    color: var(--color-fg-muted);
                    border-left: 0.25em solid var(--color-border-default);
                }
                blockquote > :first-child { margin-top: 0; }
                blockquote > :last-child { margin-bottom: 0; }
                ul, ol {
                    margin-top: 0;
                    margin-bottom: 16px;
                    padding-left: 2em;
                }
                li { margin-top: 0.25em; }
                li + li { margin-top: 0.25em; }
                ul ul, ul ol, ol ol, ol ul {
                    margin-top: 0;
                    margin-bottom: 0;
                }
                hr {
                    height: 0.25em;
                    padding: 0;
                    margin: 24px 0;
                    background-color: var(--color-border-default);
                    border: 0;
                }
                table {
                    border-spacing: 0;
                    border-collapse: collapse;
                    margin-top: 0;
                    margin-bottom: 16px;
                    display: block;
                    width: max-content;
                    max-width: 100%;
                    overflow: auto;
                }
                table th {
                    font-weight: 600;
                }
                table th, table td {
                    padding: 6px 13px;
                    border: 1px solid var(--color-border-default);
                }
                table tr {
                    background-color: var(--color-canvas-default);
                    border-top: 1px solid var(--color-border-muted);
                }
                table tr:nth-child(2n) {
                    background-color: var(--color-canvas-subtle);
                }
                img {
                    max-width: 100%;
                    box-sizing: content-box;
                    background-color: var(--color-canvas-default);
                }
                del { color: var(--color-fg-muted); }
                strong { font-weight: 600; }
                em { font-style: italic; }
                .front-matter {
                    margin-bottom: 24px;
                    padding: 12px 16px;
                    background-color: var(--color-canvas-subtle);
                    border-radius: 6px;
                    border: 1px solid var(--color-border-muted);
                }
                .front-matter-table {
                    display: table;
                    width: auto;
                    margin: 0;
                    font-size: 12px;
                    border: none;
                }
                .front-matter-table tr {
                    background: transparent !important;
                    border: none;
                }
                .front-matter-table td {
                    padding: 2px 0;
                    border: none;
                    vertical-align: top;
                }
                .front-matter-table .fm-key {
                    color: var(--color-fg-muted);
                    padding-right: 12px;
                    white-space: nowrap;
                    font-weight: 500;
                }
                .front-matter-table .fm-value {
                    color: var(--color-fg-default);
                    font-family: ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace;
                }
                mark.mv-find-match {
                    background-color: #fff3b0;
                    color: #111111;
                    border-radius: 2px;
                }
                mark.mv-find-active {
                    background-color: #ffd24d;
                }
            </style>
        </head>
        <body>
            \(body)
            <script>hljs.highlightAll();</script>
            <script>
                (function() {
                    var state = {
                        query: "",
                        matches: [],
                        index: -1
                    };

                    function clearHighlights() {
                        var marks = document.querySelectorAll("mark.mv-find-match");
                        for (var i = 0; i < marks.length; i++) {
                            var mark = marks[i];
                            var parent = mark.parentNode;
                            if (!parent) {
                                continue;
                            }
                            parent.replaceChild(document.createTextNode(mark.textContent), mark);
                            parent.normalize();
                        }
                        state.matches = [];
                        state.index = -1;
                    }

                    function collectTextNodes() {
                        var nodes = [];
                        var walker = document.createTreeWalker(
                            document.body,
                            NodeFilter.SHOW_TEXT,
                            {
                                acceptNode: function(node) {
                                    if (!node.nodeValue || !node.nodeValue.trim()) {
                                        return NodeFilter.FILTER_REJECT;
                                    }
                                    var parent = node.parentNode;
                                    if (!parent) {
                                        return NodeFilter.FILTER_REJECT;
                                    }
                                    if (parent.closest("script, style, mark")) {
                                        return NodeFilter.FILTER_REJECT;
                                    }
                                    return NodeFilter.FILTER_ACCEPT;
                                }
                            }
                        );
                        var current = walker.nextNode();
                        while (current) {
                            nodes.push(current);
                            current = walker.nextNode();
                        }
                        return nodes;
                    }

                    function highlightAll(query) {
                        clearHighlights();
                        state.query = query;
                        if (!query) {
                            return;
                        }
                        var lowerQuery = query.toLowerCase();
                        var nodes = collectTextNodes();
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            var text = node.nodeValue;
                            var fragment = document.createDocumentFragment();
                            var lowerText = text.toLowerCase();
                            var startIndex = 0;
                            var matchIndex = lowerText.indexOf(lowerQuery, startIndex);
                            if (matchIndex === -1) {
                                continue;
                            }
                            while (matchIndex !== -1) {
                                var endIndex = matchIndex + query.length;
                                if (matchIndex > startIndex) {
                                    fragment.appendChild(document.createTextNode(text.slice(startIndex, matchIndex)));
                                }
                                var mark = document.createElement("mark");
                                mark.className = "mv-find-match";
                                mark.textContent = text.slice(matchIndex, endIndex);
                                fragment.appendChild(mark);
                                state.matches.push(mark);
                                startIndex = endIndex;
                                matchIndex = lowerText.indexOf(lowerQuery, startIndex);
                            }
                            if (startIndex < text.length) {
                                fragment.appendChild(document.createTextNode(text.slice(startIndex)));
                            }
                            node.parentNode.replaceChild(fragment, node);
                        }
                        if (state.matches.length > 0) {
                            state.index = 0;
                            updateActive();
                        }
                    }

                    function updateActive() {
                        if (state.matches.length === 0 || state.index < 0) {
                            return;
                        }
                        for (var i = 0; i < state.matches.length; i++) {
                            if (i === state.index) {
                                state.matches[i].classList.add("mv-find-active");
                            } else {
                                state.matches[i].classList.remove("mv-find-active");
                            }
                        }
                        var target = state.matches[state.index];
                        if (target && target.scrollIntoView) {
                            target.scrollIntoView({ block: "center", inline: "nearest" });
                        }
                    }

                    function step(direction) {
                        if (state.matches.length === 0) {
                            return;
                        }
                        if (direction === "backward") {
                            state.index = (state.index - 1 + state.matches.length) % state.matches.length;
                        } else {
                            state.index = (state.index + 1) % state.matches.length;
                        }
                        updateActive();
                    }

                    window.__markdownViewerFind = function(payload) {
                        if (!payload) {
                            return;
                        }
                        var query = payload.query || "";
                        var direction = payload.direction || "forward";
                        var reset = Boolean(payload.reset);
                        if (reset || query !== state.query) {
                            highlightAll(query);
                        } else {
                            step(direction);
                        }
                    };
                })();
            </script>
        </body>
        </html>
        """
    }
}
