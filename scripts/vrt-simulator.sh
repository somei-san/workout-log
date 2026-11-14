#!/bin/bash
# 見た目の回帰テストで画面を撮る専用のシミュレーターを用意して起動し、UDID を出力する。
# 手元と CI で同じ条件で撮るため、どちらもこのスクリプトで用意する。
# 既存のシミュレーターを使い回すと、キーボードの種類などの設定が手元と CI で食い違うおそれがあるため、専用の端末を作る
set -euo pipefail

name="WorkoutLog VRT"
runtime="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-17"

udid=$(xcrun simctl list devices available -j \
  | jq -r --arg runtime "$runtime" --arg name "$name" \
    '.devices[$runtime] // [] | map(select(.name == $name)) | first | .udid // empty')
if [ -z "$udid" ]; then
  udid=$(xcrun simctl create "$name" "$device_type" "$runtime")
fi

# 起動済みなら boot は失敗するので、失敗を無視する
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b > /dev/null

# 起動した後は、壁紙・ウィジェット・写真の解析などのシミュレーターの中のサービスが CPU を使い続け、UI テストの操作が遅くなるおそれがある。
# テストのアプリの画面に写らないサービスを止める。キーボードの表示に関わりそうなもの（予測変換・音声入力）は止めない。
for service in \
  com.apple.PosterBoard \
  com.apple.chronod \
  com.apple.photoanalysisd \
  com.apple.mediaanalysisd \
  com.apple.telephonyutilities.callservicesd \
  com.apple.WebBookmarks.webbookmarksd \
  com.apple.searchd \
  com.apple.sociallayerd; do
  # 止められなかったサービスがあっても、テストは続けられるので失敗を無視する。
  # 止めると標準出力に警告が出る。標準出力は UDID だけにするので、捨てる
  xcrun simctl spawn "$udid" launchctl bootout "system/$service" > /dev/null 2>&1 || true
done

# ステータスバーの時刻・電池・電波を毎回同じ表示にする。上書きは端末を再起動すると消えるので、起動のたびにかける
xcrun simctl status_bar "$udid" override \
  --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --operatorName "" \
  --batteryState charged --batteryLevel 100

echo "$udid"
