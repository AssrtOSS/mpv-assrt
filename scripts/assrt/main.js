/*
 * assrt.js
 *
 * Description: Search subtitle on assrt.net
 * Version:     1.1.1
 * Author:      AssrtOpensource
 * URL:         https://github.com/AssrtOSS/mpv-assrt
 * License:     Apache License, Version 2.0
 */

'use strict';

// >= 0.33.0
mp.module_paths.push(mp.get_script_directory());

var Ass = require('AssFormat'),
    SelectionMenu = require('SelectionMenu');

var VERSION = "1.0.4";

var COMMON_PREFIX_KEY = "##common-prefix##";
var RLSITE_KEY = "##release-site##";
var SEARCH_MORE_KEY = "##search-more##";

var tmpDir;

var getTmpDir = function () {
    if (!tmpDir) {
        var temp = mp.utils.getenv("TEMP") ||
            mp.utils.getenv("TMP") ||
            mp.utils.getenv("TMPDIR");
        if (temp) {
            tmpDir = temp;
        } else {
            tmpDir = "/tmp";
        }
    }
    return tmpDir;
}

var fileExists = function (path) {
    if (mp.utils.file_info) { // >= 0.28.0
        return mp.utils.file_info(path);
    }
    try {
        mp.utils.read_file(path, 1)
    } catch (e) {
        return false;
    }
    return true;
}

var testDownloadTool = function () {
    var _UA = mp.get_property("mpv-version").replace(" ", "/") + " assrt-js-" + VERSION;
    var UA = "User-Agent: " + _UA;
    var cmds = [
        ["curl", "-SLs", "-H", UA, "--max-time", "5"],
        ["wget", "-q", "--header", UA, "-O", "-"],
        ["powershell", " Invoke-WebRequest -UserAgent \"" + _UA + "\"  -ContentType \"application/json; charset=utf-8\" -URI "]
    ];
    var _winhelper = mp.utils.split_path(mp.get_script_file())[0] + "win-helper.vbs";
    if (fileExists(_winhelper)) {
        cmds.push(["cscript", "/nologo", _winhelper, _UA]);
    };
    for (var i = 0; i < cmds.length; i++) {
        var result = mp.utils.subprocess({
            args: [cmds[i][0], '-h'],
            cancellable: false
        });
        if (typeof result.stdout === 'string' && result.status != -1) {
            mp.msg.info("selected: ", cmds[i][0]);
            return cmds[i];
        }
    }
    return null;
}

var httpget = function (args, url, saveFile) {
    args = args.slice();
    var isSaveFile = (saveFile != null);
    saveFile = saveFile || mp.utils.join_path(getTmpDir(), ".assrt-helper.tmp");

    if (args[0] == "powershell") {
        args[args.length - 1] += "\"" + url + "\" -Outfile \"" + saveFile + "\"";
    } else if (args[0] == "cscript") {
        args.push(url, saveFile);
    } else {
        if (isSaveFile) {
            if (args[0] == "wget") {
                args.pop(); // pop "-"
            } else {
                args.push("-o");
            }
            args.push(saveFile);
        }
        args.push(url);
    }

    var result = mp.utils.subprocess({
        args: args,
        cancellable: true
    });

    if (result.stderr || result.status != 0) {
        mp.msg.error(result.stderr || ("subprocess exit with code " + result.status));
        return;
    }

    if (isSaveFile) {
        // TODO: check file sanity
        return true;
    } else {
        if (args[0] == "powershell" || args[0] == "cscript") {
            return mp.utils.read_file(saveFile);
        } else {
            return result.stdout;
        }
    }
}

