do
local _ENV = _ENV
package.preload[ "goodbye" ] = function( ... ) local arg = _G.arg;
local goodbye = {}

local sayer = require("yopta.sayer")

function goodbye.say(n)
    sayer.say_each(n, "goodbye")
end

return goodbye
end
end

do
local _ENV = _ENV
package.preload[ "hello" ] = function( ... ) local arg = _G.arg;
local hello = {}

local sayer = require("yopta.sayer")

function hello.say(n)
    sayer.say_each(n, "hello")
end

return hello
end
end

do
local _ENV = _ENV
package.preload[ "inspect" ] = function( ... ) local arg = _G.arg;
local inspect ={
  _VERSION = 'inspect.lua 3.1.0',
  _URL     = 'http://github.com/kikito/inspect.lua',
  _DESCRIPTION = 'human-readable representations of tables',
  _LICENSE = [[
    MIT LICENSE

    Copyright (c) 2013 Enrique García Cota

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]]
}

local tostring = tostring

inspect.KEY       = setmetatable({}, {__tostring = function() return 'inspect.KEY' end})
inspect.METATABLE = setmetatable({}, {__tostring = function() return 'inspect.METATABLE' end})

local function rawpairs(t)
  return next, t, nil
end

-- Apostrophizes the string if it has quotes, but not aphostrophes
-- Otherwise, it returns a regular quoted string
local function smartQuote(str)
  if str:match('"') and not str:match("'") then
    return "'" .. str .. "'"
  end
  return '"' .. str:gsub('"', '\\"') .. '"'
end

-- \a => '\\a', \0 => '\\0', 31 => '\31'
local shortControlCharEscapes = {
  ["\a"] = "\\a",  ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n",
  ["\r"] = "\\r",  ["\t"] = "\\t", ["\v"] = "\\v"
}
local longControlCharEscapes = {} -- \a => nil, \0 => \000, 31 => \031
for i=0, 31 do
  local ch = string.char(i)
  if not shortControlCharEscapes[ch] then
    shortControlCharEscapes[ch] = "\\"..i
    longControlCharEscapes[ch]  = string.format("\\%03d", i)
  end
end

local function escape(str)
  return (str:gsub("\\", "\\\\")
             :gsub("(%c)%f[0-9]", longControlCharEscapes)
             :gsub("%c", shortControlCharEscapes))
end

local function isIdentifier(str)
  return type(str) == 'string' and str:match( "^[_%a][_%a%d]*$" )
end

local function isSequenceKey(k, sequenceLength)
  return type(k) == 'number'
     and 1 <= k
     and k <= sequenceLength
     and math.floor(k) == k
end

local defaultTypeOrders = {
  ['number']   = 1, ['boolean']  = 2, ['string'] = 3, ['table'] = 4,
  ['function'] = 5, ['userdata'] = 6, ['thread'] = 7
}

local function sortKeys(a, b)
  local ta, tb = type(a), type(b)

  -- strings and numbers are sorted numerically/alphabetically
  if ta == tb and (ta == 'string' or ta == 'number') then return a < b end

  local dta, dtb = defaultTypeOrders[ta], defaultTypeOrders[tb]
  -- Two default types are compared according to the defaultTypeOrders table
  if dta and dtb then return defaultTypeOrders[ta] < defaultTypeOrders[tb]
  elseif dta     then return true  -- default types before custom ones
  elseif dtb     then return false -- custom types after default ones
  end

  -- custom types are sorted out alphabetically
  return ta < tb
end

-- For implementation reasons, the behavior of rawlen & # is "undefined" when
-- tables aren't pure sequences. So we implement our own # operator.
local function getSequenceLength(t)
  local len = 1
  local v = rawget(t,len)
  while v ~= nil do
    len = len + 1
    v = rawget(t,len)
  end
  return len - 1
end

