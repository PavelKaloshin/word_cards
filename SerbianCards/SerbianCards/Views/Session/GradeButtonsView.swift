import SwiftUI

struct GradeButtonsView: View {
    let onGrade: (Grade) -> Void

    var body: some View {
        HStack(spacing: 12) {
            gradeButton(grade: .again, label: "Again", color: .red, systemImage: "xmark")
            gradeButton(grade: .hard, label: "Hard", color: .orange, systemImage: "minus")
            gradeButton(grade: .good, label: "Good", color: .green, systemImage: "checkmark")
        }
        .padding(.horizontal)
    }

    private func gradeButton(grade: Grade, label: String, color: Color, systemImage: String) -> some View {
        Button {
            onGrade(grade)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
