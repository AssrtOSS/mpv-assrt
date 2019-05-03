--[[
    assrt.lua

    Description: Search subtitle on assrt.net
    Version:     1.0.1
    Author:      AssrtOpensource
    URL:         https:-- github.com/AssrtOSS/mpv-assrt
    License:     Apache License, Version 2.0
]] --

-- luacheck: globals mp read_options

local Ass = require("modules.AssFormat")
local SelectionMenu = require("modules.SelectionMenu")

require("mp.options")
local utils = require("mp.utils")

local VERSION = "1.0.1"

local ASSRT = {}

local tmpDir

local function getenv(n)
  local result =
    utils.subprocess(
    {
      args = {"echo", "$" .. n},
      cancellable = false
    }
  )
  return result and result.stdout
end

local function getTmpDir()
  if not tmpDir then
    local temp = getenv("TEMP") or getenv("TMP")
    if temp then
      -- is windows
      tmpDir = temp
    else
      tmpDir = "/tmp"
    end
  end
  return tmpDir
end

local function testDownloadTool()
  local _UA = mp.get_property("mpv-version"):gsub(" ", "/") .. " assrt-" .. VERSION
  local UA = "User-Agent: " .. _UA
  local cmds = {
    {"curl", "-SLs", "-H", UA},
    {"wget", "-q", "--header", UA, "-O", "-"},
    {
      "powershell",
      ' Invoke-WebRequest -UserAgent "' .. _UA .. '"  -ContentType "application/json charset=utf-8" -URI '
    }
  }
  -- cscript is not avaiable under windows because of missing API
  -- in Lua hook. Need at least mp.script_path or mp.utils.write_file
  for i = 1, #cmds do
    local result =
      utils.subprocess(
      {
        args = {cmds[i][1], "-h"},
        cancellable = false
      }
    )
    if type(result.stdout) == "string" and result.status ~= -1 then
      mp.msg.info("selected: ", cmds[i][1])
      return cmds[i]
    end
  end
  return
end

