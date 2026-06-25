import SwiftUI
import AVKit

struct MediaPlayerView: View {
    let item: FileItem
    @State private var player: AVPlayer?
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading media…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Cannot play this file", systemImage: "play.slash")
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            player = AVPlayer(url: item.url)
            isLoading = false
            player?.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
