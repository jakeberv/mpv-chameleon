#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mpv-chameleon contributors
"""Opt-in physical-monitor tests. Uses a private IPC socket only in this harness."""
import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


class Player:
    def __init__(self, config, output, name, source, screen):
        self.directory = tempfile.TemporaryDirectory(prefix="mpv-chameleon-ipc-")
        self.path = Path(self.directory.name) / "ipc"
        self.log = output / (name + ".log")
        self.stream = open(output / (name + ".stdout"), "w")
        self.process = subprocess.Popen([
            "mpv", "--config-dir=" + str(config), "--geometry=640x360+100+100",
            "--screen=" + str(screen), "--loop-file=inf", "--hwdec=videotoolbox",
            "--volume=0", "--title=mpv-chameleon-test", "--no-terminal", "--native-fs=no",
            "--script-opts=chameleon-debug=yes",
            "--input-ipc-server=" + str(self.path), "--log-file=" + str(self.log),
            str(source)], stdout=self.stream, stderr=subprocess.STDOUT)
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(10)
        self.reader = None
        self.counter = 0
        self.expected_path = str(source)
        try:
            deadline = time.monotonic() + 15
            while not self.path.exists():
                if self.process.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("mpv did not open the test socket; inspect private log")
                time.sleep(.1)
            self.socket.connect(str(self.path))
            self.reader = self.socket.makefile("r")
        except BaseException:
            self.close()
            raise

    def command(self, *args):
        self.counter += 1
        self.socket.sendall((json.dumps({"command": args, "request_id": self.counter}) + "\n").encode())
        while True:
            line = self.reader.readline()
            if not line:
                raise RuntimeError("mpv closed its IPC connection")
            response = json.loads(line)
            if response.get("request_id") == self.counter:
                if response.get("error") != "success":
                    raise RuntimeError(f"mpv command {args[0:2]}: {response.get('error')}")
                return response.get("data")

    def get(self, name):
        return self.command("get_property", name)

    def text(self):
        return self.log.read_text(errors="replace") if self.log.exists() else ""

    def sample(self, helper, display_id, hdr):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                names = self.get("display-names")
            except RuntimeError as error:
                if "property unavailable" not in str(error):
                    raise
                time.sleep(.1)
                continue
            response = json.loads(subprocess.check_output([str(helper), "--display", names[0]]))
            on_display = response["selection"].get("display_id") == display_id
            colors = re.findall(r"Metal layer colorspace changed: (\S+)", self.text())
            expected = "ITUR_2100_PQ" if hdr else "SRGB"
            if on_display and colors and colors[-1] == expected and self.get("path") == self.expected_path:
                # Allow compositor and pipeline reconstruction to settle before
                # counting frames. This isn't a calibrated color measurement.
                before = self.get("frame-drop-count")
                time.sleep(1.5)
                after = self.get("frame-drop-count")
                text = self.text()
                if hdr:
                    assert self.get("video-params")["gamma"] == "pq"
                    assert self.get("video-params")["primaries"] == "bt.2020"
                    assert re.search(r"Picked surface configuration .*VK_COLOR_SPACE_HDR10_ST2084_EXT", text)
                else:
                    assert self.get("target-trc") == "srgb"
                return {"metal_colorspace": expected, "frame_drops_total": after,
                        "frame_drops_settled_interval": after - before,
                        "decoder_drops": self.get("decoder-frame-drop-count"),
                        "video_params": self.get("video-params"),
                        "video_out_params": self.get("video-out-params"),
                        "tone_mapping": self.get("tone-mapping"),
                        "target_trc": self.get("target-trc")}
            time.sleep(.15)
        raise AssertionError(f"display/Metal state mismatch: wanted id={display_id}, colorspace={expected}; last selection={response.get('selection')}, colors={colors[-1:]}, fullscreen={self.get('fullscreen')}, fs-screen={self.get('fs-screen')}")

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        if self.reader:
            self.reader.close()
        self.socket.close()
        self.stream.close()
        self.directory.cleanup()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hdr-video", type=Path, required=True)
    parser.add_argument("--sdr-video", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/integration")
    args = parser.parse_args()
    for video in (args.hdr_video, args.sdr_video):
        if not video.is_file():
            parser.error("both video paths must exist")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    summary = {"sdr_signaling": "explicit target", "tests": {}}
    with tempfile.TemporaryDirectory(prefix="mpv-chameleon-integration-") as temporary:
        config = Path(temporary) / "config"
        subprocess.run([str(ROOT / "install.sh"), "--config-dir", str(config)], check=True,
                       stdout=subprocess.DEVNULL)
        (config / "mpv.conf").write_text("vo=gpu-next\ngpu-api=vulkan\ngpu-context=macvk\n")
        helper = config / "helpers/mpv-chameleon"
        displays = json.loads(subprocess.check_output([str(helper)]))["displays"]
        hdr_index = next(i for i, d in enumerate(displays) if d["hdr_capable"])
        sdr_index = next(i for i, d in enumerate(displays) if not d["hdr_capable"])
        summary["displays"] = displays  # Helper omits serial numbers.

        def record(name, player, index, hdr):
            value = player.sample(helper, displays[index]["id"], hdr)
            if name.startswith("sdr-") or name.endswith("-sdr-file"):
                if "hdr-start" not in name and "hdr-file" not in name:
                    assert value["video_params"]["gamma"] not in ("pq", "hlg"), "SDR test source was HDR"
            if "hdr-start" in name or "hdr-file" in name or name.startswith("hdr-") and "playlist" not in name:
                if "sdr-file" not in name:
                    assert value["video_params"]["gamma"] == "pq", "HDR test source was not PQ"
            summary["tests"][name] = value
            (output / "summary.json").write_text(json.dumps(summary, indent=2))
            print(f"PASS {name}: {value['metal_colorspace']}, settled drops={value['frame_drops_settled_interval']}", flush=True)

        # Fullscreen transitions move a real, continuously playing window. The
        # current display and Metal layer are verified, not inferred from flags.
        for source_name, source, start, other, source_hdr in [
            ("hdr", args.hdr_video, hdr_index, sdr_index, True),
            ("sdr", args.sdr_video, sdr_index, hdr_index, False),
        ]:
            player = Player(config, output, source_name + "-transitions", source, start)
            try:
                record(source_name + "-start", player, start, source_hdr)
                player.command("set_property", "fs-screen", other)
                time.sleep(.5)  # Allow macvk's option cache to observe the new target.
                player.command("set_property", "fullscreen", True)
                record(source_name + "-moved", player, other, False)
                player.command("set_property", "fullscreen", False)
                time.sleep(1.5)
                player.command("set_property", "fs-screen", start)
                time.sleep(.5)
                player.command("set_property", "fullscreen", True)
                record(source_name + "-returned", player, start, source_hdr)
                if not source_hdr:
                    assert "ITUR_2100_PQ" not in player.text(), "SDR source was signaled as PQ"
                    assert "+ VK_COLOR_SPACE_HDR10_ST2084_EXT" not in player.text(), "SDR source used a PQ surface"
            finally:
                player.close()

        player = Player(config, output, "sdr-direct-hdr", args.sdr_video, hdr_index)
        try:
            record("sdr-direct-hdr", player, hdr_index, False)
            assert "ITUR_2100_PQ" not in player.text()
        finally:
            player.close()

        # Direct startup on the other display and file changes without restarting.
        for index, label in [(sdr_index, "sdr-display"), (hdr_index, "hdr-display")]:
            player = Player(config, output, label + "-playlist", args.hdr_video, index)
            try:
                record(label + "-hdr-start", player, index, index == hdr_index)
                player.expected_path = str(args.sdr_video.resolve())
                player.command("loadfile", player.expected_path, "replace")
                time.sleep(.5)
                record(label + "-sdr-file", player, index, False)
                player.expected_path = str(args.hdr_video.resolve())
                player.command("loadfile", player.expected_path, "replace")
                time.sleep(.5)
                record(label + "-hdr-file", player, index, index == hdr_index)
            finally:
                player.close()
        # Files generated from lavfi contain no third-party footage. Metadata
        # edge cases verify policy/signaling, not perceptual HLG fidelity.
        variants = [("missing", []), ("ambiguous-pq", ["-color_trc", "smpte2084", "-color_primaries", "bt709"]),
                    ("hlg", ["-color_trc", "arib-std-b67", "-color_primaries", "bt2020"]),
                    ("wide-sdr", ["-color_trc", "iec61966-2-1", "-color_primaries", "smpte432"])]
        for label, tags in variants:
            clip = Path(temporary) / (label + ".mkv")
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24",
                            "-t", "3", "-c:v", "ffv1", "-threads", "2", *tags, str(clip)], check=True)
            for index, screen_label in [(sdr_index, "sdr"), (hdr_index, "hdr")]:
                player = Player(config, output, label + "-" + screen_label, clip, index)
                try:
                    record(label + "-" + screen_label, player, index, False)
                    assert "ITUR_2100_PQ" not in player.text()
                finally:
                    player.close()
    print(f"Physical integration: {len(summary['tests'])} stages passed; private logs in {output}")


if __name__ == "__main__":
    main()
