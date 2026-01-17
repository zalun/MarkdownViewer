import AppKit
import SwiftUI

struct OutlineSidebar: View {
    let items: [OutlineItem]
    let onSelect: (OutlineItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Text("No headings")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        OutlineRow(item: item, onSelect: onSelect)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 240, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1),
            alignment: .leading
        )
    }
}

struct OutlineRow: View {
    let item: OutlineItem
    let onSelect: (OutlineItem) -> Void

    private var indent: CGFloat {
        CGFloat(max(item.level - 1, 0)) * 12
    }

    private var fontSize: CGFloat {
        item.level == 1 ? 13 : 12
    }

    private var fontWeight: Font.Weight {
        item.level == 1 ? .semibold : .regular
    }

    private var textColor: Color {
        item.level <= 2 ? .primary : .secondary
    }

    var body: some View {
        Button(action: {
            onSelect(item)
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(textColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .padding(.leading, indent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
