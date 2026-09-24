import SwiftUI

struct DynamicForwardUnavailableView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.caption.weight(.semibold))
            Text("原动态不可见或已删除")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