local function getNonSequentialKeys(t)
  local keys, keysLength = {}, 0
  local sequenceLength = getSequenceLength(t)
  for k,_ in rawpairs(t) do
    if not isSequenceKey(k, sequenceLength) then
      keysLength = keysLength + 1
      keys[keysLength] = k
    end
  end
  table.sort(keys, sortKeys)
  return keys, keysLength, sequenceLength
end

local function countTableAppearances(t, tableAppearances)
  tableAppearances = tableAppearances or {}

  if type(t) == 'table' then
    if not tableAppearances[t] then
      tableAppearances[t] = 1
      for k,v in rawpairs(t) do
        countTableAppearances(k, tableAppearances)
        countTableAppearances(v, tableAppearances)
      end
      countTableAppearances(getmetatable(t), tableAppearances)
    else
      tableAppearances[t] = tableAppearances[t] + 1
    end
  end

  return tableAppearances
end

local copySequence = function(s)
  local copy, len = {}, #s
  for i=1, len do copy[i] = s[i] end
  return copy, len
end

local function makePath(path, ...)
  local keys = {...}
  local newPath, len = copySequence(path)
  for i=1, #keys do
    newPath[len + i] = keys[i]
  end
  return newPath
end

local function processRecursive(process, item, path, visited)
  if item == nil then return nil end
  if visited[item] then return visited[item] end

  local processed = process(item, path)
  if type(processed) == 'table' then
    local processedCopy = {}
    visited[item] = processedCopy
    local processedKey

    for k,v in rawpairs(processed) do
      processedKey = processRecursive(process, k, makePath(path, k, inspect.KEY), visited)
      if processedKey ~= nil then
        processedCopy[processedKey] = processRecursive(process, v, makePath(path, processedKey), visited)
      end
    end

    local mt  = processRecursive(process, getmetatable(processed), makePath(path, inspect.METATABLE), visited)
    if type(mt) ~= 'table' then mt = nil end -- ignore not nil/table __metatable field
    setmetatable(processedCopy, mt)
    processed = processedCopy
  end
  return processed
end



-------------------------------------------------------------------

local Inspector = {}
local Inspector_mt = {__index = Inspector}

function Inspector:puts(...)
  local args   = {...}
  local buffer = self.buffer
  local len    = #buffer
  for i=1, #args do
    len = len + 1
    buffer[len] = args[i]
  end
end

function Inspector:down(f)
  self.level = self.level + 1
  f()
  self.level = self.level - 1
end

function Inspector:tabify()
  self:puts(self.newline, string.rep(self.indent, self.level))
end

function Inspector:alreadyVisited(v)
  return self.ids[v] ~= nil
end

function Inspector:getId(v)
  local id = self.ids[v]
  if not id then
    local tv = type(v)
    id              = (self.maxIds[tv] or 0) + 1
    self.maxIds[tv] = id
    self.ids[v]     = id
  end
  return tostring(id)
end

function Inspector:putKey(k)
  if isIdentifier(k) then return self:puts(k) end
  self:puts("[")
  self:putValue(k)
  self:puts("]")
end

function Inspector:putTable(t)
  if t == inspect.KEY or t == inspect.METATABLE then
    self:puts(tostring(t))
  elseif self:alreadyVisited(t) then
    self:puts('<table ', self:getId(t), '>')
  elseif self.level >= self.depth then
    self:puts('{...}')
  else
    if self.tableAppearances[t] > 1 then self:puts('<', self:getId(t), '>') end

    local nonSequentialKeys, nonSequentialKeysLength, sequenceLength = getNonSequentialKeys(t)
    local mt                = getmetatable(t)

    self:puts('{')
    self:down(function()
      local count = 0
      for i=1, sequenceLength do
        if count > 0 then self:puts(',') end
        self:puts(' ')
        self:putValue(t[i])
        count = count + 1
      end

      for i=1, nonSequentialKeysLength do
        local k = nonSequentialKeys[i]
        if count > 0 then self:puts(',') end
        self:tabify()
        self:putKey(k)
        self:puts(' = ')
        self:putValue(t[k])
        count = count + 1
      end

      if type(mt) == 'table' then
        if count > 0 then self:puts(',') end
        self:tabify()
        self:puts('<metatable> = ')
        self:putValue(mt)
      end
    end)

    if nonSequentialKeysLength > 0 or type(mt) == 'table' then -- result is multi-lined. Justify closing }
      self:tabify()
    elseif sequenceLength > 0 then -- array tables have one extra space before closing }
      self:puts(' ')
    end

    self:puts('}')
  end
