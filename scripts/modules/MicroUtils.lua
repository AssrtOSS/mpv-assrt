--[[
    MICROUTILS.LUA (MODULE)

    Version:     1.2.0
    Original:    VideoPlayerCode (Javascipt)
    Author:      AssrtOSS
    URL:         https://github.com/VideoPlayerCode/mpv-tools
    License:     Apache License, Version 2.0
]] --

-- luacheck: globals mp

local utils = require("mp.utils")

local Utils = {}

-- https://stackoverflow.com/a/16257287
local function luav()
  -- luacheck: ignore
  local n = "8"
  repeat
    n = n * n
  until n == n * n
  local t = {
    "Lua 5.1",
    nil,
    [-1 / 0] = "Lua 5.2",
    [1 / 0] = "Lua 5.3",
    [2] = "LuaJIT"
  }
  return t[2] or t[#"\z"] or t[n / "-0"] or "Lua 5.4"
end

Utils.luaversion = luav()

-- NOTE: This is an implementation of a non-recursive quicksort, with options
-- of with or without considering case
Utils.quickSort = function(arr, options)
  local tbl = {}

  for i, a in ipairs(arr) do
    tbl[i] = a
  end

  if options and options.caseInsensitive then
    table.sort(
      tbl,
      function(a, b)
        return a:lower() < b:lower()
      end
    )
  end

  table.sort(tbl)
  return tbl
end

Utils.isInt = function(n)
  -- Verify that the input is an integer (whole number).
  return n and tonumber(n) and n - math.floor(n) <= 0
end

local hexSymbols = {
  "0",
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "a",
  "b",
  "c",
  "d",
  "e",
  "f"
}

-- http://lua-users.org/wiki/BitUtils
local function nand(x, y, z)
  z = z or 2 ^ 16
  if z < 2 then
    return 1 - x * y
  else
    return nand((x - x % z) / z, (y - y % z) / z, math.sqrt(z)) * z + nand(x % z, y % z, math.sqrt(z))
  end
end

local bnot = function(y, z)
  return nand(nand(0, 0, z), y, z)
end

local bor = function(x, y, z)
  return nand(bnot(x, z), bnot(y, z), z)
end

local band = function(x, y, z)
  return nand(bnot(0, z), nand(x, y, z), z)
end

-- http://luaforge.net/projects/bit
local function rshift(n, bits)
  if not Utils.isInt(n) then
    error("first operand is not interger: got " .. tostring(n))
  end

  local high_bit = 0
  if (n < 0) then
    -- negative
    n = bnot(math.abs(n)) + 1
    high_bit = 2147483648 -- 0x80000000
  end

  for _ = 1, bits do
    n = n / 2
    n = bor(math.floor(n), high_bit)
  end
  return math.floor(n)
end

local bitAnd = Utils.luaversion == "LuaJIT" and require("bit").band or band

local bitRshift = Utils.luaversion == "LuaJIT" and require("bit").rshift or rshift

Utils.toHex = function(num, outputLength)
  -- Generates a fixed-length output, and handles negative numbers properly.
  local result = ""
  while outputLength > 0 do
    outputLength = outputLength - 1
    result = hexSymbols[bitAnd(num, 0xF) + 1] .. result
    num = bitRshift(num, 4)
  end
  return result
end

Utils.shuffle = function(arr)
  local m = #arr
  local tmp, i

  while m > 0 do -- While items remain to shuffle...
    -- Pick a remaining element...
    i = math.random(0, m - 1) + 1

    -- And swap it with the current element.
    tmp = arr[m]
    arr[m] = arr[i]
    arr[i] = tmp
    m = m - 1
  end

  return arr
end

-- http://lua-users.org/wiki/CommonFunctions
Utils.trim = function(str)
  -- Trim left and right whitespace.
  return (str:gsub("^%s*(.-)%s*$", "%1"))
end

Utils.ltrim = function(str)
  -- Trim left whitespace.
  return (str:gsub("^%s*", ""))
end

Utils.rtrim = function(str)
  -- Trim right whitespace.
  local n = #str
  while n > 0 and str:find("^%s", n) do
    n = n - 1
  end
  return str:sub(1, n)
end

Utils.dump = function(value)
  mp.msg.error(utils.format_json(value))
end

Utils.benchmarkStart = function(textLabel)
  Utils.benchmarkTimestamp = mp.get_time()
  Utils.benchmarkTextLabel = textLabel
end

Utils.benchmarkEnd = function()
  local now = mp.get_time()
  local start = Utils.benchmarkTimestamp or now
  local elapsed = now - start
  local label = Utils.benchmarkTextLabel or ""
  mp.msg.info("Time Elapsed (Benchmark" .. (label and (": " .. label) or "") .. "): " .. elapsed .. " seconds.")
end

return Utils
