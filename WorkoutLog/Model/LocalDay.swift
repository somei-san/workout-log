import Foundation

/// 年月日。1 回の記録の日付は、記録した場所の時刻で数える
struct LocalDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year!
        month = c.month!
        day = c.day!
    }

    /// performedAt(UTC)と、記録した場所の UTC との時差(分)から
    init(performedAt: Date, utcOffset: Int) {
        self.init(performedAt, timeZone: TimeZone(secondsFromGMT: utcOffset * 60)!)
    }

    static func today() -> LocalDay {
        LocalDay(Date(), timeZone: .current)
    }

    /// self から other までの日数
    func days(to other: LocalDay) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let from = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let to = calendar.date(from: DateComponents(year: other.year, month: other.month, day: other.day))!
        return calendar.dateComponents([.day], from: from, to: to).day!
    }

    static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

extension WorkoutRecord {
    /// 記録した場所のタイムゾーン
    var timeZone: TimeZone { TimeZone(secondsFromGMT: utcOffset * 60)! }

    var day: LocalDay { LocalDay(performedAt: performedAt, utcOffset: utcOffset) }

    /// 同じ日に別の 1 回の記録があるか。あれば日付に時刻も出す
    func sharesDay(with records: [WorkoutRecord]) -> Bool {
        records.contains { $0.id != id && $0.exerciseId == exerciseId && $0.day == day }
    }
}
