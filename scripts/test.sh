#!/bin/bash
# 手元でテストを回す。テストは、見た目の回帰テストを撮る端末と同じ、scripts/vrt-simulator.sh が用意する
# 専用のシミュレーター 1 台で回す。
#
#   scripts/test.sh                                   単体テストだけ（30 秒ほど）
#   scripts/test.sh RecordTests SnapshotTests/testRecord
#                                                     選んだ UI テストのクラスかテストだけ（WorkoutLogUITests/ は省ける）
#   scripts/test.sh WorkoutLogTests WorkoutLogUITests 全部（UI テストに 30 分ほどかかる）
#
# 見た目の回帰テストの画像を撮り直すときは、環境変数 TEST_RUNNER_SNAPSHOT_TESTING_RECORD=failed を付けて回す
set -euo pipefail

cd "$(dirname "$0")/.."

tests=()
if [ $# -eq 0 ]; then
  tests=(-only-testing:WorkoutLogTests)
fi
for name in "$@"; do
  case "$name" in
    WorkoutLogTests* | WorkoutLogUITests*) tests+=("-only-testing:$name") ;;
    *) tests+=("-only-testing:WorkoutLogUITests/$name") ;;
  esac
done

# xcodeproj が古いままだと、pull で足されたファイルがプロジェクトに入らない。足された Clock.swift が入らず、
# Clock が Swift 標準の同じ名前の型と取り違えられて、ビルドが落ちたことがある。毎回 project.yml から作り直す
xcodegen generate --quiet

udid=$(scripts/vrt-simulator.sh)

# Mac の負荷が高いときに UI テストが落ちることがあったので、並べて回さず、1 台で順に回す
xcodebuild test \
  -project WorkoutLog.xcodeproj -scheme WorkoutLog \
  -destination "id=$udid" -derivedDataPath build \
  -parallel-testing-enabled NO \
  -quiet \
  "${tests[@]}"
