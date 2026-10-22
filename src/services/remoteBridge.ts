import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { player } from "../stores/player.svelte";
import { lyricsStore } from "../stores/lyrics.svelte";
import { favorites } from "../stores/favorites.svelte";

export interface RemoteInfo {
  ip: string | null;
  port: number;
}

export async function getRemoteServerInfo(): Promise<RemoteInfo> {
  return await invoke<RemoteInfo>("remote_get_info");
}

export function startRemoteBridge(): () => void {
  let stopped = false;
  let lastTrackPath: string | null = null;
  let lastLyrics: unknown = null;

  const PUSH_INTERVAL_MS = 250;
  const timer = setInterval(() => {
    if (stopped) return;

    const curPath = player.current?.source;
    if (curPath && curPath !== lastTrackPath) {
      lastTrackPath = curPath;
      void invoke("remote_set_artwork_file", { path: curPath }).catch(() => {});
    } else if (!curPath && lastTrackPath) {
      lastTrackPath = null;
    }

    void invoke("remote_update_state", {
      update: {
        title: player.current?.title ?? "No track playing",
        artist: player.current?.artist ?? "",
        album: player.current?.album ?? "",
        position: player.position,
        duration: player.duration,
        playing: player.isPlaying,
        buffering: player.isBuffering,
        accent: player.accent,
        liked: player.current?.id ? favorites.has(player.current.id) : false,
        volume: player.volume,
        muted: player.muted,
        has_artwork: !!player.current?.artwork,
        has_lyrics: !!lyricsStore.lyrics,
      },
    }).catch(() => {});
  }, PUSH_INTERVAL_MS);

  const lyricsTimer = setInterval(() => {
    if (stopped) return;
    if (lyricsStore.lyrics === lastLyrics) return;
    lastLyrics = lyricsStore.lyrics;
    const l = lyricsStore.lyrics;
    const jsonStr = l
      ? JSON.stringify({
          lines: l.lines.map((x) => ({ time: x.time, text: x.text, words: x.words })),
          level: l.level,
        })
      : null;
    void invoke("remote_update_lyrics", { lyricsJson: jsonStr }).catch(() => {});
  }, 500);

  const unlistenPromise = listen<{ command: string; value?: number }>(
    "remote-command",
    (event) => {
      const { command, value } = event.payload;
      if (command === "toggle") {
        void player.toggle();
      } else if (command === "play") {
        void player.play();
      } else if (command === "pause") {
        player.pause();
      } else if (command === "next") {
        void player.next();
      } else if (command === "prev") {
        void player.previous();
      } else if (command === "favorite") {
        const id = player.current?.id;
        if (id) favorites.toggle(id);
      } else if (command === "mute") {
        player.setMuted(!player.muted);
      } else if (command === "vol" && typeof value === "number") {
        player.setVolume(Math.min(1, Math.max(0, value)));
      } else if (command === "seek" && typeof value === "number" && player.duration > 0) {
        player.seek(Math.min(1, Math.max(0, value)) * player.duration);
      }
    }
  );

  return () => {
    stopped = true;
    clearInterval(timer);
    clearInterval(lyricsTimer);
    void unlistenPromise.then((unlisten) => unlisten());
  };
}
