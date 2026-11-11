// SPDX-License-Identifier: GPL-2.0-only
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const LABELS = {
    '30s': 'Keyboard backlight: off after 30 s',
    '3min': 'Keyboard backlight: off after 3 min',
    'always': 'Keyboard backlight: always on',
};

export default class KbdBacklightTimeoutOsd extends Extension {
    enable() {
        this._cancellable = new Gio.Cancellable();
        this._proc = Gio.Subprocess.new(
            ['python3', GLib.build_filenamev([this.path, 'watch.py'])],
            Gio.SubprocessFlags.STDOUT_PIPE);
        this._stream = new Gio.DataInputStream({
            base_stream: this._proc.get_stdout_pipe(),
            close_base_stream: true,
        });
        this._readLine();
    }

    _readLine() {
        this._stream.read_line_async(GLib.PRIORITY_DEFAULT, this._cancellable, (stream, res) => {
            let line;
            try {
                [line] = stream.read_line_finish_utf8(res);
            } catch (e) {
                return;
            }
            if (line === null)
                return;
            this._show(line.trim());
            this._readLine();
        });
    }

    _show(value) {
        const label = LABELS[value] ?? `Keyboard backlight timeout: ${value}`;
        const icon = Gio.ThemedIcon.new('keyboard-brightness-symbolic');
        const osd = Main.osdWindowManager;
        if (typeof osd.showAll === 'function')
            osd.showAll(icon, label, null, null);
        else
            osd.show(-1, icon, label, null, null);
    }

    disable() {
        this._cancellable?.cancel();
        this._proc?.force_exit();
        this._cancellable = null;
        this._proc = null;
        this._stream = null;
    }
}
