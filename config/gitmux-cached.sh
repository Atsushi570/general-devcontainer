#!/bin/sh
# gitmux をキャッシュ経由で呼ぶ。
# tmux はペイン出力による再描画のたびに #() を実行するので(実測 1.6回/秒、
# status-interval とは無関係)、gitmux を直接書くと 1回 0.3-0.5s x 常時 で
# CPU を 1コア近く食う。ここではキャッシュを即座に返し、TTL 切れのときだけ
# 裏で 1 本だけ gitmux を走らせる。

path="$1"
ttl=15
dir="${XDG_CACHE_HOME:-$HOME/.cache}/gitmux"
key=$(printf '%s' "$path" | cksum | cut -d' ' -f1)
cache="$dir/$key"
lock="$dir/$key.lock"

mkdir -p "$dir"

# 常に現在のキャッシュを返す(空でもよい。1秒以内に埋まる)
[ -f "$cache" ] && cat "$cache"

# まだ新しければ何もしない
[ -n "$(find "$cache" -newermt "-${ttl} seconds" 2>/dev/null)" ] && exit 0

# 死んだプロセスが残したロックを回収
[ -d "$lock" ] && [ -z "$(find "$lock" -newermt '-60 seconds' 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null

# 更新は同時に 1 本だけ
if mkdir "$lock" 2>/dev/null; then
	(
		if gitmux -cfg "$HOME/.gitmux.conf" "$path" >"$cache.tmp" 2>/dev/null; then
			mv "$cache.tmp" "$cache"
		else
			rm -f "$cache.tmp"
		fi
		rmdir "$lock" 2>/dev/null
	) >/dev/null 2>&1 &
fi

exit 0
