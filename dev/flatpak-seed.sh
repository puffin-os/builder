#!/bin/sh
set -eu

mode=${1:?usage: flatpak-seed.sh lock|build}
apps=/work/desktop/flatpaks.apps
lock=/work/desktop/flatpaks.lock
output=/work/out/puffin-desktop-flatpaks-x86-64.tar.zst
if test "$mode" = lock; then
    work=/work/.cache/flatpak-lock
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf -- "$work"' EXIT INT TERM
fi

export XDG_DATA_HOME="$work/data"
export XDG_CONFIG_HOME="$work/config"
export XDG_CACHE_HOME="$work/cache"
export XDG_DATA_DIRS="$XDG_DATA_HOME/flatpak/exports/share:/usr/local/share:/usr/share"
if test "$mode" = build && test -d /work/.cache/flatpak-lock/data/flatpak; then
    cp -a --reflink=auto /work/.cache/flatpak-lock/data "$work/"
fi
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

flatpak --user remote-add --if-not-exists --from \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo

while IFS= read -r app; do
    test -n "$app" || continue
    flatpak --user install --noninteractive -y flathub "$app"
done <"$apps"

list_refs() {
    {
        flatpak --user list --app --columns=ref:f |
            while IFS= read -r ref; do
                printf 'app/%s\t%s\n' "$ref" \
                    "$(flatpak --user info --show-commit "$ref")"
            done
        flatpak --user list --runtime --columns=ref:f |
            while IFS= read -r ref; do
                printf 'runtime/%s\t%s\n' "$ref" \
                    "$(flatpak --user info --show-commit "$ref")"
            done
    } | LC_ALL=C sort
}

case "$mode" in
    lock)
        list_refs >"$lock"
        echo "Wrote $lock"
        ;;
    build)
        test -s "$lock" || {
            echo "missing $lock; run task desktop:flatpaks:lock" >&2
            exit 1
        }

        while read -r ref commit; do
            test -n "$ref" && test -n "$commit" || continue
            case "$ref" in
                runtime/*)
                    flatpak --user install --runtime --noninteractive -y \
                        flathub "$ref"
                    ;;
            esac
            flatpak --user update --noninteractive -y \
                --commit="$commit" "$ref"
        done <"$lock"

        list_refs >"$work/actual"
        cmp -s "$lock" "$work/actual" || {
            echo "Flatpak deployment differs from desktop/flatpaks.lock" >&2
            diff -u "$lock" "$work/actual" >&2 || true
            exit 1
        }

        mkdir -p /work/out
        chmod 0755 "$XDG_DATA_HOME/flatpak"
        tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
            -C "$XDG_DATA_HOME/flatpak" -cf - . |
            zstd -T0 -10 -f -o "$output"
        echo "Built $output"
        ;;
    *)
        echo "usage: $0 lock|build" >&2
        exit 2
        ;;
esac
