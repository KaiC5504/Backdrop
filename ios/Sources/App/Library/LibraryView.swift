import SwiftUI
import UniformTypeIdentifiers
import BackdropCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let zoomNamespace: Namespace.ID

    @State private var videos: [VideoItem] = []
    @State private var libraryAlbums: [AlbumItem] = []
    @State private var selectedAlbumID = AlbumItem.favouritesID
    @State private var hasLoaded = false
    /// True only for the first grid render, so the stagger plays once, not on every refresh.
    @State private var staggerDone = false
    /// The favourite whose lifted preview is under the finger.
    @State private var draggingID: String?
    @State private var reorderCount = 0

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.s),
        GridItem(.flexible(), spacing: Theme.Spacing.s),
    ]

    private var isFavouritesTab: Bool { selectedAlbumID == AlbumItem.favouritesID }

    private var albums: [AlbumItem] {
        let favourites = AlbumItem(
            id: AlbumItem.favouritesID, title: AppModel.favouritesTitle,
            kind: .favourites, count: model.favourites.count
        )
        return [favourites] + libraryAlbums
    }

    /// Favourites render straight from the model so a drag reorder animates in place.
    private var displayedVideos: [VideoItem] {
        isFavouritesTab ? model.favourites : videos
    }

    var body: some View {
        @Bindable var model = model
        ZStack {
            BackdropBackground()
            ScrollView {
                VStack(spacing: 0) {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.m, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(displayedVideos.enumerated()), id: \.element.id) { index, item in
                                cell(for: item, at: index)
                            }
                        } header: {
                            gridHeader
                        }
                    }
                    if hasLoaded && displayedVideos.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .refreshable { await reloadAll() }
        }
        // A favourite let go anywhere but over a cell lands here, so the lifted cell
        // never stays dimmed after a cancelled drag.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            let wasDragging = draggingID != nil
            draggingID = nil
            return wasDragging
        }
        .safeAreaBar(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.engine.current != nil {
                MiniBarView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.spring, value: model.engine.current != nil)
        .sensoryFeedback(.selection, trigger: reorderCount)
        .sheet(isPresented: $model.isDiagnosticsPresented) { DiagnosticsView() }
        .task {
            // Favourites is home. CI's `library` shot wants the full grid, so it opens All.
            if model.launch.initialScreen == "library" {
                selectedAlbumID = AlbumItem.allID
            }
            await reloadAll()
            for await _ in model.library.changes {
                await reloadAll()
            }
        }
        .onChange(of: selectedAlbumID) { _, _ in
            draggingID = nil
            Task { await reloadVideos() }
        }
    }

    @ViewBuilder
    private func cell(for item: VideoItem, at index: Int) -> some View {
        let base = VideoCell(
            item: item, index: index,
            animateIn: !staggerDone && !reduceMotion,
            starred: !isFavouritesTab && model.isFavourite(item.id)
        )
        .matchedTransitionSource(id: item.id, in: zoomNamespace)
        .onTapGesture { model.play(item) }
        .contextMenu { cellMenu(for: item) }

        if isFavouritesTab {
            base
                .onDrag {
                    draggingID = item.id
                    return NSItemProvider(object: item.id as NSString)
                }
                .onDrop(of: [.text], delegate: FavouriteDropDelegate(
                    targetID: item.id,
                    draggingID: $draggingID,
                    move: { dragged in
                        withAnimation(Theme.Motion.snappy) { model.moveFavourite(dragged, onto: item.id) }
                        reorderCount += 1
                    }
                ))
                // Outermost so the lifted preview snapshots the cell at full strength.
                .opacity(draggingID == item.id ? 0.3 : 1)
        } else {
            base
        }
    }

    @ViewBuilder
    private func cellMenu(for item: VideoItem) -> some View {
        let starred = model.isFavourite(item.id)
        Button {
            withAnimation(Theme.Motion.spring) { model.toggleFavourite(item) }
        } label: {
            Label(starred ? "Remove from Favourites" : "Add to Favourites",
                  systemImage: starred ? "star.slash" : "star")
        }
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

    private var gridHeader: some View {
        VStack(spacing: 0) {
            AlbumChips(albums: albums, selectedID: $selectedAlbumID)
            if isFavouritesTab {
                favouritesBlurb
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.snappy, value: isFavouritesTab)
    }

    private var favouritesBlurb: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "star.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.Colors.favourite)
                .padding(.top, 2)
            Text("Your playlist. Star a video in the player to add it here, hold one and drag to reorder, and tap any to play them all from there in this order.")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + 2)
        .glassSurface(cornerRadius: Theme.Radius.pill)
        .padding(.bottom, Theme.Spacing.s)
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
        let count = displayedVideos.count
        if count == 0 { return "Your videos, playing behind everything else." }
        if isFavouritesTab { return count == 1 ? "1 favourite" : "\(count) favourites" }
        return count == 1 ? "1 video" : "\(count) videos"
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: isFavouritesTab ? "star" : "video.slash")
                .font(.title)
                .foregroundStyle(isFavouritesTab ? Theme.Colors.favourite : Theme.Colors.textSecondary)
            Text(isFavouritesTab ? "No favourites yet" : "No videos here")
                .font(.headline)
            Text(isFavouritesTab
                 ? "Pick a video from All and tap the star next to Queue. It lands here, and Favourites are what plays next."
                 : "Videos you record or save to Photos show up here.")
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
        await model.refreshFavourites()
        libraryAlbums = await model.library.albums()
        if albums.contains(where: { $0.id == selectedAlbumID }) {
            await reloadVideos()
        } else {
            selectedAlbumID = AlbumItem.favouritesID   // onChange reloads
        }
        if !hasLoaded {
            hasLoaded = true
            try? await Task.sleep(for: .seconds(1))
            staggerDone = true
        }
    }

    private func reloadVideos() async {
        if isFavouritesTab {
            videos = []
            return
        }
        let album = libraryAlbums.first(where: { $0.id == selectedAlbumID })
            ?? AlbumItem(id: AlbumItem.allID, title: "All", kind: .all, count: 0)
        videos = await model.library.videos(in: album)
    }
}

/// Live reorder: the moment the finger carries a favourite over another cell the model
/// changes underneath, so the cells slide apart. By the drop there is nothing left to do.
private struct FavouriteDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let move: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingID, dragging != targetID else { return }
        move(dragging)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}
