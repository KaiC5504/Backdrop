import SwiftUI
import BackdropCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let zoomNamespace: Namespace.ID

    @State private var videos: [VideoItem] = []
    @State private var albums: [AlbumItem] = []
    @State private var selectedAlbumID = AlbumItem.allID
    @State private var hasLoaded = false
    /// True only for the first grid render, so the stagger plays once, not on every refresh.
    @State private var staggerDone = false

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.s),
        GridItem(.flexible(), spacing: Theme.Spacing.s),
    ]

    var body: some View {
        @Bindable var model = model
        ZStack {
            BackdropBackground()
            ScrollView {
                VStack(spacing: 0) {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.m, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                                VideoCell(item: item, index: index, animateIn: !staggerDone && !reduceMotion)
                                    .matchedTransitionSource(id: item.id, in: zoomNamespace)
                                    .onTapGesture { model.play(item, in: videos) }
                                    .contextMenu {
                                        Button {
                                            model.playNext(item)
                                        } label: {
                                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        }
                                        Button {
                                            model.enqueue(item)
                                        } label: {
                                            Label("Add to Queue", systemImage: "text.badge.plus")
                                        }
                                    }
                            }
                        } header: {
                            AlbumChips(albums: albums, selectedID: $selectedAlbumID)
                        }
                    }
                    if hasLoaded && videos.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .refreshable { await reloadAll() }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.engine.current != nil {
                MiniBarView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.spring, value: model.engine.current != nil)
        .sheet(isPresented: $model.isDiagnosticsPresented) { DiagnosticsView() }
        .task {
            await reloadAll()
            for await _ in model.library.changes {
                await reloadAll()
            }
        }
        .onChange(of: selectedAlbumID) { _, _ in
            Task { await reloadVideos() }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Backdrop")
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            if model.access == .limited {
                Button {
                    LimitedLibraryPicker.present()
                } label: {
                    Text("Manage")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.chipH)
                        .padding(.vertical, Theme.Spacing.s)
                }
                .buttonStyle(.plain)
                .glassCapsule(interactive: true)
            }
            GlassIconButton(systemName: "gearshape") {
                model.isDiagnosticsPresented = true
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }

    private var subtitle: String {
        if videos.isEmpty { return "Your videos, playing behind everything else." }
        return videos.count == 1 ? "1 video" : "\(videos.count) videos"
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "video.slash")
                .font(.title)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No videos here")
                .font(.headline)
            Text("Videos you record or save to Photos show up here.")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .glassSurface()
        .padding(.top, Theme.Spacing.xl)
    }

    private func reloadAll() async {
        albums = await model.library.albums()
        if !albums.contains(where: { $0.id == selectedAlbumID }) {
            selectedAlbumID = AlbumItem.allID
        }
        await reloadVideos()
        if !hasLoaded {
            hasLoaded = true
            try? await Task.sleep(for: .seconds(1))
            staggerDone = true
        }
    }

    private func reloadVideos() async {
        let album = albums.first(where: { $0.id == selectedAlbumID })
            ?? AlbumItem(id: AlbumItem.allID, title: "All", kind: .all, count: 0)
        videos = await model.library.videos(in: album)
    }
}
