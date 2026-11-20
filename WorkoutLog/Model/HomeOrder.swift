import Foundation

extension SortRule {
    /// この並べ方で種目のカードを並べる。未実施の種目は、経過日数がいちばん大きく、頻度が 0 として扱う。
    /// 値が同じなら経過日数の大きい順、それも同じなら名前の順
    func sorted(_ cards: [ExerciseCard], today: LocalDay) -> [ExerciseCard] {
        cards.sorted { a, b in
            let ea = a.elapsedDays(today: today) ?? .max, eb = b.elapsedDays(today: today) ?? .max
            if !isElapsed, a.frequency(self) != b.frequency(self) {
                return isDescending ? a.frequency(self) > b.frequency(self) : a.frequency(self) < b.frequency(self)
            }
            if isElapsed, !isDescending, ea != eb {
                return ea < eb
            }
            return ea != eb ? ea > eb : a.exercise.name < b.exercise.name
        }
    }
}
