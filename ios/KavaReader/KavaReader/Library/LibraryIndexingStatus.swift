import SwiftUI

/// The same indexing status is used on Home and below the file library.
struct LibraryIndexingStatus: View {
    @ObservedObject var diagnostics: LibraryPlusDiagnostics

    private var total: Int {
        diagnostics.isLoading ? diagnostics.totalCount : diagnostics.externalTotalCount
    }

    private var completed: Int {
        min(total, diagnostics.isLoading ? diagnostics.completedCount : diagnostics.externalCompletedCount)
    }

    var body: some View {
        if diagnostics.isLoading || diagnostics.isEnriching {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("인덱싱 중…")
                        .font(.subheadline.weight(.medium))
                }
                VStack(alignment: .trailing, spacing: 5) {
                    ProgressView(value: Double(completed), total: Double(max(total, 1)))
                        .tint(AppTheme.accent)
                    Text("\(completed)/\(total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Text("작품의 장르와 태그 정보를 정리해 장르별 탐색과 취향에 맞는 추천을 준비하고 있어요.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
}
