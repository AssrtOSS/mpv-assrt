--[[
    ASSFORMAT.LUA (MODULE)

    Version:     1.2.0
    Original:    VideoPlayerCode (Javascipt)
    Author:      AssrtOSS
    URL:         https://github.com/VideoPlayerCode/mpv-tools
    License:     Apache License, Version 2.0
]] --

-- luacheck: globals mp

local Utils = require("modules.MicroUtils")

local Ass = {}

Ass._startSeq = mp.get_property_osd("osd-ass-cc/0")

Ass._stopSeq = mp.get_property_osd("osd-ass-cc/1")

Ass.startSeq = function(output)
  return output == false and "" or Ass._startSeq
end

Ass.stopSeq = function(output)
  return output == false and "" or Ass._stopSeq
end

Ass.esc = function(str, escape)
  if escape == false then -- Conveniently disable escaping via the same call.
    return str
  end
  -- Uses the same technique as mangle_ass() in mpv's osd_libass.c:
  -- - Treat backslashes as literal by inserting a U+2060 WORD JOINER after
  --   them so libass can't interpret the next char as an escape sequence.
  -- - Replace `{` with `\{` to avoid opening an ASS override block. There is
  --   no need to escape the `}` since it's printed literally when orphaned.
  -- - See: https://github.com/libass/libass/issues/194#issuecomment-351902555
  -- \u2060 -> '\xe2\x81\xa0'
  return str:gsub("\\", "\\\226\129\160"):gsub("{", "\\{")
end

Ass.size = function(fontSize, output)
  return output == false and "" or "{\\fs" .. fontSize .. "}"
end

Ass.scale = function(scalePercent, output)
  return output == false and "" or "{\\fscx" .. scalePercent .. "\\fscy" .. scalePercent .. "}"
end

Ass.convertPercentToHex = function(percent, invertValue)
  -- Tip: Use with "invertValue" to convert input range 0.0 (invisible) - 1.0
  -- (fully visible) to hex range '00' (fully visible) - 'FF' (invisible), for
  -- use with the alpha() function in a logical manner for end-users.
  if tonumber(percent) == nil or percent < 0 or percent > 1 then
    error("Invalid percentage value (must be 0.0 - 1.0)")
  end
  return Utils.toHex(
    -- Invert range (optionally), and make into a 0-255 value.
    math.floor(255 * (invertValue and 1 - percent or percent)),
    -- Fixed-size: 2 bytes (00-FF), as needed for hex in ASS subtitles.
    2
  )
end

Ass.alpha = function(transparencyHex, output)
  return output == false and "" or "{\\alpha&H" .. transparencyHex .. "&}" -- 00-FF.
end

Ass.color = function(rgbHex, output)
  return output == false and "" or "{\\1c&H" .. rgbHex:sub(5, 6) .. rgbHex:sub(3, 4) .. rgbHex:sub(1, 2) .. "&}"
end

Ass.white = function(output)
  return Ass.color("FFFFFF", output)
end

Ass.gray = function(output)
  return Ass.color("909090", output)
end

Ass.yellow = function(output)
  return Ass.color("FFFF90", output)
end

Ass.green = function(output)
  return Ass.color("90FF90", output)
end

return Ass
