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

    /// 部位の見方の区切りの順。経過日数なら胸、肩、…、その他の順。
    /// 頻度なら、その部位の表示中の種目の頻度の合計で、選んだ向きに並べる。合計が同じなら胸、肩、…の順
    func partOrder(_ cards: [ExerciseCard]) -> [Part] {
        guard !isElapsed else { return Part.allCases }
        let total = Dictionary(grouping: cards.filter { !$0.exercise.isHidden }, by: \.exercise.part).mapValues { $0.reduce(0) { $0 + $1.frequency(self) } }
        return Part.allCases.enumerated().sorted { a, b in
            let ta = total[a.element] ?? 0, tb = total[b.element] ?? 0
            if ta != tb { return isDescending ? ta > tb : ta < tb }
            return a.offset < b.offset
        }.map(\.element)
    }
}
