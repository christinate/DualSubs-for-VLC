import argparse
import ctypes
import json
import os
import sys
import time
from ctypes import POINTER, Structure, c_char_p, c_int, c_void_p


class TrackDescription(Structure):
    pass


TrackDescription._fields_ = [
    ("i_id", c_int),
    ("psz_name", c_char_p),
    ("p_next", POINTER(TrackDescription)),
]


def iter_track_descriptions(head):
    current = head
    while current:
        item = current.contents
        yield {
            "id": int(item.i_id),
            "name": item.psz_name.decode("utf-8", errors="replace") if item.psz_name else "",
        }
        current = item.p_next


def build_arg_parser():
    parser = argparse.ArgumentParser(
        description="Smoke-test DualSubs subtitle track exposure through libVLC."
    )
    parser.add_argument("--runtime", required=True, help="Path to the VLC runtime directory")
    parser.add_argument("--media", required=True, help="Path to the test media file")
    parser.add_argument("--sub1", required=True, help="Path to the first subtitle file")
    parser.add_argument("--sub2", required=True, help="Path to the second subtitle file")
    parser.add_argument(
        "--sleep-seconds",
        type=float,
        default=2.0,
        help="Seconds to wait after playback starts before reading subtitle tracks",
    )
    return parser


def main():
    args = build_arg_parser().parse_args()

    runtime = os.path.abspath(args.runtime)
    media = os.path.abspath(args.media)
    sub1 = os.path.abspath(args.sub1)
    sub2 = os.path.abspath(args.sub2)
    libvlc_path = os.path.join(runtime, "libvlc.dll")

    if not os.path.exists(libvlc_path):
        print(json.dumps({"ok": False, "error": f"Missing libvlc.dll at {libvlc_path}"}))
        return 1

    if hasattr(os, "add_dll_directory"):
        os.add_dll_directory(runtime)

    os.environ["VLC_PLUGIN_PATH"] = os.path.join(runtime, "plugins")

    libvlc = ctypes.WinDLL(libvlc_path)

    libvlc.libvlc_new.argtypes = [c_int, POINTER(c_char_p)]
    libvlc.libvlc_new.restype = c_void_p
    libvlc.libvlc_release.argtypes = [c_void_p]
    libvlc.libvlc_release.restype = None
    libvlc.libvlc_media_new_path.argtypes = [c_void_p, c_char_p]
    libvlc.libvlc_media_new_path.restype = c_void_p
    libvlc.libvlc_media_add_option.argtypes = [c_void_p, c_char_p]
    libvlc.libvlc_media_add_option.restype = None
    libvlc.libvlc_media_release.argtypes = [c_void_p]
    libvlc.libvlc_media_release.restype = None
    libvlc.libvlc_media_player_new_from_media.argtypes = [c_void_p]
    libvlc.libvlc_media_player_new_from_media.restype = c_void_p
    libvlc.libvlc_media_player_release.argtypes = [c_void_p]
    libvlc.libvlc_media_player_release.restype = None
    libvlc.libvlc_media_player_play.argtypes = [c_void_p]
    libvlc.libvlc_media_player_play.restype = c_int
    libvlc.libvlc_media_player_stop.argtypes = [c_void_p]
    libvlc.libvlc_media_player_stop.restype = None
    libvlc.libvlc_video_get_spu_count.argtypes = [c_void_p]
    libvlc.libvlc_video_get_spu_count.restype = c_int
    libvlc.libvlc_video_get_spu_description.argtypes = [c_void_p]
    libvlc.libvlc_video_get_spu_description.restype = POINTER(TrackDescription)
    libvlc.libvlc_track_description_list_release.argtypes = [POINTER(TrackDescription)]
    libvlc.libvlc_track_description_list_release.restype = None

    instance_args = [
        b"--intf=dummy",
        b"--no-video-title-show",
        b"--quiet",
    ]
    argc = len(instance_args)
    argv = (c_char_p * argc)(*instance_args)

    instance = libvlc.libvlc_new(argc, argv)
    if not instance:
        print(json.dumps({"ok": False, "error": "libvlc_new() returned NULL"}))
        return 1

    media_obj = None
    player = None
    desc_head = None

    try:
        media_obj = libvlc.libvlc_media_new_path(instance, media.encode("utf-8"))
        if not media_obj:
            print(json.dumps({"ok": False, "error": "libvlc_media_new_path() returned NULL"}))
            return 1

        media_options = [
            b":demux=rawvideo",
            b":rawvid-fps=1",
            b":rawvid-width=320",
            b":rawvid-height=180",
            b":rawvid-chroma=RV24",
            f":input-slave={sub1}#{sub2}".encode("utf-8"),
        ]
        for option in media_options:
            libvlc.libvlc_media_add_option(media_obj, option)

        player = libvlc.libvlc_media_player_new_from_media(media_obj)
        if not player:
            print(
                json.dumps(
                    {"ok": False, "error": "libvlc_media_player_new_from_media() returned NULL"}
                )
            )
            return 1

        play_rc = int(libvlc.libvlc_media_player_play(player))
        time.sleep(args.sleep_seconds)

        spu_count = int(libvlc.libvlc_video_get_spu_count(player))
        desc_head = libvlc.libvlc_video_get_spu_description(player)
        tracks = list(iter_track_descriptions(desc_head)) if desc_head else []
        positive_tracks = [track for track in tracks if track["id"] >= 0]
        ok = play_rc == 0 and len(positive_tracks) >= 2

        print(
            json.dumps(
                {
                    "ok": ok,
                    "play_rc": play_rc,
                    "spu_count": spu_count,
                    "tracks": tracks,
                },
                indent=2,
            )
        )
        return 0 if ok else 1
    finally:
        if desc_head:
            libvlc.libvlc_track_description_list_release(desc_head)
        if player:
            libvlc.libvlc_media_player_stop(player)
            libvlc.libvlc_media_player_release(player)
        if media_obj:
            libvlc.libvlc_media_release(media_obj)
        libvlc.libvlc_release(instance)


if __name__ == "__main__":
    sys.exit(main())
