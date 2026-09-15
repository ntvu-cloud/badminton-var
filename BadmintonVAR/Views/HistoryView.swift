import SwiftUI

public struct HistoryView: View {
    @Binding public var records: [ChallengeRecord]
    @Environment(\.dismiss) var dismiss
    
    public init(records: Binding<[ChallengeRecord]>) {
        self._records = records
    }
    
    public var body: some View {
        NavigationView {
            List {
                // Thống kê nhanh
                Section(header: Text("Tổng hợp phán quyết")) {
                    HStack {
                        statisticBadge(
                            title: "IN",
                            count: records.filter { $0.verdict == .inCourt }.count,
                            color: .green
                        )
                        Spacer()
                        statisticBadge(
                            title: "OUT",
                            count: records.filter { $0.verdict == .outOfCourt }.count,
                            color: .red
                        )
                        Spacer()
                        statisticBadge(
                            title: "TỔNG SỐ",
                            count: records.count,
                            color: .blue
                        )
                    }
                    .padding(.vertical, 4)
                }
                
                // Danh sách chi tiết các pha Challenge
                Section(header: Text("Lịch sử các pha Challenge")) {
                    if records.isEmpty {
                        Text("Chưa có pha Challenge nào được ghi nhận.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(records) { record in
                            HStack(spacing: 12) {
                                Image(systemName: record.verdict.iconName)
                                    .font(.system(size: 24))
                                    .foregroundColor(record.verdict.color)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(record.verdict.rawValue)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(record.verdict.color)
                                        Spacer()
                                        Text(record.timestamp, style: .time)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(record.position.rawValue)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    if !record.notes.isEmpty {
                                        Text(record.notes)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteRecords)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Lịch sử VAR")
            .navigationBarItems(
                leading: EditButton(),
                trailing: Button("Đóng") { dismiss() }
            )
        }
    }
    
    private func statisticBadge(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
    }
    
    private func deleteRecords(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
    }
}
