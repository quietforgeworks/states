#!/bin/zsh
set -eu
project_dir="${0:A:h}"
build_dir="${STATES_BUILD_DIR:-/private/tmp/states-build}"
app_output="${STATES_APP_OUTPUT:-$project_dir/../States.app}"
cd -- "$project_dir"
mkdir -p "$build_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/module-cache"
swift build -c release --disable-sandbox --scratch-path "$build_dir" --cache-path "$build_dir/cache" --config-path "$build_dir/config"
bin_dir=$(swift build -c release --disable-sandbox --scratch-path "$build_dir" --show-bin-path)
stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/states-release.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
app="$stage_dir/States.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/States" "$app/Contents/MacOS/States"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
chmod +x "$app/Contents/MacOS/States"
codesign --force --options runtime --sign - --identifier local.states.systemstatus "$app"
codesign --verify --strict "$app"
if [[ -e "$app_output" ]]; then mv -- "$app_output" "$stage_dir/Previous.app"; fi
if ! ditto --norsrc --noextattr "$app" "$app_output"; then
    if [[ -e "$stage_dir/Previous.app" ]]; then ditto --norsrc --noextattr "$stage_dir/Previous.app" "$app_output"; fi
    exit 1
fi
print "已构建：$app_output"
