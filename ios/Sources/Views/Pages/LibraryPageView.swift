import SwiftUI
import UIKit

public struct LibraryPageView: View {
    public var onSelectDate: ((String) -> Void)? = nil

    private var lang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var ciStore: CIIndexStore {
        CIIndexStore.shared
    }

    private var listeningStore: ListeningIndexStore {
        ListeningIndexStore.shared
    }

    private var accentColor: Color {
        if let ciShades = MetadataStore.shared.languages[lang.code]?.colors?.ci {
            return ciShades.swiftUIColor
        }
        return lang.themeColor
    }

    @State private var openAccordions: Set<String> = []
    @State private var copiedUrl: String? = nil

    public init(onSelectDate: ((String) -> Void)? = nil) {
        self.onSelectDate = onSelectDate
    }

    private var candidateData: CICandidateData {
        CICandidateService.getUnprocessedCICandidates(
            listeningEntries: listeningStore.entries,
            ciLinks: ciStore.links
        )
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                // 1. Header Glass Pod
                headerGlassPod

                // 2. Queue Section or Empty State
                if candidateData.sortedDates.isEmpty {
                    emptyQueueNotice
                } else {
                    candidateAccordionList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            ciStore.connect(langCode: lang.code)
            listeningStore.connect(langCode: lang.code)
            if let first = candidateData.sortedDates.first {
                openAccordions.insert(first)
            }
        }
        .onChange(of: lang.code) { _, newCode in
            ciStore.connect(langCode: newCode)
            listeningStore.connect(langCode: newCode)
        }
    }

    // MARK: - 1. Header Glass Pod

    private var headerGlassPod: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.38), lineWidth: 1)
                    )

                Image(systemName: "headphones")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(accentColor)
                    .symbolEffect(.pulse)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("CI Candidate Queue")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.primary)

                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: accentColor, radius: 4)
                }

                Text("Listened media ready to be processed into Comprehensible Input")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(candidateData.candidates.count) \(candidateData.candidates.count == 1 ? "candidate" : "candidates")")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accentColor.opacity(0.15))
                .foregroundStyle(accentColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(accentColor.opacity(0.35), lineWidth: 1)
                )
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
    }

    // MARK: - 2. Accordions

    private var candidateAccordionList: some View {
        VStack(spacing: 12) {
            ForEach(candidateData.sortedDates, id: \.self) { dateKey in
                let videos = candidateData.groupedByDate[dateKey] ?? []
                let isOpen = openAccordions.contains(dateKey)

                VStack(spacing: 0) {
                    // Header Bar
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if isOpen {
                                openAccordions.remove(dateKey)
                            } else {
                                openAccordions.insert(dateKey)
                            }
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: accentColor, radius: 3)

                            Image(systemName: "calendar")
                                .font(.caption.bold())
                                .foregroundStyle(accentColor)

                            Text(dateKey)
                                .font(.subheadline.bold().monospaced())
                                .foregroundStyle(.primary)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "film")
                                    .font(.caption2)
                                    .foregroundStyle(accentColor)
                                Text("\(videos.count) \(videos.count == 1 ? "video" : "videos")")
                                    .font(.caption2.bold().monospaced())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(Capsule())

                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isOpen ? 180 : 0))
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)

                    // Video Items Deck
                    if isOpen {
                        Divider()
                            .padding(.horizontal, 14)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                            ForEach(videos) { item in
                                candidateCard(item: item, dateKey: dateKey)
                            }
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.02))
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private func candidateCard(item: CICandidateItem, dateKey: String) -> some View {
        VStack(spacing: 0) {
            VideoPlayerView(src: item.url, accentColor: accentColor)

            HStack {
                if let onSelectDate {
                    Button {
                        onSelectDate(dateKey)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(dateKey)
                                .font(.caption2.bold().monospaced())
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(dateKey)
                            .font(.caption2.bold().monospaced())
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Copy URL Button
                Button {
                    UIPasteboard.general.string = item.url
                    copiedUrl = item.url
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        if copiedUrl == item.url { copiedUrl = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedUrl == item.url ? "checkmark" : "doc.on.doc")
                        Text(copiedUrl == item.url ? "Copied" : "Copy")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .foregroundStyle(copiedUrl == item.url ? accentColor : .primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Open Link
                if let url = URL(string: item.url) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption.bold())
                            .padding(6)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .foregroundStyle(.secondary)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }

    private var emptyQueueNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(accentColor)
            Text("All Caught Up!")
                .font(.headline.bold())
            Text("All listened videos have been processed into Comprehensible Input. Log more listening sessions to generate new candidates.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}