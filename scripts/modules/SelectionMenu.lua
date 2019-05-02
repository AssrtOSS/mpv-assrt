--[[
    SELECTIONMENU.LUA (MODULE)

    Version:     1.2.0
    Original:    VideoPlayerCode (Javascipt)
    Author:      AssrtOSS
    URL:         https://github.com/VideoPlayerCode/mpv-tools
    License:     Apache License, Version 2.0
]] --

-- luacheck: globals mp

local Ass = require("modules.AssFormat")
local Utils = require("modules.MicroUtils")

local utils = require("mp.utils")

local SelectionMenu = {}

SelectionMenu.new = function(settings)
  settings = settings or {}
  local tbl = {}

  tbl.uniqueId = "M" .. tostring(mp.get_time()):gsub("%.", ""):sub(4) .. tostring(math.random(100, 999))
  tbl.metadata = nil
  tbl.title = "No title"
  tbl.options = {}
  tbl.selectionIdx = 0
  tbl.cbMenuShow = type(settings.cbMenuShow) == "function" and settings.cbMenuShow or nil
  tbl.cbMenuHide = type(settings.cbMenuHide) == "function" and settings.cbMenuHide or nil
  tbl.cbMenuLeft = type(settings.cbMenuLeft) == "function" and settings.cbMenuLeft or nil
  tbl.cbMenuRight = type(settings.cbMenuRight) == "function" and settings.cbMenuRight or nil
  tbl.cbMenuOpen = type(settings.cbMenuOpen) == "function" and settings.cbMenuOpen or nil
  tbl.cbMenuUndo = type(settings.cbMenuUndo) == "function" and settings.cbMenuUndo or nil
  tbl.maxLines = type(settings.maxLines) == "number" and settings.maxLines >= 3 and math.floor(settings.maxLines) or 10
  tbl.menuFontAlpha =
    Ass.convertPercentToHex( -- Throws if invalid input.
    ((type(settings.menuFontAlpha) == "number" and settings.menuFontAlpha >= 0 and settings.menuFontAlpha <= 1) and
      settings.menuFontAlpha or
      1),
    true -- Invert input range so "1.0" is visible and "0.0" is invisible.
  )
  tbl.menuFontSize =
    type(settings.menuFontSize) == "number" and settings.menuFontSize >= 1 and math.floor(settings.menuFontSize) or 40
  tbl.originalFontSize = nil
  tbl.hasRegisteredKeys = false -- Also means that menu is active/open.
  tbl.useTextColors = true
  tbl.currentMenuText = ""
  tbl.isShowingMessage = false
  tbl.currentMessageText = ""
  tbl.menuInterval = nil
  tbl.stopMessageTimeout = nil
  tbl.autoCloseDelay =
    (type(settings.autoCloseDelay) == "number" and
      settings.autoCloseDelay >= 0) and settings.autoCloseDelay or 5 -- 0 = Off.
  tbl.autoCloseActiveAt = 0
  tbl.keyBindings = {
    -- Default keybindings.
    ["Menu-Up"] = {repeatable = true, keys = {"up"}},
    ["Menu-Down"] = {repeatable = true, keys = {"down"}},
    ["Menu-Up-Fast"] = {repeatable = true, keys = {"shift+up"}},
    ["Menu-Down-Fast"] = {repeatable = true, keys = {"shift+down"}},
    ["Menu-Left"] = {repeatable = true, keys = {"left"}},
    ["Menu-Right"] = {repeatable = false, keys = {"right"}},
    ["Menu-Open"] = {repeatable = false, keys = {"enter"}},
    ["Menu-Undo"] = {repeatable = false, keys = {"bs"}},
    ["Menu-Help"] = {repeatable = false, keys = {"h"}},
    ["Menu-Close"] = {repeatable = false, keys = {"esc"}}
  }

  -- Apply custom rebinding overrides if provided.
  -- Format: `{'Menu-Open':['a','shift+b']}`
  -- Note that all "shift variants" MUST be specified as "shift+<key>".
  local rebinds = settings.keyRebindings
  if rebinds then
    for action, allKeys in pairs(rebinds) do
      local erasedDefaults = false
      for i = 1, #allKeys do
        local key = allKeys[i]
        if type(key) == "string" then
          error("Invalid non-string key (" .. utils.format_json(key) .. ") in custom rebindings")
        end
        key = key:lower() -- Unify case of all keys for de-dupe.
        key = Utils.trim(key) -- Trim whitespace.
        if key:len() > 0 then
          if not erasedDefaults then -- Erase default keys for tbl action.
            erasedDefaults = true
            tbl.keyBindings[action].keys = {}
          end
        end
        table.insert(tbl.keyBindings[action].keys, key)
      end
    end
  end

  -- Verify that no duplicate bindings exist for the same key.
  local boundKeys = {}
  for action in pairs(tbl.keyBindings) do
    local allKeys = tbl.keyBindings[action].keys
    for i = 1, #allKeys do
      local key = allKeys[i]
      if boundKeys[key] then
        error('Invalid duplicate menu bindings for key "' .. key .. '" (detected in action "' .. action .. '")')
      end
      boundKeys[key] = true
    end
  end

  return setmetatable(tbl, {__index = SelectionMenu})