end

function Inspector:putValue(v)
  local tv = type(v)

  if tv == 'string' then
    self:puts(smartQuote(escape(v)))
  elseif tv == 'number' or tv == 'boolean' or tv == 'nil' or
         tv == 'cdata' or tv == 'ctype' then
    self:puts(tostring(v))
  elseif tv == 'table' then
    self:putTable(v)
  else
    self:puts('<', tv, ' ', self:getId(v), '>')
  end
end

-------------------------------------------------------------------

function inspect.inspect(root, options)
  options       = options or {}

  local depth   = options.depth   or math.huge
  local newline = options.newline or '\n'
  local indent  = options.indent  or '  '
  local process = options.process

  if process then
    root = processRecursive(process, root, {}, {})
  end

  local inspector = setmetatable({
    depth            = depth,
    level            = 0,
    buffer           = {},
    ids              = {},
    maxIds           = {},
    newline          = newline,
    indent           = indent,
    tableAppearances = countTableAppearances(root)
  }, Inspector_mt)

  inspector:putValue(root)

  return table.concat(inspector.buffer)
end

setmetatable(inspect, { __call = function(_, ...) return inspect.inspect(...) end })

return inspect
end
end

do
local _ENV = _ENV
package.preload[ "lua-string" ] = function( ... ) local arg = _G.arg;
local boolvalues = {
	["1"] = "0";
	["true"] = "false";
	["on"] = "off";
	["yes"] = "no";
	["y"] = "n"
}
local eschars = {
	"\"", "'", "\\"
}
local escregexchars = {
	"(", ")", ".", "%", "+", "-", "*", "?", "[", "]", "^", "$"
}
local mt = getmetatable("")

local function includes(tbl, item)
	for k, v in pairs(tbl) do
		if v == item then
			return true
		end
	end
	return false
end

--- Overloads `*` operator. Works the same as `string.rep()` function.
--- @param n number Multiplier.
--- @return string rs String multiplied `n` times.
function mt:__mul(n)
	if type(self) == "number" then
		return n * self
	end
	if type(n) ~= "number" then
		error(string.format("attempt to mul a '%1' with a 'string'", type(n)))
	end
	return self:rep(n)
end

--- Overloads `[]` operator. It's possible to access individual chars with this operator. Index could be negative. In
--- that case the counting will start from the end.
--- @param i number Index at which retrieve a char.
--- @return string ch Single character at specified index. Nil if the index is larger than length of the string.
function mt:__index(i)
	if string[i] then
		return string[i]
	end
	i = i < 0 and #self + i + 1 or i
	local rs = self:sub(i, i)
	return #rs > 0 and rs or nil
end

--- Splits the string by supplied separator. If the `pattern` parameter is set to true then the separator is considered
--- as a regular expression.
--- @param sep string Separator by which separate the string.
--- @param pattern? boolean `true` for separator to be considered as a pattern. `false` by default.
--- @return string[] t Table of substrings separated by `sep` string.
function string:split(sep, pattern)
	if sep == "" then
		return self:totable()
	end
	local rs = {}
	local previdx = 1
	while true do
		local startidx, endidx = self:find(sep, previdx, not pattern)
		if not startidx then
			table.insert(rs, self:sub(previdx))
			break
		end
		table.insert(rs, self:sub(previdx, startidx - 1))
		previdx = endidx + 1
	end
	return rs
end