local function httpget(args, url, saveFile)
  local tbl = {}
  for i, arg in ipairs(args) do
    tbl[i] = arg
  end
  args = tbl

  local isSaveFile = (saveFile ~= nil)
  saveFile = saveFile or utils.join_path(getTmpDir(), ".assrt-helper.tmp")

  if args[1] == "powershell" then
    args[#args.length] = args[#args.length] .. '"' .. url .. '" -Outfile "' .. saveFile .. '"'
  else
    if args[1] == "cscript" then
      table.insert(args, url, saveFile)
    else
      if isSaveFile then
        if args[1] == "wget" then
          args[#args] = nil -- pop "-"
        else
          table.insert(args, "-o")
        end
        table.insert(args, saveFile)
      end
      table.insert(args, url)
    end

    local result =
      utils.subprocess(
      {
        args = args,
        cancellable = true
      }
    )

    if result.stderr or result.status ~= 0 then
      mp.msg.error(result.stderr or ("subprocess exit with code " .. result.status))
      return
    end

    if isSaveFile then
      -- TODO: check file sanity
      return true
    else
      if args[1] == "powershell" or args[1] == "cscript" then
        return utils.read_file(saveFile)
      else
        return result.stdout
      end
    end
  end
end

function ASSRT.new(options)
  options = options or {}
  local tbl = {}

  tbl.cmd = nil
  tbl.apiToken = options.apiToken
  tbl.useHttps = options.useHttps

  tbl._list_map = {}
  tbl._enableColor = mp.get_property_bool("vo-configured") or true
  tbl._menu_state = {}

  tbl.menu =
    SelectionMenu.new(
    {
      maxLines = options.maxLines,
      menuFontSize = options.menuFontSize,
      autoCloseDelay = options.autoCloseDelay,
      keyRebindings = options.keyRebindings
    }
  )
  tbl.menu:setMetadata({type = nil})
  tbl.menu:setUseTextColors(tbl._enableColor)

  -- callbacks
  local _open = function()
    table.insert(
      tbl._menu_state,
      {
        type = tbl.menu:getMetadata().type,
        options = tbl.menu.options,
        list_map = tbl._list_map,
        title = tbl.menu.title,
        idx = tbl.menu.selectionIdx,
        ass_esc = Ass.esc
      }
    )

    local selectedItem = tbl.menu:getSelectedItem()
    tbl.menu:hideMenu()

    local call_map = {
      list = tbl.getSubtitleDetail,
      detail = tbl.downloadSubtitle
    }
    call_map[tbl.menu:getMetadata().type](tbl, selectedItem)
  end
  tbl.menu:setCallbackMenuOpen(_open)
  tbl.menu:setCallbackMenuRight(_open)

  tbl.menu:setCallbackMenuHide(
    function()
      -- restore escape function if needed
      if Ass._old_esc then
        Ass.esc = Ass._old_esc
        Ass._old_esc = nil
      end
    end
  )

  local _undo = function()
    if #tbl._menu_state == 0 then
      tbl.menu:hideMenu()
      return
    end
    local state = tbl._menu_state[#tbl._menu_state]
    tbl._menu_state[#tbl._menu_state] = nil
    tbl._list_map = state.list_map
    Ass.esc = state.ass_esc
    tbl.menu:getMetadata().type = state.type
    tbl.menu:setTitle(state.title)
    tbl.menu:setOptions(state.options, state.idx)
    tbl.menu:renderMenu()
  end
  tbl.menu:setCallbackMenuUndo(_undo)
  tbl.menu:setCallbackMenuLeft(_undo)

  return setmetatable(tbl, {__index = ASSRT})
end

local function _showOsdColor(self, output, duration, color)
  local c = self._enableColor
  local _originalFontSize = mp.get_property_number("osd-font-size")
  mp.set_property("osd-font-size", self.menu.menuFontSize)
  mp.osd_message(
    Ass.startSeq(c) .. Ass.color(color, c) .. Ass.scale(75, c) .. Ass.esc(output, c) .. Ass.stopSeq(c),
    duration
  )
  mp.set_property("osd-font-size", _originalFontSize)
end

function ASSRT:showOsdError(output, duration)
  _showOsdColor(self, output, duration, "FE2424")
end

function ASSRT:showOsdInfo(output, duration)
  _showOsdColor(self, output, duration, "F59D1A")
end

function ASSRT:showOsdOk(output, duration)
  _showOsdColor(self, output, duration, "90FF90")
end

function ASSRT:api(uri, arg)
  if not self.cmd then
    self.cmd = testDownloadTool()
  end
  if not self.cmd then
    mp.msg.error("no wget or curl found")
    self:showOsdError("ASSRT: 没有找到wget和curl，无法运行", 2)
    return
  end

  local url =
    (self.useHttps and "https" or "http") ..
    "://api.assrt.net/v1" .. uri .. "?token=" .. self.apiToken .. "&" .. (arg and arg or "")
  local ret = httpget(self.cmd, url)
  if not ret then
    return
  end

  local err

  ret, err = utils.parse_json(ret)
  if err then
    mp.msg.error(err)
    return
  end
  if ret.status > 0 then
    mp.msg.error("API failed with code: " .. ret.status .. ", message: " .. ret.errmsg)
    return
  end
  return ret
end

local function formatLang(s, output)
  s = Ass._old_esc(s)
  if not output then
    return s
  end
  local color_list = {
    ["英"] = "00247D",
    ["简"] = "f40002",
    ["繁"] = "000098",
    ["双语"] = "ffffff"
  }
  return s:gsub(
    "%S+",
    function(match)
      local c = color_list[match]
      if c then
        return Ass.color(c, true) .. match .. Ass.white(true)
      else
        return Ass.color("8e44ad", true) .. match .. Ass.white(true)
      end
    end
  ) .. Ass.white(true)
end

-- https://github.com/daurnimator/lua-http/blob/master/http/util.lua
local function char_to_pchar(c)
  return string.format("%%%02X", c:byte(1, 1))
end

local function encodeURIComponent(s)
  return s:gsub("[^%w%-_%.%!%~%*%'%(%)]", char_to_pchar)
end

function ASSRT:searchSubtitle()
  self:showOsdInfo("正在搜索字幕...", 2)
  local fpath = mp.get_property("path", " ")
  local _, fname = utils.split_path(fpath)
  local try_args = {"is_file", "no_muxer"}
  local ret
  fname = fname:gsub("[%(%)~]", "")
  for i = 1, 2 do
    ret = self:api("/sub/search", "q=" .. encodeURIComponent(fname) .. "&" .. try_args[i] .. "=1")
    if ret and #ret.sub.subs > 0 then
      break
    end
  end
  if not ret then
    if self.cmd then -- don't overlap cmd error
      self:showOsdError("API请求错误，请检查控制台输出", 2)
    end
    return
  end
  if #ret.sub.subs == 0 then -- ????
    self:showOsdOk("没有符合条件的字幕", 1)
    return
  end

  local menuOptions = {}
  local initialSelectionIdx = 0
  self._list_map = {}

  local sublist = ret.sub.subs
  if not Ass._old_esc then
    Ass._old_esc = Ass.esc
    -- disable escape temporarily
    Ass.esc = function(str, _)
      return str
    end
  end
  for i = 1, #sublist do
    local title = Ass._old_esc(sublist[i].native_name)
    if title == "" then
      title = Ass._old_esc(sublist[i].videoname)
    end
    if sublist[i].release_site ~= nil then
      title =
        Ass.alpha("88", self._enableColor) ..
        (self._enableColor and "" or "[") ..
          Ass._old_esc(sublist[i].release_site) ..
            (self._enableColor and "  " or "]  ") ..
              Ass.alpha("00", self._enableColor) ..
                Ass.alpha("55", self._enableColor) .. title .. Ass.alpha("00", self._enableColor)
    end
    if sublist[i].lang ~= nil then
      title =
        title ..
        (self._enableColor and "  " or "  [") ..
          formatLang(sublist[i].lang.desc, self._enableColor) .. (self._enableColor and "  " or "]  ")
    end
    table.insert(menuOptions, title)
    self._list_map[title] = ret.sub.subs[i].id
    -- if (selectEntry == sub)
    --    initialSelectionIdx = menuOptions.length - 1
  end

  self.menu:getMetadata().type = "list"

  self.menu:setTitle("选择字幕")
  self.menu:setOptions(menuOptions, initialSelectionIdx)
  self.menu:renderMenu()
end

function ASSRT:getSubtitleDetail(selection)
  self:showOsdInfo("正在获取字幕详情...", 2)
  local id = self._list_map[selection]

  local ret = self:api("/sub/detail", "id=" .. id)
  if not ret and self.cmd then -- don't overlap cmd error
    self:showOsdError("API请求错误，请检查控制台输出", 2)
    return
  end

  local title
  local menuOptions = {}
  local initialSelectionIdx = 0

  self._list_map = {}

  local filelist = ret.sub.subs[1].filelist
  for i = 1, #filelist do
    title = filelist[i].f
    table.insert(menuOptions, title)
    self._list_map[title] = filelist[i].url
    -- if (selectEntry == sub)
    --    initialSelectionIdx = menuOptions.length - 1
  end
  -- if filelist is empty and file is not archive
  if menuOptions.length == 0 and ret.sub.subs[1].filename:gmatch("%.(rar|zip|7z)$") == nil then
    title = ret.sub.subs[1].filename
    table.insert(menuOptions, title)
    self._list_map[title] = ret.sub.subs[1].url
  end

  self.menu:getMetadata().type = "detail"

  self.menu:setTitle("下载字幕")
  self.menu:setOptions(menuOptions, initialSelectionIdx)
  self.menu:renderMenu()
end

function ASSRT:downloadSubtitle(selection)
  local url = self._list_map[selection]

  self:showOsdInfo("正在下载字幕...", 10)

  local saveFile
  local mediaPath = mp.get_property("path", " ")
  -- use the same directory as mediaPath by default
  local _dir, _ = utils.split_path(mediaPath)
  if mediaPath and mediaPath:match("^%a+://") then
    -- is web, use temp path
    _dir = getTmpDir()
  end
  saveFile = utils.join_path(_dir, selection)

  local ret = httpget(self.cmd, url, saveFile)

  if not ret then
    self:showOsdError("字幕下载失败，请检查控制台输出", 2)
    return
  end

  self:showOsdOk("字幕已下载", 2)
  mp.commandv("sub-add", saveFile)
end

local function init()
  local userConfig = {
    api_token = "tNjXZUnOJWcHznHDyalNMYqqP6IdDdpQ",
    use_https = true,
    auto_close = 5,
    max_lines = 15,
    font_size = 24
  }
  read_options(userConfig)

  -- Create and initialize the media browser instance.
  local assrt
  local status, err =
    pcall(
    function()
      assrt =
        ASSRT.new(
        {
          apiToken = userConfig["api_token"],
          useHttps = userConfig["use_https"],
          autoCloseDelay = userConfig["auto_close"],
          maxLines = userConfig["max_lines"],
          menuFontSize = userConfig["font_size"]
        }
      )
    end
  )
  if not status then
    mp.msg.error("ASSRT: " .. err .. ".")
    mp.osd_message("ASSRT: " .. err .. ".", 3)
    error(err) -- Critical init error. Stop script execution.
  end

  -- Provide the bindable mpv command which opens/cycles through the menu.
  -- Bind self via input.conf: `a script-binding assrt`.
  mp.add_key_binding(
    "a",
    "assrt-lua",
    function()
      assrt:searchSubtitle()
    end
  )
  mp.msg.info("loaded assrt Lua flavor")
end

init()