end

function SelectionMenu:setMetadata(metadata)
  self.metadata = metadata
end

function SelectionMenu:getMetadata()
  return self.metadata
end

function SelectionMenu:setTitle(newTitle)
  if type(newTitle) ~= "string" then
    error("setTitle: No title value provided")
  end
  self.title = newTitle
end

function SelectionMenu:setOptions(newOptions, initialSelectionIdx)
  if type(newOptions) == "undefined" then
    error("setOptions: No options value provided")
  end
  self.options = newOptions
  self.selectionIdx =
    (type(initialSelectionIdx) == "number" and initialSelectionIdx >= 0 and initialSelectionIdx < #newOptions) and
    initialSelectionIdx or
    0
end

function SelectionMenu:setCallbackMenuShow(newCbMenuShow)
  self.cbMenuShow = type(newCbMenuShow) == "function" and newCbMenuShow or nil
end

function SelectionMenu:setCallbackMenuHide(newCbMenuHide)
  self.cbMenuHide = type(newCbMenuHide) == "function" and newCbMenuHide or nil
end

function SelectionMenu:setCallbackMenuLeft(newCbMenuLeft)
  self.cbMenuLeft = type(newCbMenuLeft) == "function" and newCbMenuLeft or nil
end

function SelectionMenu:setCallbackMenuRight(newCbMenuRight)
  self.cbMenuRight = type(newCbMenuRight) == "function" and newCbMenuRight or nil
end

function SelectionMenu:setCallbackMenuOpen(newCbMenuOpen)
  self.cbMenuOpen = type(newCbMenuOpen) == "function" and newCbMenuOpen or nil
end

function SelectionMenu:setCallbackMenuUndo(newCbMenuUndo)
  self.cbMenuUndo = type(newCbMenuUndo) == "function" and newCbMenuUndo or nil
end

function SelectionMenu:setUseTextColors(value)
  local hasChanged = self.useTextColors ~= value
  self.useTextColors = value ~= nil
  -- Update text cache, and redraw menu if visible (otherwise don't show it).
  if hasChanged then
    self:renderMenu(nil, 1) -- 1 = Only redraw if menu is onscreen.
  end
end

function SelectionMenu:isMenuActive()
  return self.hasRegisteredKeys -- If keys are registered, menu is active.
end

function SelectionMenu:getSelectedItem()
  if self.selectionIdx < 0 or self.selectionIdx >= #self.options then
    return ""
  else
    return self.options[self.selectionIdx + 1]
  end
end

function SelectionMenu:_processBindings(fnCb)
  if type(fnCb) ~= "function" then
    error("Missing callback for _processBindings")
  end

  local bindings = self.keyBindings

  for action in pairs(bindings) do
    local allKeys = bindings[action].keys
    for i = 1, #allKeys do
      local key = allKeys[i]
      local identifier = self.uniqueId .. "_" .. action .. "_" .. key
      fnCb(
        identifier, -- Unique identifier for this binding.
        action, -- What action the key is assigned to trigger.
        key, -- What key.
        bindings[action] -- Details about this binding.
      )
    end
  end
end

function SelectionMenu:_registerMenuKeys()
  if self.hasRegisteredKeys then
    return
  end

  -- Necessary in order to preserve "this" in the called function, since mpv's
  -- callbacks don't receive "this" if the object's func is keybound directly.
  local createFn = function(obj, fn)
    return function()
      obj:_menuAction(fn)
    end
  end

  self:_processBindings(
    function(identifier, action, key, details)
      mp.add_forced_key_binding(
        key, -- What key.
        identifier, -- Unique identifier for the binding.
        createFn(self, action), -- Generate anonymous func to execute.
        {repeatable = details.repeatable} -- Extra options.
      )
    end
  )

  self.hasRegisteredKeys = true
end

function SelectionMenu:_unregisterMenuKeys()
  if not self.hasRegisteredKeys then
    return
  end

  self:_processBindings(
    function(identifier, _, _, _)
      mp.remove_key_binding(
        identifier -- Remove binding by its unique identifier.
      )
    end
  )

  self.hasRegisteredKeys = false
end

function SelectionMenu:_menuAction(action)
  if self.isShowingMessage and action ~= "Menu-Close" then
    return -- Block everything except "close" while showing a message.
  end

  if action == "Menu-Up" or action == "Menu-Down" or action == "Menu-Up-Fast" or action == "Menu-Down-Fast" then
    local maxIdx = #self.options - 1

    if action == "Menu-Up" or action == "Menu-Up-Fast" then
      self.selectionIdx = self.selectionIdx - (action == "Menu-Up-Fast" and 10 or 1)
    else
      self.selectionIdx = self.selectionIdx + (action == "Menu-Down-Fast" and 10 or 1)
    end

    -- Handle wraparound in single-move mode, or clamp in fast-move mode.
    if self.selectionIdx < 0 then
      self.selectionIdx = (action == "Menu-Up-Fast" and 0 or maxIdx)
    elseif self.selectionIdx > maxIdx then
      self.selectionIdx = (action == "Menu-Down-Fast" and maxIdx or 0)
    end

    self:renderMenu()
  elseif action == "Menu-Left" or action == "Menu-Right" or action == "Menu-Open" or action == "Menu-Undo" then
    local cbName = "cb" .. action:gsub("-", "")
    if type(self[cbName]) == "function" then
      -- We don't know what the callback will do, and it may be slow, so
      -- we'll disable the menu's auto-close timeout while it runs.
      self:_disableAutoCloseTimeout() -- Soft-disable.
      self[cbName](action)
    end
  elseif action == "Menu-Help" then
    -- List all keybindings to help the user remember them.
    local entryTitle, allKeys
    local c = self.useTextColors
    local helpLines = 0
    local helpString = Ass.startSeq(c) .. Ass.alpha(self.menuFontAlpha, c)
    local bindings = self.keyBindings
    for entry in pairs(bindings) do
      allKeys = bindings[entry].keys
      if not (entry:match("^Menu-") or not allKeys or #allKeys == 0) then
        entryTitle = entry:sub(5)
        if entryTitle:len() > 0 then
          Utils.quickSort(allKeys, {caseInsensitive = true})
          helpLines = helpLines + 1
          helpString =
            helpString ..
            Ass.yellow(c) ..
              Ass.esc(entryTitle, c) .. ": " .. Ass.white(c) .. Ass.esc("{" .. allKeys.join("}, {") .. "}", c) .. "\n"
        end
      end
    end
    helpString = helpString .. Ass.stopSeq(c)
    if not helpLines then
      helpString = "No help available."
    end
    self:showMessage(helpString, 5000)
  elseif action == "Menu-Close" then
    self:hideMenu()
  else
    mp.msg.error('Unknown menu action "' .. action .. '"')
    return
  end

  self:_updateAutoCloseTimeout() -- Soft-update.
end

function SelectionMenu:_disableAutoCloseTimeout(forceLock)
  self.autoCloseActiveAt = forceLock and -2 or -1 -- -2 = hard, -1 = soft.
end

function SelectionMenu:_updateAutoCloseTimeout(forceUnlock)
  if not forceUnlock and self.autoCloseActiveAt == -2 then
    -- Do nothing while autoclose is locked in "disabled" mode.
    return
  end

  self.autoCloseActiveAt = mp.get_time()
end

function SelectionMenu:_handleAutoClose()
  if self.autoCloseDelay <= 0 or self.autoCloseActiveAt <= -1 then
    -- -2 = hard, -1 = soft.
    -- Do nothing while autoclose is disabled (0) or locked (< 0).
    return
  end

  local now = mp.get_time()
  if self.autoCloseActiveAt <= (now - self.autoCloseDelay) then
    self:hideMenu()
  end
end

function SelectionMenu:_renderActiveText()
  if not self:isMenuActive() then
    return
  end

  -- Determine which text to render (critical messages take precedence).
  local msg = self.isShowingMessage and self.currentMessageText or self.currentMenuText
  if type(msg) ~= "string" then
    msg = ""
  end

  -- Tell mpv's OSD to show the text. It will automatically be replaced and
  -- refreshed every second while the menu remains open, to ensure that
  -- nothing else is able to overwrite our menu text.
  -- NOTE: The long display duration is important, because the JS engine lacks
  -- real threading, so any slow mpv API calls or slow JS functions will delay
  -- our redraw timer! Without a long display duration, the menu would vanish.
  -- NOTE: If a timer misses multiple intended ticks, it will only tick ONCE
  -- when catching up. So there can thankfully never be any large "backlog"!
  mp.osd_message(msg, 1000)
end

function SelectionMenu:renderMenu(selectionPrefix, renderMode)
  local c = self.useTextColors
  local finalString

  -- Title.
  finalString =
    Ass.startSeq(c) ..
    Ass.alpha(self.menuFontAlpha, c) ..
      Ass.gray(c) .. Ass.scale(75, c) .. Ass.esc(self.title, c) .. ":" .. Ass.scale(100, c) .. Ass.white(c) .. "\n\n"

  -- Options.
  if #self.options > 0 then
    -- Calculate start/end offsets around focal point.
    local startIdx = self.selectionIdx - math.floor(self.maxLines / 2)
    if startIdx < 0 then
      startIdx = 0
    end

    local endIdx = startIdx + self.maxLines - 1
    local maxIdx = #self.options - 1
    if endIdx > maxIdx then
      endIdx = maxIdx
    end

    -- Increase number of leading lines if we've reached end of list.
    local lineCount = (endIdx - startIdx) + 1 -- "+1" to count start line too.
    local lineDiff = self.maxLines - lineCount
    startIdx = startIdx - lineDiff
    if startIdx < 0 then
      startIdx = 0
    end

    -- Format and add all output lines.
    local opt
    for i = startIdx, endIdx do
      opt = self.options[i + 1]
      if i == self.selectionIdx then
        -- NOTE: Prefix stays on screen until cursor-move or re-render.
        finalString =
          finalString ..
          Ass.yellow(c) .. "> " .. (type(selectionPrefix) == "string" and (Ass.esc(selectionPrefix, c) .. " ") or "")
      end
      finalString =
        finalString ..
        ((i == startIdx and startIdx > 0) and "..." or
          ((i == endIdx and endIdx < maxIdx) and "..." or Ass.esc(type(opt) == "object" and opt.menuText or opt, c)))
      if i == self.selectionIdx then
        finalString = finalString .. Ass.white(c)
      end
      if i ~= endIdx then
        finalString = finalString .. "\n"
      end
    end
  end

  -- End the Advanced SubStation command sequence.
  finalString = finalString .. Ass.stopSeq(c)

  -- Update cached menu text. But only open/redraw the menu if it's already
  -- active OR if we're NOT being prevented from going out of "hidden" state.
  self.currentMenuText = finalString

  -- Handle render mode:
  -- 1 = Only redraw if menu is onscreen (doesn't trigger open/redrawing if
  -- the menu is closed or busy showing a text message) 2 = Don't show/redraw
  -- at all (good for just updating the text cache silently) any other value
  -- (incl. undefined, aka default) = show/redraw the menu.
  if (renderMode == 1 and (not self:isMenuActive() or self.isShowingMessage)) or renderMode == 2 then
    return
  end
  self:_showMenu()
end

function SelectionMenu:_showMenu()
  local justOpened = false
  if not self:isMenuActive() then
    justOpened = true
    self.originalFontSize = mp.get_property_number("osd-font-size")
    mp.set_property("osd-font-size", self.menuFontSize)
    self:_registerMenuKeys()

    -- Redraw the currently active text every second and do periodic tasks.
    -- NOTE: This prevents other OSD scripts from removing our menu text.
    if self.menuInterval ~= nil then
      self.menuInterval:stop()
    end
    self.menuInterval =
      mp.add_periodic_timer(
      1,
      function()
        self:_renderActiveText()
        self:_handleAutoClose()
      end
    )

    -- Get rid of any lingering "stop message" timeout and message.
    self:stopMessage(true)
  end

  -- Display the currently active text instantly.
  self:_renderActiveText()

  if justOpened then
    -- Run "menu show" callback if registered.
    if type(self.cbMenuShow) == "function" then
      self:_disableAutoCloseTimeout() -- Soft-disable while CB runs.
      self:cbMenuShow("Menu-Show")
    end

    -- Force an update/unlock of the activity timeout when menu opens.
    self:_updateAutoCloseTimeout(true) -- Hard-update.
  end
end

function SelectionMenu:hideMenu()
  if not self:isMenuActive() then
    return
  end

  mp.osd_message("")
  if self.originalFontSize ~= nil then
    mp.set_property("osd-font-size", self.originalFontSize)
  end
  self:_unregisterMenuKeys()
  if self.menuInterval ~= nil then
    self.menuInterval:stop()
    self.menuInterval = nil
  end

  -- Get rid of any lingering "stop message" timeout and message.
  self:stopMessage(true)

  -- Run "menu hide" callback if registered.
  if type(self.cbMenuHide) == "function" then
    self:cbMenuHide("Menu-Hide")
  end
end

function SelectionMenu:showMessage(msg, durationMs, clearSelectionPrefix)
  if not self:isMenuActive() then
    return
  end

  if type(msg) ~= "string" then
    msg = "showMessage: Invalid message value."
  end
  if type(durationMs) ~= "number" then
    durationMs = 800
  end

  local duration
  if durationMs < 1000 then
    duration = 1
  else
    duration = durationMs / 1000
  end

  if clearSelectionPrefix then
    self:renderMenu(nil, 2) -- 2 = Only update text cache (no redraw).
  end

  self.isShowingMessage = true
  self.currentMessageText = msg
  self:_renderActiveText()
  self:_disableAutoCloseTimeout(true) -- Hard-disable (ignore msg idle time).

  if self.stopMessageTimeout ~= nil then
    self.stopMessageTimeout:stop()
  end
  self.stopMessageTimeout =
    mp.add_timeout(
    duration,
    function()
      self:stopMessage()
    end
  )
end

function SelectionMenu:stopMessage(preventRender)
  if self.stopMessageTimeout ~= nil then
    self.stopMessageTimeout:stop()
    self.stopMessageTimeout = nil
  end
  self.isShowingMessage = false
  self.currentMessageText = ""
  if not preventRender then
    self:_renderActiveText()
  end
  self:_updateAutoCloseTimeout(true) -- Hard-update (last user activity).
end

return SelectionMenu