--- Trims string's characters from its endings. Trims whitespaces by default. The `chars` argument is a regex string
--- containing which characters to trim.
--- @param chars? string Pattern that represents which characters to trim from the ends. Whitespaces by default.
--- @return string s String with trimmed characters on both sides.
function string:trim(chars)
	chars = chars or "%s"
	return self:trimstart(chars):trimend(chars)
end

--- Trims string's characters from its left side. Trims whitespaces by default. The `chars` argument is a regex string
--- containing which characters to trim
--- @param chars? string Pattern that represents which characters to trim from the start. Whitespaces by default.
--- @return string s String with trimmed characters at the start.
function string:trimstart(chars)
	return self:gsub("^["..(chars or "%s").."]+", "")
end

--- Trims string's characters from its right side. Trims whitespaces by default. The `chars` argument is a regex string
--- containing which characters to trim.
--- @param chars? string Pattern that represents Which characters to trim from the end. Whitespaces by default.
--- @return string s String with trimmed characters at the end.
function string:trimend(chars)
	return self:gsub("["..(chars or "%s").."]+$", "")
end

--- Pads the string at the start with specified string until specified length.
--- @param len number To which length pad the string.
--- @param str? string String to pad the string with. " " by default
--- @return string s Padded string or the string itself if this parameter is less than string's length.
function string:padstart(len, str)
	str = str or " "
	local selflen = self:len()
	return (str:rep(math.ceil((len - selflen) / str:len()))..self):sub(-(selflen < len and len or selflen))
end

--- Pads the string at the end with specified string until specified length.
--- @param len number To which length pad the string.
--- @param str? string String to pad the string with. " " by default
--- @return string s Padded string or the string itself if this parameter is less than string's length.
function string:padend(len, str)
	str = str or " "
	local selflen = self:len()
	return (self..str:rep(math.ceil((len - selflen) / str:len()))):sub(1, selflen < len and len or selflen)
end

--- If the string starts with specified prefix then returns string itself, otherwise pads the string until it starts
--- with the prefix.
--- @param prefix string String to ensure this string starts with.
--- @return string s String that starts with specified prefix.
function string:ensurestart(prefix)
	local prefixlen = prefix:len()
	if prefixlen > self:len() then
		return prefix:ensureend(self)
	end
	local left = self:sub(1, prefixlen)
	local i = 1
	while not prefix:endswith(left) and i <= prefixlen do
		i = i + 1
		left = left:sub(1, -2)
	end
	return prefix:sub(1, i - 1)..self
end

--- If the string ends with specified suffix then returns string itself, otherwise pads the string until it ends with
--- the suffix.
--- @param suffix string String to ensure this string ends with.
--- @return string s String that ends with specified prefix.
function string:ensureend(suffix)
	local suffixlen = suffix:len()
	if suffixlen > self:len() then
		return suffix:ensurestart(self)
	end
	local right = self:sub(-suffixlen)
	local i = suffixlen
	while not suffix:startswith(right) and i >= 1 do
		i = i - 1
		right = right:sub(2)
	end
	return self..suffix:sub(i + 1)
end