var ASSRT = function (options) {
    options = options || {};
    this.cmd = null;
    this.apiToken = options.apiToken;
    this.useHttps = options.useHttps;
    this.autoRename = options.autoRename;

    this._list_map = {};
    this._enableColor = mp.get_property_bool('vo-configured') || true;
    this._menu_state = [];

    this.menu = new SelectionMenu({
        maxLines: options.maxLines,
        menuFontSize: options.menuFontSize,
        autoCloseDelay: options.autoCloseDelay,
        keyRebindings: options.keyRebindings
    });
    this.menu.setMetadata({
        type: null
    });
    this.menu.setUseTextColors(this._enableColor);

    var self = this;
    // callbacks
    var _open = function () {
        self._menu_state.push({
            type: self.menu.getMetadata().type,
            options: self.menu.options,
            list_map: self._list_map,
            title: self.menu.title,
            idx: self.menu.selectionIdx,
            ass_esc: Ass.esc,
        });

        var selectedItem = self.menu.getSelectedItem();
        self.menu.hideMenu();
        switch (self.menu.getMetadata().type) {
            case "list":
                self.getSubtitleDetail(selectedItem);
                break;
            case "detail":
                self.downloadSubtitle(selectedItem);
                break;
        }
    }
    this.menu.setCallbackMenuOpen(_open);
    this.menu.setCallbackMenuRight(_open);

    this.menu.setCallbackMenuHide(function () {
        // restore escape function if needed
        if (Ass._old_esc) {
            Ass.esc = Ass._old_esc;
            Ass._old_esc = null;
        }
    });

    var _undo = function () {
        if (!self._menu_state.length) {
            self.menu.hideMenu();
            return;
        }
        var state = self._menu_state.pop();
        self._list_map = state.list_map;
        Ass.esc = state.ass_esc;
        self.menu.getMetadata().type = state.type;
        self.menu.setTitle(state.title);
        self.menu.setOptions(state.options, state.idx);
        self.menu.renderMenu();
    }
    this.menu.setCallbackMenuUndo(_undo);
    this.menu.setCallbackMenuLeft(_undo);
};

var _showOsdColor = function (self, output, duration, color) {
    var c = self._enableColor;
    var _originalFontSize = mp.get_property_number('osd-font-size');
    mp.set_property('osd-font-size', self.menu.menuFontSize);
    mp.osd_message(Ass.startSeq(c) + Ass.color(color, c) + Ass.scale(75, c) + Ass.esc(output, c) + Ass.stopSeq(c), duration);
    mp.set_property('osd-font-size', _originalFontSize);
}

ASSRT.prototype.showOsdError = function (output, duration) {
    _showOsdColor(this, output, duration, "FE2424");
}

ASSRT.prototype.showOsdInfo = function (output, duration) {
    _showOsdColor(this, output, duration, "F59D1A");
}

ASSRT.prototype.showOsdOk = function (output, duration) {
    _showOsdColor(this, output, duration, "90FF90");
}

