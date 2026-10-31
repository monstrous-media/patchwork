#if os(macOS)
import SwiftUI
import PatchworkCore

/// Which guide section the Help window should show when it opens (set by the ? buttons).
final class HelpState: ObservableObject {
    @Published var requestedSection: String?
}

/// Minimal Markdown document model: enough for the bundled guide (headings, paragraphs,
/// bullet lists, fenced code, pipe tables, inline bold/code/links).
enum MDBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case code(String)
    case table([[String]])

    var id: String {
        switch self {
        case .heading(let l, let t): return "h\(l)-\(HelpDoc.slug(t))"
        case .paragraph(let s): return "p-\(s.hashValue)"
        case .bullets(let items): return "ul-\(items.joined().hashValue)"
        case .code(let s): return "code-\(s.hashValue)"
        case .table(let rows): return "table-\(rows.flatMap { $0 }.joined().hashValue)"
        }
    }
}

enum HelpDoc {
    static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        var out = ""
        var lastDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber { out.append(ch); lastDash = false }
            else if !lastDash && !out.isEmpty { out.append("-"); lastDash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    static func loadGuide() -> String {
        if let url = Bundle.module.url(forResource: "guide", withExtension: "md", subdirectory: "Resources"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        return "# Guide not found\n\nThe bundled guide.md is missing from the app resources."
    }

    static func parse(_ markdown: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var table: [[String]] = []
        var code: [String]? = nil

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
        }
        func flushTable() {
            if !table.isEmpty { blocks.append(.table(table)); table = [] }
        }
        func flushAll() { flushParagraph(); flushBullets(); flushTable() }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let c = code {
                if line.hasPrefix("```") { blocks.append(.code(c.joined(separator: "\n"))); code = nil }
                else { code!.append(rawLine) }
                continue
            }
            if line.hasPrefix("```") { flushAll(); code = []; continue }
            if line.isEmpty { flushAll(); continue }
            if line.hasPrefix("#") {
                flushAll()
                let level = line.prefix { $0 == "#" }.count
                blocks.append(.heading(level: level, text: line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph(); flushTable()
                bullets.append(String(line.dropFirst(2)))
                continue
            }
            if line.hasPrefix("|") {
                flushParagraph(); flushBullets()
                let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                let inner = Array(cells.dropFirst().dropLast())
                if inner.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } && !$0.isEmpty }) { continue }   // |---|---| separator
                table.append(inner)
                continue
            }
            flushBullets(); flushTable()
            paragraph.append(line)
        }
        flushAll()
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        return blocks
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct HelpView: View {
    @EnvironmentObject var help: HelpState
    @State private var blocks: [MDBlock] = HelpDoc.parse(HelpDoc.loadGuide() + "\n\n" + ParameterHelp.markdownReference())
    @State private var selection: String?

    var sections: [(id: String, title: String, level: Int)] {
        blocks.compactMap { block -> (id: String, title: String, level: Int)? in
            if case .heading(let l, let t) = block, l >= 2 { return (id: "h\(l)-\(HelpDoc.slug(t))", title: t, level: l) }
            return nil
        }
    }

    var body: some View {
        NavigationSplitView {
            List(sections, id: \.id, selection: $selection) { s in
                Text(s.title)
                    .padding(.leading, s.level == 3 ? 14 : 0)
                    .font(s.level == 2 ? .body : .callout)
                    .foregroundStyle(s.level == 2 ? .primary : .secondary)
                    .tag(s.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(blocks) { block in
                            blockView(block).id(block.id)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                }
                .onChange(of: selection) { id in
                    if let id = id { withAnimation { proxy.scrollTo(id, anchor: .top) } }
                }
                .onChange(of: help.requestedSection) { section in
                    if let s = section { selection = sections.first { $0.id.hasSuffix(s) }?.id; help.requestedSection = nil }
                }
                .onAppear {
                    if let s = help.requestedSection { selection = sections.first { $0.id.hasSuffix(s) }?.id; help.requestedSection = nil }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder
    func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            switch level {
            case 1: Text(text).font(.largeTitle.bold()).padding(.bottom, 4)
            case 2: Text(text).font(.title2.bold()).padding(.top, 14)
            default: Text(text).font(.headline).padding(.top, 6)
            }
        case .paragraph(let s):
            Text(HelpDoc.inline(s)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(HelpDoc.inline(item)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 6)
        case .code(let s):
            Text(s)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(HelpDoc.inline(cell))
                                .font(i == 0 ? .body.bold() : .body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if i == 0 { Divider() }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// A small circled "?" that opens the guide at a section.
struct HelpButton: View {
    let section: String
    @EnvironmentObject var help: HelpState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            help.requestedSection = section
            openWindow(id: "help")
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.borderless)
        .help("Open the guide for this part of the app")
    }
}
#endif