--- Adds backslashes before `"`, `'` and `\` characters.
--- @param eschar? string Escape character. `\` by default.
--- @param eschartbl? string[] Characters to escape. `{"\"", "'", "\\"}` by default.
--- @return string s String with escaped characters.
function string:esc(eschar, eschartbl)
	local s = ""
	eschar = eschar or "\\"
	eschartbl = eschartbl or eschars
	for char in self:iter() do
		s = includes(eschartbl, char) and s..eschar..char or s..char
	end
	return s
end

--- Strips backslashes from the string.
--- @param eschar? string Escape character. `\` by default.
--- @return string s Unescaped string with stripped escape character.
function string:unesc(eschar)
	local s = ""
	local i = 0
	eschar = eschar or "\\"
	while i <= #self do
		local char = self:sub(i, i)
		if char == eschar then
			i = i + 1
			s = s..self:sub(i, i)
		else
			s = s..char
		end
		i = i + 1
	end
	return s
end

--- Escapes pattern special characters so the string can be used in pattern matching functions as is.
--- @return string s String with escaped pattern special characters.
function string:escpattern()
	return self:esc("%", escregexchars)
end

--- Unescapes pattern special characters.
--- @return string s Unescaped string with stripped pattern `%` escape character.
function string:unescpattern()
	return self:unesc("%")
end

--- Escapes pattern special characters so the string can be used in pattern matching functions as is.
--- @return string s String with escaped pattern special characters.
--- @deprecated
function string:escregex()
	return self:esc("%", escregexchars)
end

--- Unescapes pattern special characters.
--- @return string s Unescaped string with stripped pattern `%` escape character.
--- @deprecated
function string:unescregex()
	return self:unesc("%")
end

--- Returns an iterator which can be used in `for ... in` loops.
--- @return fun(): string f Iterator.
function string:iter()
	local i = 0
	return function ()
		i = i + 1
		return i <= self:len() and self:sub(i, i) or nil
	end
end

--- Truncates string to a specified length with optional suffix.
--- @param len number Length to which truncate the string.
--- @param suffix? string Optional string that will be added at the end.
--- @return string s Truncated string.
function string:truncate(len, suffix)
	if suffix then
		local newlen = len - suffix:len()
		return 0 < newlen and newlen < self:len() and self:sub(1, newlen)..suffix or self:sub(1, len)
	else
		return self:sub(1, len)
	end
end

--- Returns true if the string starts with specified string.
--- @param prefix string String to test that this string starts with.
--- @return boolean b `true` if the string starts with the specified prefix.
function string:startswith(prefix)
	return self:sub(0, prefix:len()) == prefix
end

--- Returns true if the string ends with specified string.
--- @param suffix string String to test that this string ends with.
--- @return boolean b `true` if the string ends with the specified suffix.
function string:endswith(suffix)
	return self:sub(self:len() - suffix:len() + 1) == suffix
end

--- Checks if the string is empty.
--- @return boolean b `true` if the string's length is 0.
function string:isempty()
	return self:len() == 0
end

--- Checks if the string consists of whitespace characters.
--- @return boolean b `true` if the string consists of whitespaces or it's empty.
function string:isblank()
	return self:match("^%s*$") ~= nil
end

--- Converts "1", "true", "on", "yes", "y" and their contraries into real boolean. Case-insensetive.
--- @return boolean | nil b Boolean corresponding to the string or nil if casting cannot be done.
function string:tobool()
	local lowered = self:lower()
	for truthy, falsy in pairs(boolvalues) do
		if lowered == truthy then
			return true
		elseif lowered == falsy then
			return false
		end
	end
	return nil
end

--- Returns table containing all the chars in the string.
--- @return string[] t Table that consists of the string's characters.
function string:totable()
	local result = {}
	for ch in self:iter() do
		table.insert(result, ch)
	end
	return result
end
end
end

do
local _ENV = _ENV
package.preload[ "mymod" ] = function( ... ) local arg = _G.arg;
local mymodule = {}

function mymodule.foo()
    print("Hello World!")
end

return mymodule
end
end

do
local _ENV = _ENV
package.preload[ "yopta.sayer" ] = function( ... ) local arg = _G.arg;
local sayer = {}

function sayer.say_each(n, word)
    for i = 1, n do
        sayer.say(word)
    end
end

function sayer.say(word)
    print(word)
end

return sayer
end
end

do
local _ENV = _ENV
package.preload[ "yopta.utils" ] = function( ... ) local arg = _G.arg;
local utils = {}

function utils.say_it()
    print("Yopta!")
end

return utils
end
end

mymodule = require "mymod"
mymodule.foo()

local yopta_utils = require "yopta.utils"
yopta_utils.say_it()

require "lua-string"
inspect = require "inspect"

local v = ("Hello world!"):trimend("!"):sub(6):trim():totable()
print(inspect(v))

local x = 10

local r = ""

if x < 10 then
    r = require("hello")
else
    r = require("goodbye")
end

r.say(2)
