import SwiftUI

struct LearnProgressView: View {
    let progress: LearnProgress

    var body: some View {
        VStack(spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * progressFraction)
                        .animation(.easeInOut(duration: 0.3), value: progressFraction)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            // Summary text
            HStack {
                Text("\(progress.totalCorrect)/\(progress.maxCorrect) correct")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(progress.completedWords)/\(progress.totalWords) mastered")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var progressFraction: CGFloat {
        guard progress.maxCorrect > 0 else { return 0 }
        return CGFloat(progress.totalCorrect) / CGFloat(progress.maxCorrect)
    }
}

struct LearnPanelView: View {
    let progress: LearnProgress

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(progress.words) { item in
                    HStack(spacing: 8) {
                        if let image = MediaStorageService.loadImage(path: item.imagePath) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .frame(width: 36, height: 36)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.wordCyr.isEmpty ? item.wordLat : item.wordCyr)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if !item.translation.isEmpty {
                                Text(item.translation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        // Pips
                        HStack(spacing: 3) {
                            ForEach(0..<progress.threshold, id: \.self) { i in
                                Circle()
                                    .fill(i < item.correctCount ? Color.green : Color(.systemGray5))
                                    .frame(width: 8, height: 8)
                            }
                        }

                        Text("\(item.correctCount)/\(progress.threshold)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(item.completed ? Color.green.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