ASSRT.prototype.api = function (uri, arg) {
    if (!this.cmd) {
        this.cmd = testDownloadTool();
    }
    if (!this.cmd) {
        mp.msg.error("no wget or curl found");
        this.showOsdError("ASSRT: 没有找到wget和curl，无法运行", 2);
        return;

    }

    var url = (this.useHttps ? "https" : "http") + "://api.assrt.net/v1" + uri + "?token=" + this.apiToken + "&" + (arg ? arg : "");
    var ret = httpget(this.cmd, url);

    try {
        // https://bugs.ghostscript.com/show_bug.cgi?id=697891
        // Let's replace \/ with #@#
        ret = ret.replace(/\\\//g, '#@#');
        ret = JSON.parse(ret);
    } catch (e) {
        mp.msg.error(e);
        return null;
    }
    if (ret.status) {
        mp.msg.error("API failed with code: " + ret.status + ", message: " + ret.errmsg);
        return null;
    }
    return ret;

}

var formatLang = function (s, output) {
    s = Ass._old_esc(s)
    if (!output) {
        return s;
    }
    var color_list = {
        "英": "00247D",
        "简": "f40002",
        "繁": "000098",
        "双语": "ffffff",
    }
    return s.replace(/([^\s]+)/g, function (match) {
        var c = color_list[match]
        if (c) {
            return Ass.color(c, true) + match + Ass.white(true);
        } else {
            return Ass.color("8e44ad", true) + match + Ass.white(true);
        }
    }) + Ass.white(true);;
}

ASSRT.prototype.searchSubtitle = function (no_muxer_only) {
    this.showOsdInfo("正在搜索字幕...", 2);
    var fpath = mp.get_property("path", " ");
    var fname = mp.utils.split_path(fpath);
    var try_args = ["is_file", "no_muxer"];
    fname = fname[1].replace(/[\(\)~]/g, "");
    var sublist = [];
    var already_try_no_muxer = false;
    for (var i = no_muxer_only? 1: 0; i < try_args.length; i++) {
        already_try_no_muxer = i == try_args.length - 1;
        var ret = this.api("/sub/search", "q=" + encodeURIComponent(fname) + "&" + try_args[i] + "=1");
        if (ret && ret.sub.subs.length > 0) {
            sublist = sublist.concat(ret.sub.subs);
            if (sublist.length >= 3) {
                break;
            }
        }
    }
    if (!sublist) {
        if (this.cmd) //don't overlap cmd error
            this.showOsdError("API请求错误，请检查控制台输出", 2);
        return;
    } else if (sublist.length == 0) { //????
        this.showOsdOk("没有符合条件的字幕", 1);
        return;
    }

    var i, title,
        menuOptions = [],
        initialSelectionIdx = 0;

    this._list_map = {};

    if (!Ass._old_esc) {
        Ass._old_esc = Ass.esc;
        // disable escape temporarily
        Ass.esc = function (str, escape) {
            return str;
        };
    }
    var seen = {};
    for (i = 0; i < sublist.length; ++i) {
        var id = sublist[i].id;
        if (seen[id]) {
            continue;
        }
        seen[id] = true;
        // Replace #@# back to /
        title = Ass._old_esc(sublist[i].native_name.replace(/#@#/g, '/'));
        if (title == "")
            title = Ass._old_esc(sublist[i].videoname.replace(/#@#/g, '/'));
        if (sublist[i].release_site != null) {
            title = Ass.alpha("88", this._enableColor) +
                (this._enableColor ? "" : "[") +
                Ass._old_esc(sublist[i].release_site.replace(/#@#/g, '/')) +
                (this._enableColor ? "  " : "]  ") +
                Ass.alpha("00", this._enableColor) +
                Ass.alpha("55", this._enableColor) +
                title +
                Ass.alpha("00", this._enableColor);
        }
        if (sublist[i].lang != null) {
            title += (this._enableColor ? "  " : "  [") +
                formatLang(sublist[i].lang.desc, this._enableColor) +
                (this._enableColor ? "  " : "]  ");
        }
        if (!this._list_map[title]) {
            menuOptions.push(title);
            this._list_map[title] = sublist[i].id;
        }
        //if (selectEntry === sub)
        //    initialSelectionIdx = menuOptions.length - 1;
    }

    if (!already_try_no_muxer) {
        var t = Ass.alpha("A0", this._enableColor) +
                "查找更多..." +
                Ass.alpha("00", this._enableColor);
        menuOptions.push(t);
        this._list_map[t] = SEARCH_MORE_KEY;
    }

    this.menu.getMetadata().type = "list";

    this.menu.setTitle("选择字幕");
    this.menu.setOptions(menuOptions, initialSelectionIdx);
    this.menu.renderMenu();

};

// https://github.com/NemoAlex/glutton/blob/master/src/services/util.js#L32
function findCommon(names) {
    if (names.length == 1) {
        return null;
    }
    var name = names[0];
    if (name === null) return null;

    var common = '';
    for (var i = 1; i < name.length; i++) {
        var test = name.substring(0, i);
        var success = true;
        for (var j = 1; j < names.length; j++) {
            if (names[j].substring(0, i) != test) {
                success = false
                break
            }
        }
        if (!success) {
            break
        }
        common = test
    }
    return common.length;
}

ASSRT.prototype.getSubtitleDetail = function (selection) {
    var id = this._list_map[selection];
    if(id == SEARCH_MORE_KEY) {
        return this.searchSubtitle(true);
    }

    this.showOsdInfo("正在获取字幕详情...", 2);

    var ret = this.api("/sub/detail", "id=" + id);
    if (!ret) {
        if (this.cmd) //don't overlap cmd error
            this.showOsdError("API请求错误，请检查控制台输出", 2);
        return;
    }

    var i, title,
        menuOptions = [],
        initialSelectionIdx = 0;

    this._list_map = {};

    var filelist = ret.sub.subs[0].filelist;
    var fnames = [];
    for (var i = 0; i < filelist.length; ++i) {
        // Replace #@# back to /
        title = filelist[i].f;
        menuOptions.push(title);
        fnames.push(title);
        this._list_map[title] = filelist[i].url.replace(/#@#/g, '/');
        //if (selectEntry === sub)
        //    initialSelectionIdx = menuOptions.length - 1;
    }


    this._list_map[COMMON_PREFIX_KEY] = findCommon(fnames)

    var rlsite = ret.sub.subs[0].release_site;
    this._list_map[RLSITE_KEY] = rlsite == "个人" ? null : rlsite;

    // if filelist is empty and file is not archive
    if (menuOptions.length == 0 && ret.sub.subs[0].filename.match(/\.(rar|zip|7z)$/) === null) {
        title = ret.sub.subs[0].filename
        menuOptions.push(title);
        this._list_map[title] = ret.sub.subs[0].url.replace(/#@#/g, '/');
    }

    this.menu.getMetadata().type = "detail";

    this.menu.setTitle("下载字幕");
    this.menu.setOptions(menuOptions, initialSelectionIdx);
    this.menu.renderMenu();

};

ASSRT.prototype.downloadSubtitle = function (selection) {
    var url = this._list_map[selection];

    this.showOsdInfo("正在下载字幕...", 10);

    var saveFile;
    var mediaPath = mp.get_property("path", " ");
    // use the same directory as mediaPath by default
    var _dir = mp.utils.split_path(mediaPath)[0];
    if (mediaPath && mediaPath.match(/^[^:]+:\/\//)) {
        // is web, use temp path
        _dir = getTmpDir();
    }
    var fname = selection;
    if (this.autoRename) {
        var mname = mp.get_property("filename/no-ext", " ");
        if (mname) {
            // rlsite
            if (this._list_map[RLSITE_KEY]) {
                mname = mname + "." + this._list_map[RLSITE_KEY];
            }
            // partial without common prefix
            var common_len = this._list_map[COMMON_PREFIX_KEY];
            var suffix;
            if (common_len) {
                suffix = selection.substring(common_len);
            }
            if (!suffix) { // nothing left? use extension
                suffix = selection.match(/(\.[^\.]+)$/)[0];
            } else if (suffix.substring(0, 1) != ".") {
                mname = mname + ".";
            }
            fname = mname + suffix;
        }
    }
    saveFile = mp.utils.join_path(_dir, fname);

    var ret;
    for (var i = 1; i <= 3; i ++) {
        ret = httpget(this.cmd, url, saveFile);
        if (ret) break;
        this.showOsdInfo("字幕下载失败，重试" + i, 2)
    }

    if (!ret) {
        this.showOsdError("字幕下载失败，请检查控制台输出", 2);
        return;
    }

    this.showOsdOk("字幕已下载", 2);
    mp.commandv("sub-add", saveFile);


};

(function () {
    // object will be mofied in place
    var userConfig = {
        api_token: "tNjXZUnOJWcHznHDyalNMYqqP6IdDdpQ",
        use_https: true,
        auto_close: 5,
        max_lines: 15,
        font_size: 24,
        auto_rename: true,
    };
    if (mp.options) {
        mp.options.read_options(userConfig, "assrt");
    } else {
        var Options = require('Options')
        new Options.read_options(userConfig, "assrt");
    }

    // Create and initialize the media browser instance.
    try {
        var assrt = new ASSRT({ // Throws.
            apiToken: userConfig['api_token'],
            useHttps: userConfig['use_https'],
            autoCloseDelay: userConfig['auto_close'],
            maxLines: userConfig['max_lines'],
            menuFontSize: userConfig['font_size'],
            autoRename: userConfig['auto_rename'],
        });
    } catch (e) {
        mp.msg.error('ASSRT: ' + e + '.');
        mp.osd_message('ASSRT: ' + e + '.', 3);
        throw e; // Critical init error. Stop script execution.
    }

    // Provide the bindable mpv command which opens/cycles through the menu.
    // * Bind this via input.conf: `a script-binding assrt`.
    mp.add_key_binding('a', 'assrt', function () {
        assrt.searchSubtitle();
    });
    mp.msg.info("loaded assrt Javscript flavor")
})();

