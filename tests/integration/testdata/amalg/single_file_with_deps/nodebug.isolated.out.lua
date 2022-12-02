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
package.preload[ "luassert" ] = function( ... ) local arg = _G.arg;
local assert = require('luassert.assert')

assert._COPYRIGHT   = "Copyright (c) 2018 Olivine Labs, LLC."
assert._DESCRIPTION = "Extends Lua's built-in assertions to provide additional tests and the ability to create your own."
assert._VERSION     = "Luassert 1.8.0"

-- load basic asserts
require('luassert.assertions')
require('luassert.modifiers')
require('luassert.array')
require('luassert.matchers')
require('luassert.formatters')

-- load default language
require('luassert.languages.en')

return assert
end
end

do
local _ENV = _ENV
package.preload[ "luassert.array" ] = function( ... ) local arg = _G.arg;
local assert = require('luassert.assert')
local say = require('say')

-- Example usage:
-- local arr = { "one", "two", "three" }
--
-- assert.array(arr).has.no.holes()   -- checks the array to not contain holes --> passes
-- assert.array(arr).has.no.holes(4)  -- sets explicit length to 4 --> fails
--
-- local first_hole = assert.array(arr).has.holes(4)     -- check array of size 4 to contain holes --> passes
-- assert.equal(4, first_hole)        -- passes, as the index of the first hole is returned


-- Unique key to store the object we operate on in the state object
-- key must be unique, to make sure we do not have name collissions in the shared state object
local ARRAY_STATE_KEY = "__array_state"

-- The modifier, to store the object in our state
local function array(state, args, level)
  assert(args.n > 0, "No array provided to the array-modifier")
  assert(rawget(state, ARRAY_STATE_KEY) == nil, "Array already set")
  rawset(state, ARRAY_STATE_KEY, args[1])
  return state
end

-- The actual assertion that operates on our object, stored via the modifier
local function holes(state, args, level)
  local length = args[1]
  local arr = rawget(state, ARRAY_STATE_KEY) -- retrieve previously set object
  -- only check against nil, metatable types are allowed
  assert(arr ~= nil, "No array set, please use the array modifier to set the array to validate")
  if length == nil then
    length = 0
    for i in pairs(arr) do
      if type(i) == "number" and
         i > length and
         math.floor(i) == i then
        length = i
      end
    end
  end
  assert(type(length) == "number", "expected array length to be of type 'number', got: "..tostring(length))
  -- let's do the actual assertion
  local missing
  for i = 1, length do
    if arr[i] == nil then
      missing = i
      break
    end
  end
  -- format arguments for output strings;
  args[1] = missing
  args.n = missing and 1 or 0
  return missing ~= nil, { missing } -- assert result + first missing index as return value
end

-- Register the proper assertion messages
say:set("assertion.array_holes.positive", [[
Expected array to have holes, but none was found.
]])
say:set("assertion.array_holes.negative", [[
Expected array to not have holes, hole found at position: %s
]])

-- Register the assertion, and the modifier
assert:register("assertion", "holes", holes,
                  "assertion.array_holes.positive",
                  "assertion.array_holes.negative")

assert:register("modifier", "array", array)
end
end

do
local _ENV = _ENV
package.preload[ "luassert.assert" ] = function( ... ) local arg = _G.arg;
local s = require 'say'
local astate = require 'luassert.state'
local util = require 'luassert.util'
local unpack = require 'luassert.compatibility'.unpack
local obj   -- the returned module table
local level_mt = {}

-- list of namespaces
local namespace = require 'luassert.namespaces'

local function geterror(assertion_message, failure_message, args)
  if util.hastostring(failure_message) then
    failure_message = tostring(failure_message)
  elseif failure_message ~= nil then
    failure_message = astate.format_argument(failure_message)
  end
  local message = s(assertion_message, obj:format(args))
  if message and failure_message then
    message = failure_message .. "\n" .. message
  end
  return message or failure_message
end

local __state_meta = {

  __call = function(self, ...)
    local keys = util.extract_keys("assertion", self.tokens)

    local assertion

    for _, key in ipairs(keys) do
      assertion = namespace.assertion[key] or assertion
    end

    if assertion then
      for _, key in ipairs(keys) do
        if namespace.modifier[key] then
          namespace.modifier[key].callback(self)
        end
      end

      local arguments = {...}
      arguments.n = select('#', ...) -- add argument count for trailing nils
      local val, retargs = assertion.callback(self, arguments, util.errorlevel())

      if not val == self.mod then
        local message = assertion.positive_message
        if not self.mod then
          message = assertion.negative_message
        end
        local err = geterror(message, rawget(self,"failure_message"), arguments)
        error(err or "assertion failed!", util.errorlevel())
      end

      if retargs then
        return unpack(retargs)
      end
      return ...
    else
      local arguments = {...}
      arguments.n = select('#', ...)
      self.tokens = {}

      for _, key in ipairs(keys) do
        if namespace.modifier[key] then
          namespace.modifier[key].callback(self, arguments, util.errorlevel())
        end
      end
    end

    return self
  end,

  __index = function(self, key)
    for token in key:lower():gmatch('[^_]+') do
      table.insert(self.tokens, token)
    end

    return self
  end
}

obj = {
  state = function() return setmetatable({mod=true, tokens={}}, __state_meta) end,

  -- registers a function in namespace
  register = function(self, nspace, name, callback, positive_message, negative_message)
    local lowername = name:lower()
    if not namespace[nspace] then
      namespace[nspace] = {}
    end
    namespace[nspace][lowername] = {
      callback = callback,
      name = lowername,
      positive_message=positive_message,
      negative_message=negative_message
    }
  end,

  -- unregisters a function in a namespace
  unregister = function(self, nspace, name)
    local lowername = name:lower()
    if not namespace[nspace] then
      namespace[nspace] = {}
    end
    namespace[nspace][lowername] = nil
  end,

  -- registers a formatter
  -- a formatter takes a single argument, and converts it to a string, or returns nil if it cannot format the argument
  add_formatter = function(self, callback)
    astate.add_formatter(callback)
  end,

  -- unregisters a formatter
  remove_formatter = function(self, fmtr)
    astate.remove_formatter(fmtr)
  end,

  format = function(self, args)
    -- args.n specifies the number of arguments in case of 'trailing nil' arguments which get lost
    local nofmt = args.nofmt or {}  -- arguments in this list should not be formatted
    local fmtargs = args.fmtargs or {} -- additional arguments to be passed to formatter
    for i = 1, (args.n or #args) do -- cannot use pairs because table might have nils
      if not nofmt[i] then
        local val = args[i]
        local valfmt = astate.format_argument(val, nil, fmtargs[i])
        if valfmt == nil then valfmt = tostring(val) end -- no formatter found
        args[i] = valfmt
      end
    end
    return args
  end,

  set_parameter = function(self, name, value)
    astate.set_parameter(name, value)
  end,
  
  get_parameter = function(self, name)
    return astate.get_parameter(name)
  end,  
  
  add_spy = function(self, spy)
    astate.add_spy(spy)
  end,
  
  snapshot = function(self)
    return astate.snapshot()
  end,
  
  level = function(self, level)
    return setmetatable({
        level = level
      }, level_mt)
  end,
  
  -- returns the level if a level-value, otherwise nil
  get_level = function(self, level)
    if getmetatable(level) ~= level_mt then
      return nil -- not a valid error-level
    end
    return level.level
  end,
}

local __meta = {

  __call = function(self, bool, message, level, ...)
    if not bool then
      local err_level = (self:get_level(level) or 1) + 1
      error(message or "assertion failed!", err_level)
    end
    return bool , message , level , ...
  end,

  __index = function(self, key)
    return rawget(self, key) or self.state()[key]
  end,

}

return setmetatable(obj, __meta)
end
end

do
local _ENV = _ENV
package.preload[ "luassert.assertions" ] = function( ... ) local arg = _G.arg;
-- module will not return anything, only register assertions with the main assert engine

-- assertions take 2 parameters;
-- 1) state
-- 2) arguments list. The list has a member 'n' with the argument count to check for trailing nils
-- 3) level The level of the error position relative to the called function
-- returns; boolean; whether assertion passed

local assert = require('luassert.assert')
local astate = require ('luassert.state')
local util = require ('luassert.util')
local s = require('say')

local function format(val)
  return astate.format_argument(val) or tostring(val)
end

local function set_failure_message(state, message)
  if message ~= nil then
    state.failure_message = message
  end
end

local function unique(state, arguments, level)
  local list = arguments[1]
  local deep
  local argcnt = arguments.n
  if type(arguments[2]) == "boolean" or (arguments[2] == nil and argcnt > 2) then
    deep = arguments[2]
    set_failure_message(state, arguments[3])
  else
    if type(arguments[3]) == "boolean" then
      deep = arguments[3]
    end
    set_failure_message(state, arguments[2])
  end
  for k,v in pairs(list) do
    for k2, v2 in pairs(list) do
      if k ~= k2 then
        if deep and util.deepcompare(v, v2, true) then
          return false
        else
          if v == v2 then
            return false
          end
        end
      end
    end
  end
  return true
end

local function near(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 2, s("assertion.internal.argtolittle", { "near", 3, tostring(argcnt) }), level)
  local expected = tonumber(arguments[1])
  local actual = tonumber(arguments[2])
  local tolerance = tonumber(arguments[3])
  local numbertype = "number or object convertible to a number"
  assert(expected, s("assertion.internal.badargtype", { 1, "near", numbertype, format(arguments[1]) }), level)
  assert(actual, s("assertion.internal.badargtype", { 2, "near", numbertype, format(arguments[2]) }), level)
  assert(tolerance, s("assertion.internal.badargtype", { 3, "near", numbertype, format(arguments[3]) }), level)
  -- switch arguments for proper output message
  util.tinsert(arguments, 1, util.tremove(arguments, 2))
  arguments[3] = tolerance
  arguments.nofmt = arguments.nofmt or {}
  arguments.nofmt[3] = true
  set_failure_message(state, arguments[4])
  return (actual >= expected - tolerance and actual <= expected + tolerance)
end

local function matches(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 1, s("assertion.internal.argtolittle", { "matches", 2, tostring(argcnt) }), level)
  local pattern = arguments[1]
  local actual = nil
  if util.hastostring(arguments[2]) or type(arguments[2]) == "number" then
    actual = tostring(arguments[2])
  end
  local err_message
  local init_arg_num = 3
  for i=3,argcnt,1 do
    if arguments[i] and type(arguments[i]) ~= "boolean" and not tonumber(arguments[i]) then
      if i == 3 then init_arg_num = init_arg_num + 1 end
      err_message = util.tremove(arguments, i)
      break
    end
  end
  local init = arguments[3]
  local plain = arguments[4]
  local stringtype = "string or object convertible to a string"
  assert(type(pattern) == "string", s("assertion.internal.badargtype", { 1, "matches", "string", type(arguments[1]) }), level)
  assert(actual, s("assertion.internal.badargtype", { 2, "matches", stringtype, format(arguments[2]) }), level)
  assert(init == nil or tonumber(init), s("assertion.internal.badargtype", { init_arg_num, "matches", "number", type(arguments[3]) }), level)
  -- switch arguments for proper output message
  util.tinsert(arguments, 1, util.tremove(arguments, 2))
  set_failure_message(state, err_message)
  local retargs
  local ok
  if plain then
    ok = (actual:find(pattern, init, plain) ~= nil)
    retargs = ok and { pattern } or {}
  else
    retargs = { actual:match(pattern, init) }
    ok = (retargs[1] ~= nil)
  end
  return ok, retargs
end

local function equals(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 1, s("assertion.internal.argtolittle", { "equals", 2, tostring(argcnt) }), level)
  local result =  arguments[1] == arguments[2]
  -- switch arguments for proper output message
  util.tinsert(arguments, 1, util.tremove(arguments, 2))
  set_failure_message(state, arguments[3])
  return result
end

local function same(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 1, s("assertion.internal.argtolittle", { "same", 2, tostring(argcnt) }), level)
  if type(arguments[1]) == 'table' and type(arguments[2]) == 'table' then
    local result, crumbs = util.deepcompare(arguments[1], arguments[2], true)
    -- switch arguments for proper output message
    util.tinsert(arguments, 1, util.tremove(arguments, 2))
    arguments.fmtargs = arguments.fmtargs or {}
    arguments.fmtargs[1] = { crumbs = crumbs }
    arguments.fmtargs[2] = { crumbs = crumbs }
    set_failure_message(state, arguments[3])
    return result
  end
  local result = arguments[1] == arguments[2]
  -- switch arguments for proper output message
  util.tinsert(arguments, 1, util.tremove(arguments, 2))
  set_failure_message(state, arguments[3])
  return result
end

local function truthy(state, arguments, level)
  set_failure_message(state, arguments[2])
  return arguments[1] ~= false and arguments[1] ~= nil
end

local function falsy(state, arguments, level)
  return not truthy(state, arguments, level)
end

local function has_error(state, arguments, level)
  local level = (level or 1) + 1
  local retargs = util.shallowcopy(arguments)
  local func = arguments[1]
  local err_expected = arguments[2]
  local failure_message = arguments[3]
  assert(util.callable(func), s("assertion.internal.badargtype", { 1, "error", "function or callable object", type(func) }), level)
  local ok, err_actual = pcall(func)
  if type(err_actual) == 'string' then
    -- remove 'path/to/file:line: ' from string
    err_actual = err_actual:gsub('^.-:%d+: ', '', 1)
  end
  retargs[1] = err_actual
  arguments.nofmt = {}
  arguments.n = 2
  arguments[1] = (ok and '(no error)' or err_actual)
  arguments[2] = (err_expected == nil and '(error)' or err_expected)
  arguments.nofmt[1] = ok
  arguments.nofmt[2] = (err_expected == nil)
  set_failure_message(state, failure_message)

  if ok or err_expected == nil then
    return not ok, retargs
  end
  if type(err_expected) == 'string' then
    -- err_actual must be (convertible to) a string
    if util.hastostring(err_actual) then
      err_actual = tostring(err_actual)
      retargs[1] = err_actual
    end
    if type(err_actual) == 'string' then
      return err_expected == err_actual, retargs
    end
  elseif type(err_expected) == 'number' then
    if type(err_actual) == 'string' then
      return tostring(err_expected) == tostring(tonumber(err_actual)), retargs
    end
  end
  return same(state, {err_expected, err_actual, ["n"] = 2}), retargs
end

local function error_matches(state, arguments, level)
  local level = (level or 1) + 1
  local retargs = util.shallowcopy(arguments)
  local argcnt = arguments.n
  local func = arguments[1]
  local pattern = arguments[2]
  assert(argcnt > 1, s("assertion.internal.argtolittle", { "error_matches", 2, tostring(argcnt) }), level)
  assert(util.callable(func), s("assertion.internal.badargtype", { 1, "error_matches", "function or callable object", type(func) }), level)
  assert(pattern == nil or type(pattern) == "string", s("assertion.internal.badargtype", { 2, "error", "string", type(pattern) }), level)

  local failure_message
  local init_arg_num = 3
  for i=3,argcnt,1 do
    if arguments[i] and type(arguments[i]) ~= "boolean" and not tonumber(arguments[i]) then
      if i == 3 then init_arg_num = init_arg_num + 1 end
      failure_message = util.tremove(arguments, i)
      break
    end
  end
  local init = arguments[3]
  local plain = arguments[4]
  assert(init == nil or tonumber(init), s("assertion.internal.badargtype", { init_arg_num, "matches", "number", type(arguments[3]) }), level)

  local ok, err_actual = pcall(func)
  if type(err_actual) == 'string' then
    -- remove 'path/to/file:line: ' from string
    err_actual = err_actual:gsub('^.-:%d+: ', '', 1)
  end
  retargs[1] = err_actual
  arguments.nofmt = {}
  arguments.n = 2
  arguments[1] = (ok and '(no error)' or err_actual)
  arguments[2] = pattern
  arguments.nofmt[1] = ok
  arguments.nofmt[2] = false
  set_failure_message(state, failure_message)

  if ok then return not ok, retargs end
  if err_actual == nil and pattern == nil then
    return true, {}
  end

  -- err_actual must be (convertible to) a string
  if util.hastostring(err_actual) then
    err_actual = tostring(err_actual)
    retargs[1] = err_actual
  end
  if type(err_actual) == 'string' then
    local ok
    local retargs_ok
    if plain then
      retargs_ok = { pattern }
      ok = (err_actual:find(pattern, init, plain) ~= nil)
    else
      retargs_ok = { err_actual:match(pattern, init) }
      ok = (retargs_ok[1] ~= nil)
    end
    if ok then retargs = retargs_ok end
    return ok, retargs
  end

  return false, retargs
end

local function is_true(state, arguments, level)
  util.tinsert(arguments, 2, true)
  set_failure_message(state, arguments[3])
  return arguments[1] == arguments[2]
end

local function is_false(state, arguments, level)
  util.tinsert(arguments, 2, false)
  set_failure_message(state, arguments[3])
  return arguments[1] == arguments[2]
end

local function is_type(state, arguments, level, etype)
  util.tinsert(arguments, 2, "type " .. etype)
  arguments.nofmt = arguments.nofmt or {}
  arguments.nofmt[2] = true
  set_failure_message(state, arguments[3])
  return arguments.n > 1 and type(arguments[1]) == etype
end

local function returned_arguments(state, arguments, level)
  arguments[1] = tostring(arguments[1])
  arguments[2] = tostring(arguments.n - 1)
  arguments.nofmt = arguments.nofmt or {}
  arguments.nofmt[1] = true
  arguments.nofmt[2] = true
  if arguments.n < 2 then arguments.n = 2 end
  return arguments[1] == arguments[2]
end

local function set_message(state, arguments, level)
  state.failure_message = arguments[1]
end

local function is_boolean(state, arguments, level)  return is_type(state, arguments, level, "boolean")  end
local function is_number(state, arguments, level)   return is_type(state, arguments, level, "number")   end
local function is_string(state, arguments, level)   return is_type(state, arguments, level, "string")   end
local function is_table(state, arguments, level)    return is_type(state, arguments, level, "table")    end
local function is_nil(state, arguments, level)      return is_type(state, arguments, level, "nil")      end
local function is_userdata(state, arguments, level) return is_type(state, arguments, level, "userdata") end
local function is_function(state, arguments, level) return is_type(state, arguments, level, "function") end
local function is_thread(state, arguments, level)   return is_type(state, arguments, level, "thread")   end

assert:register("modifier", "message", set_message)
assert:register("assertion", "true", is_true, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "false", is_false, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "boolean", is_boolean, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "number", is_number, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "string", is_string, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "table", is_table, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "nil", is_nil, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "userdata", is_userdata, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "function", is_function, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "thread", is_thread, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "returned_arguments", returned_arguments, "assertion.returned_arguments.positive", "assertion.returned_arguments.negative")

assert:register("assertion", "same", same, "assertion.same.positive", "assertion.same.negative")
assert:register("assertion", "matches", matches, "assertion.matches.positive", "assertion.matches.negative")
assert:register("assertion", "match", matches, "assertion.matches.positive", "assertion.matches.negative")
assert:register("assertion", "near", near, "assertion.near.positive", "assertion.near.negative")
assert:register("assertion", "equals", equals, "assertion.equals.positive", "assertion.equals.negative")
assert:register("assertion", "equal", equals, "assertion.equals.positive", "assertion.equals.negative")
assert:register("assertion", "unique", unique, "assertion.unique.positive", "assertion.unique.negative")
assert:register("assertion", "error", has_error, "assertion.error.positive", "assertion.error.negative")
assert:register("assertion", "errors", has_error, "assertion.error.positive", "assertion.error.negative")
assert:register("assertion", "error_matches", error_matches, "assertion.error.positive", "assertion.error.negative")
assert:register("assertion", "error_match", error_matches, "assertion.error.positive", "assertion.error.negative")
assert:register("assertion", "matches_error", error_matches, "assertion.error.positive", "assertion.error.negative")
assert:register("assertion", "match_error", error_matches, "assertion.error.positive", "assertion.error.negative")
assert:register("assertion", "truthy", truthy, "assertion.truthy.positive", "assertion.truthy.negative")
assert:register("assertion", "falsy", falsy, "assertion.falsy.positive", "assertion.falsy.negative")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.compatibility" ] = function( ... ) local arg = _G.arg;
return {
  unpack = table.unpack or unpack,
}
end
end

do
local _ENV = _ENV
package.preload[ "luassert.formatters" ] = function( ... ) local arg = _G.arg;
-- module will not return anything, only register formatters with the main assert engine
local assert = require('luassert.assert')

local colors = setmetatable({
  none = function(c) return c end
},{ __index = function(self, key)
  local ok, term = pcall(require, 'term')
  local isatty = io.type(io.stdout) == 'file' and ok and term.isatty(io.stdout)
  if not ok or not isatty or not term.colors then
    return function(c) return c end
  end
  return function(c)
    for token in key:gmatch("[^%.]+") do
      c = term.colors[token](c)
    end
    return c
  end
end
})

local function fmt_string(arg)
  if type(arg) == "string" then
    return string.format("(string) '%s'", arg)
  end
end

-- A version of tostring which formats numbers more precisely.
local function tostr(arg)
  if type(arg) ~= "number" then
    return tostring(arg)
  end

  if arg ~= arg then
    return "NaN"
  elseif arg == 1/0 then
    return "Inf"
  elseif arg == -1/0 then
    return "-Inf"
  end

  local str = string.format("%.20g", arg)

  if math.type and math.type(arg) == "float" and not str:find("[%.,]") then
    -- Number is a float but looks like an integer.
    -- Insert ".0" after first run of digits.
    str = str:gsub("%d+", "%0.0", 1)
  end

  return str
end

local function fmt_number(arg)
  if type(arg) == "number" then
    return string.format("(number) %s", tostr(arg))
  end
end

local function fmt_boolean(arg)
  if type(arg) == "boolean" then
    return string.format("(boolean) %s", tostring(arg))
  end
end

local function fmt_nil(arg)
  if type(arg) == "nil" then
    return "(nil)"
  end
end

local type_priorities = {
  number = 1,
  boolean = 2,
  string = 3,
  table = 4,
  ["function"] = 5,
  userdata = 6,
  thread = 7
}

local function is_in_array_part(key, length)
  return type(key) == "number" and 1 <= key and key <= length and math.floor(key) == key
end

local function get_sorted_keys(t)
  local keys = {}
  local nkeys = 0

  for key in pairs(t) do
    nkeys = nkeys + 1
    keys[nkeys] = key
  end

  local length = #t

  local function key_comparator(key1, key2)
    local type1, type2 = type(key1), type(key2)
    local priority1 = is_in_array_part(key1, length) and 0 or type_priorities[type1] or 8
    local priority2 = is_in_array_part(key2, length) and 0 or type_priorities[type2] or 8

    if priority1 == priority2 then
      if type1 == "string" or type1 == "number" then
        return key1 < key2
      elseif type1 == "boolean" then
        return key1  -- put true before false
      end
    else
      return priority1 < priority2
    end
  end

  table.sort(keys, key_comparator)
  return keys, nkeys
end

local function fmt_table(arg, fmtargs)
  if type(arg) ~= "table" then
    return
  end

  local tmax = assert:get_parameter("TableFormatLevel")
  local showrec = assert:get_parameter("TableFormatShowRecursion")
  local errchar = assert:get_parameter("TableErrorHighlightCharacter") or ""
  local errcolor = assert:get_parameter("TableErrorHighlightColor") or "none"
  local crumbs = fmtargs and fmtargs.crumbs or {}
  local cache = {}
  local type_desc

  if getmetatable(arg) == nil then
    type_desc = "(" .. tostring(arg) .. ") "
  elseif not pcall(setmetatable, arg, getmetatable(arg)) then
    -- cannot set same metatable, so it is protected, skip id
    type_desc = "(table) "
  else
    -- unprotected metatable, temporary remove the mt
    local mt = getmetatable(arg)
    setmetatable(arg, nil)
    type_desc = "(" .. tostring(arg) .. ") "
    setmetatable(arg, mt)
  end

  local function ft(t, l, with_crumbs)
    if showrec and cache[t] and cache[t] > 0 then
      return "{ ... recursive }"
    end

    if next(t) == nil then
      return "{ }"
    end

    if l > tmax and tmax >= 0 then
      return "{ ... more }"
    end

    local result = "{"
    local keys, nkeys = get_sorted_keys(t)

    cache[t] = (cache[t] or 0) + 1
    local crumb = crumbs[#crumbs - l + 1]

    for i = 1, nkeys do
      local k = keys[i]
      local v = t[k]
      local use_crumbs = with_crumbs and k == crumb

      if type(v) == "table" then
        v = ft(v, l + 1, use_crumbs)
      elseif type(v) == "string" then
        v = "'"..v.."'"
      end

      local ch = use_crumbs and errchar or ""
      local indent = string.rep(" ",l * 2 - ch:len())
      local mark = (ch:len() == 0 and "" or colors[errcolor](ch))
      result = result .. string.format("\n%s%s[%s] = %s", indent, mark, tostr(k), tostr(v))
    end

    cache[t] = cache[t] - 1

    return result .. " }"
  end

  return type_desc .. ft(arg, 1, true)
end

local function fmt_function(arg)
  if type(arg) == "function" then
    local debug_info = debug.getinfo(arg)
    return string.format("%s @ line %s in %s", tostring(arg), tostring(debug_info.linedefined), tostring(debug_info.source))
  end
end

local function fmt_userdata(arg)
  if type(arg) == "userdata" then
    return string.format("(userdata) '%s'", tostring(arg))
  end
end

local function fmt_thread(arg)
  if type(arg) == "thread" then
    return string.format("(thread) '%s'", tostring(arg))
  end
end

assert:add_formatter(fmt_string)
assert:add_formatter(fmt_number)
assert:add_formatter(fmt_boolean)
assert:add_formatter(fmt_nil)
assert:add_formatter(fmt_table)
assert:add_formatter(fmt_function)
assert:add_formatter(fmt_userdata)
assert:add_formatter(fmt_thread)
-- Set default table display depth for table formatter
assert:set_parameter("TableFormatLevel", 3)
assert:set_parameter("TableFormatShowRecursion", false)
assert:set_parameter("TableErrorHighlightCharacter", "*")
assert:set_parameter("TableErrorHighlightColor", "none")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.formatters.binarystring" ] = function( ... ) local arg = _G.arg;
local format = function (str)
  if type(str) ~= "string" then return nil end
  local result = "Binary string length; " .. tostring(#str) .. " bytes\n"
  local i = 1
  local hex = ""
  local chr = ""
  while i <= #str do
    local byte = str:byte(i)
    hex = string.format("%s%2x ", hex, byte)
    if byte < 32 then byte = string.byte(".") end
    chr = chr .. string.char(byte)
    if math.floor(i/16) == i/16 or i == #str then
      -- reached end of line
      hex = hex .. string.rep(" ", 16 * 3 - #hex)
      chr = chr .. string.rep(" ", 16 - #chr)

      result = result .. hex:sub(1, 8 * 3) .. "  " .. hex:sub(8*3+1, -1) .. " " .. chr:sub(1,8) .. " " .. chr:sub(9,-1) .. "\n"

      hex = ""
      chr = ""
    end
    i = i + 1
  end
  return result
end

return format
end
end

do
local _ENV = _ENV
package.preload[ "luassert.languages.ar" ] = function( ... ) local arg = _G.arg;
local s = require('say')

s:set_namespace("ar")

s:set("assertion.same.positive", "تُوُقِّعَ تَماثُلُ الكائِنات.\nتَمَّ إدخال:\n %s.\nبَينَما كانَ مِن المُتَوقَّع:\n %s.")
s:set("assertion.same.negative", "تُوُقِّعَ إختِلافُ الكائِنات.\nتَمَّ إدخال:\n %s.\nبَينَما كانَ مِن غَيرِ المُتَوقَّع:\n %s.")

s:set("assertion.equals.positive", "تُوُقِّعَ أن تَتَساوىْ الكائِنات.\nتمَّ إِدخال:\n %s.\nبَينَما كانَ من المُتَوقَّع:\n %s.")
s:set("assertion.equals.negative", "تُوُقِّعَ ألّا تَتَساوىْ الكائِنات.\nتمَّ إِدخال:\n %s.\nبَينَما كانَ مِن غير المُتًوقَّع:\n %s.")

s:set("assertion.unique.positive", "تُوُقِّعَ أَنْ يَكونَ الكائِنٌ فَريد: \n%s")
s:set("assertion.unique.negative", "تُوُقِّعَ أنْ يَكونَ الكائِنٌ غَيرَ فَريد: \n%s")

s:set("assertion.error.positive", "تُوُقِّعَ إصدارُ خطأْ.")
s:set("assertion.error.negative", "تُوُقِّعَ عدم إصدارِ خطأ.")

s:set("assertion.truthy.positive", "تُوُقِّعَت قيمةٌ صَحيحة، بينما كانت: \n%s")
s:set("assertion.truthy.negative", "تُوُقِّعَت قيمةٌ غيرُ صَحيحة، بينما كانت: \n%s")

s:set("assertion.falsy.positive", "تُوُقِّعَت قيمةٌ خاطِئة، بَينَما كانت: \n%s")
s:set("assertion.falsy.negative", "تُوُقِّعَت قيمةٌ غيرُ خاطِئة، بَينَما كانت: \n%s")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.languages.en" ] = function( ... ) local arg = _G.arg;
local s = require('say')

s:set_namespace('en')

s:set("assertion.same.positive", "Expected objects to be the same.\nPassed in:\n%s\nExpected:\n%s")
s:set("assertion.same.negative", "Expected objects to not be the same.\nPassed in:\n%s\nDid not expect:\n%s")

s:set("assertion.equals.positive", "Expected objects to be equal.\nPassed in:\n%s\nExpected:\n%s")
s:set("assertion.equals.negative", "Expected objects to not be equal.\nPassed in:\n%s\nDid not expect:\n%s")

s:set("assertion.near.positive", "Expected values to be near.\nPassed in:\n%s\nExpected:\n%s +/- %s")
s:set("assertion.near.negative", "Expected values to not be near.\nPassed in:\n%s\nDid not expect:\n%s +/- %s")

s:set("assertion.matches.positive", "Expected strings to match.\nPassed in:\n%s\nExpected:\n%s")
s:set("assertion.matches.negative", "Expected strings not to match.\nPassed in:\n%s\nDid not expect:\n%s")

s:set("assertion.unique.positive", "Expected object to be unique:\n%s")
s:set("assertion.unique.negative", "Expected object to not be unique:\n%s")

s:set("assertion.error.positive", "Expected a different error.\nCaught:\n%s\nExpected:\n%s")
s:set("assertion.error.negative", "Expected no error, but caught:\n%s")

s:set("assertion.truthy.positive", "Expected to be truthy, but value was:\n%s")
s:set("assertion.truthy.negative", "Expected to not be truthy, but value was:\n%s")

s:set("assertion.falsy.positive", "Expected to be falsy, but value was:\n%s")
s:set("assertion.falsy.negative", "Expected to not be falsy, but value was:\n%s")

s:set("assertion.called.positive", "Expected to be called %s time(s), but was called %s time(s)")
s:set("assertion.called.negative", "Expected not to be called exactly %s time(s), but it was.")

s:set("assertion.called_at_least.positive", "Expected to be called at least %s time(s), but was called %s time(s)")
s:set("assertion.called_at_most.positive", "Expected to be called at most %s time(s), but was called %s time(s)")
s:set("assertion.called_more_than.positive", "Expected to be called more than %s time(s), but was called %s time(s)")
s:set("assertion.called_less_than.positive", "Expected to be called less than %s time(s), but was called %s time(s)")

s:set("assertion.called_with.positive", "Function was not called with the arguments")
s:set("assertion.called_with.negative", "Function was called with the arguments")

s:set("assertion.returned_with.positive", "Function was not returned with the arguments")
s:set("assertion.returned_with.negative", "Function was returned with the arguments")

s:set("assertion.returned_arguments.positive", "Expected to be called with %s argument(s), but was called with %s")
s:set("assertion.returned_arguments.negative", "Expected not to be called with %s argument(s), but was called with %s")

-- errors
s:set("assertion.internal.argtolittle", "the '%s' function requires a minimum of %s arguments, got: %s")
s:set("assertion.internal.badargtype", "bad argument #%s to '%s' (%s expected, got %s)")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.languages.fr" ] = function( ... ) local arg = _G.arg;
local s = require('say')

s:set_namespace('fr')

s:set("assertion.called.positive", "Prévu pour être appelé %s fois(s), mais a été appelé %s fois(s).")
s:set("assertion.called.negative", "Prévu de ne pas être appelé exactement %s fois(s), mais ceci a été le cas.")

s:set("assertion.called_at_least.positive", "Prévu pour être appelé au moins %s fois(s), mais a été appelé %s fois(s).")
s:set("assertion.called_at_most.positive", "Prévu pour être appelé au plus %s fois(s), mais a été appelé %s fois(s).")

s:set("assertion.called_more_than.positive", "Devrait être appelé plus de %s fois(s), mais a été appelé %s fois(s).")
s:set("assertion.called_less_than.positive", "Devrait être appelé moins de %s fois(s), mais a été appelé %s fois(s).")

s:set("assertion.called_with.positive", "La fonction n'a pas été appelée avec les arguments.")
s:set("assertion.called_with.negative", "La fonction a été appelée avec les arguments.")

s:set("assertion.equals.positive", "Les objets attendus doivent être égaux. \n Argument passé en: \n %s \n Attendu: \n %s.")
s:set("assertion.equals.negative", "Les objets attendus ne doivent pas être égaux. \n Argument passé en: \n %s \n Non attendu: \n %s.")

s:set("assertion.error.positive", "Une erreur différente est attendue. \n Prise: \n %s \n Attendue: \n %s.")
s:set("assertion.error.negative", "Aucune erreur attendue, mais prise: \n %s.")

s:set("assertion.falsy.positive", "Assertion supposée etre fausse mais de valeur: \n %s")
s:set("assertion.falsy.negative", "Assertion supposée etre vraie mais de valeur: \n %s")

-- errors
s:set("assertion.internal.argtolittle", "La fonction '%s' requiert un minimum de %s arguments, obtenu: %s.")
s:set("assertion.internal.badargtype", "Mauvais argument #%s pour '%s' (%s attendu, obtenu %s).")
-- errors

s:set("assertion.matches.positive", "Chaînes attendues pour correspondre. \n Argument passé en: \n %s \n Attendu: \n %s.")
s:set("assertion.matches.negative", "Les chaînes attendues ne doivent pas correspondre. \n Argument passé en: \n %s \n Non attendu: \n %s.")

s:set("assertion.near.positive", "Les valeurs attendues sont proches. \n Argument passé en: \n %s \n Attendu: \n %s +/- %s.")
s:set("assertion.near.negative", "Les valeurs attendues ne doivent pas être proches. \n Argument passé en: \n %s \n Non attendu: \n %s +/- %s.")

s:set("assertion.returned_arguments.positive", "Attendu pour être appelé avec le(s) argument(s) %s, mais a été appelé avec %s.")
s:set("assertion.returned_arguments.negative", "Attendu pour ne pas être appelé avec le(s) argument(s) %s, mais a été appelé avec %s.")

s:set("assertion.returned_with.positive", "La fonction n'a pas été retournée avec les arguments.")
s:set("assertion.returned_with.negative", "La fonction a été retournée avec les arguments.")

s:set("assertion.same.positive", "Les objets attendus sont les mêmes. \n Argument passé en: \n %s \n Attendu: \n %s.")
s:set("assertion.same.negative", "Les objets attendus ne doivent pas être les mêmes. \n Argument passé en: \n %s \n Non attendu: \n %s.")

s:set("assertion.truthy.positive", "Assertion supposee etre vraie mais de valeur: \n %s")
s:set("assertion.truthy.negative", "Assertion supposee etre fausse mais de valeur: \n %s")

s:set("assertion.unique.positive", "Objet attendu pour être unique: \n %s.")
s:set("assertion.unique.negative", "Objet attendu pour ne pas être unique: \n %s.")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.languages.ja" ] = function( ... ) local arg = _G.arg;
local s = require('say')

s:set_namespace('ja')

s:set("assertion.same.positive", "オブジェクトの内容が同一であることが期待されています。\n実際の値:\n%s\n期待されている値:\n%s")
s:set("assertion.same.negative", "オブジェクトの内容が同一でないことが期待されています。\n実際の値:\n%s\n期待されていない値:\n%s")

s:set("assertion.equals.positive", "オブジェクトが同一であることが期待されています。\n実際の値:\n%s\n期待されている値:\n%s")
s:set("assertion.equals.negative", "オブジェクトが同一でないことが期待されています。\n実際の値:\n%s\n期待されていない値:\n%s")

s:set("assertion.unique.positive", "オブジェクトがユニークであることが期待されています。:\n%s")
s:set("assertion.unique.negative", "オブジェクトがユニークでないことが期待されています。:\n%s")

s:set("assertion.error.positive", "エラーが発生することが期待されています。")
s:set("assertion.error.negative", "エラーが発生しないことが期待されています。")

s:set("assertion.truthy.positive", "真であることが期待されていますが、値は:\n%s")
s:set("assertion.truthy.negative", "真でないことが期待されていますが、値は:\n%s")

s:set("assertion.falsy.positive", "偽であることが期待されていますが、値は:\n%s")
s:set("assertion.falsy.negative", "偽でないことが期待されていますが、値は:\n%s")

s:set("assertion.called.positive", "回呼ばれることを期待されていますが、実際には%s回呼ばれています。")
s:set("assertion.called.negative", "回呼ばれることを期待されていますが、実際には%s回呼ばれています。")

s:set("assertion.called_with.positive", "関数が期待されている引数で呼ばれていません")
s:set("assertion.called_with.negative", "関数が期待されている引数で呼ばれています")

s:set("assertion.returned_arguments.positive", "期待されている返り値の数は%sですが、実際の返り値の数は%sです。")
s:set("assertion.returned_arguments.negative", "期待されていない返り値の数は%sですが、実際の返り値の数は%sです。")

-- errors
s:set("assertion.internal.argtolittle", "関数には最低%s個の引数が必要ですが、実際の引数の数は: %s")
s:set("assertion.internal.badargtype", "bad argument #%s: 関数には%s個の引数が必要ですが、実際に引数の数は: %s")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.languages.nl" ] = function( ... ) local arg = _G.arg;
local s = require('say')

s:set_namespace('nl')

s:set("assertion.same.positive", "Verwachtte objecten die vergelijkbaar zijn.\nAangeboden:\n%s\nVerwachtte:\n%s")
s:set("assertion.same.negative", "Verwachtte objecten die niet vergelijkbaar zijn.\nAangeboden:\n%s\nVerwachtte niet:\n%s")

s:set("assertion.equals.positive", "Verwachtte objecten die hetzelfde zijn.\nAangeboden:\n%s\nVerwachtte:\n%s")
s:set("assertion.equals.negative", "Verwachtte objecten die niet hetzelfde zijn.\nAangeboden:\n%s\nVerwachtte niet:\n%s")

s:set("assertion.unique.positive", "Verwachtte objecten die uniek zijn:\n%s")
s:set("assertion.unique.negative", "Verwachtte objecten die niet uniek zijn:\n%s")

s:set("assertion.error.positive", "Verwachtte een foutmelding.")
s:set("assertion.error.negative", "Verwachtte geen foutmelding.\n%s")

s:set("assertion.truthy.positive", "Verwachtte een 'warige' (thruthy) waarde, maar was:\n%s")
s:set("assertion.truthy.negative", "Verwachtte een niet 'warige' (thruthy) waarde, maar was:\n%s")

s:set("assertion.falsy.positive", "Verwachtte een 'onwarige' (falsy) waarde, maar was:\n%s")
s:set("assertion.falsy.negative", "Verwachtte een niet 'onwarige' (falsy) waarde, maar was:\n%s")

-- errors
s:set("assertion.internal.argtolittle", "de '%s' functie verwacht minimaal %s parameters, maar kreeg er: %s")
s:set("assertion.internal.badargtype", "bad argument #%s: de '%s' functie verwacht een %s als parameter, maar kreeg een: %s")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.languages.ru" ] = function( ... ) local arg = _G.arg;
local s = require('say')

s:set_namespace("ru")

s:set("assertion.same.positive", "Ожидали одинаковые объекты.\nПередали:\n%s\nОжидали:\n%s")
s:set("assertion.same.negative", "Ожидали разные объекты.\nПередали:\n%s\nНе ожидали:\n%s")

s:set("assertion.equals.positive", "Ожидали эквивалентные объекты.\nПередали:\n%s\nОжидали:\n%s")
s:set("assertion.equals.negative", "Ожидали не эквивалентные объекты.\nПередали:\n%s\nНе ожидали:\n%s")

s:set("assertion.unique.positive", "Ожидали, что объект будет уникальным:\n%s")
s:set("assertion.unique.negative", "Ожидали, что объект не будет уникальным:\n%s")

s:set("assertion.error.positive", "Ожидали ошибку.")
s:set("assertion.error.negative", "Не ожидали ошибку.\n%s")

s:set("assertion.truthy.positive", "Ожидали true, но значние оказалось:\n%s")
s:set("assertion.truthy.negative", "Ожидали не true, но значние оказалось:\n%s")

s:set("assertion.falsy.positive", "Ожидали false, но значние оказалось:\n%s")
s:set("assertion.falsy.negative", "Ожидали не false, но значние оказалось:\n%s")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.languages.ua" ] = function( ... ) local arg = _G.arg;
local s = require('say')

s:set_namespace("ua")

s:set("assertion.same.positive", "Очікували однакові обєкти.\nПередали:\n%s\nОчікували:\n%s")
s:set("assertion.same.negative", "Очікували різні обєкти.\nПередали:\n%s\nНе очікували:\n%s")

s:set("assertion.equals.positive", "Очікували еквівалентні обєкти.\nПередали:\n%s\nОчікували:\n%s")
s:set("assertion.equals.negative", "Очікували не еквівалентні обєкти.\nПередали:\n%s\nНе очікували:\n%s")

s:set("assertion.unique.positive", "Очікували, що обєкт буде унікальним:\n%s")
s:set("assertion.unique.negative", "Очікували, що обєкт не буде унікальним:\n%s")

s:set("assertion.error.positive", "Очікували помилку.")
s:set("assertion.error.negative", "Не очікували помилку.\n%s")

s:set("assertion.truthy.positive", "Очікували true, проте значння виявилось:\n%s")
s:set("assertion.truthy.negative", "Очікували не true, проте значння виявилось:\n%s")

s:set("assertion.falsy.positive", "Очікували false, проте значння виявилось:\n%s")
s:set("assertion.falsy.negative", "Очікували не false, проте значння виявилось:\n%s")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.languages.zh" ] = function( ... ) local arg = _G.arg;
local s = require('say')

s:set_namespace('zh')

s:set("assertion.same.positive", "希望对象应该相同.\n实际值:\n%s\n希望值:\n%s")
s:set("assertion.same.negative", "希望对象应该不相同.\n实际值:\n%s\n不希望与:\n%s\n相同")

s:set("assertion.equals.positive", "希望对象应该相等.\n实际值:\n%s\n希望值:\n%s")
s:set("assertion.equals.negative", "希望对象应该不相等.\n实际值:\n%s\n不希望等于:\n%s")

s:set("assertion.unique.positive", "希望对象是唯一的:\n%s")
s:set("assertion.unique.negative", "希望对象不是唯一的:\n%s")

s:set("assertion.error.positive", "希望有错误被抛出.")
s:set("assertion.error.negative", "希望没有错误被抛出.\n%s")

s:set("assertion.truthy.positive", "希望结果为真，但是实际为:\n%s")
s:set("assertion.truthy.negative", "希望结果不为真，但是实际为:\n%s")

s:set("assertion.falsy.positive", "希望结果为假，但是实际为:\n%s")
s:set("assertion.falsy.negative", "希望结果不为假，但是实际为:\n%s")

s:set("assertion.called.positive", "希望被调用%s次, 但实际被调用了%s次")
s:set("assertion.called.negative", "不希望正好被调用%s次, 但是正好被调用了那么多次.")

s:set("assertion.called_with.positive", "希望没有参数的调用函数")
s:set("assertion.called_with.negative", "希望有参数的调用函数")

-- errors
s:set("assertion.internal.argtolittle", "函数'%s'需要最少%s个参数, 实际有%s个参数\n")
s:set("assertion.internal.badargtype", "bad argument #%s: 函数'%s'需要一个%s作为参数, 实际为: %s\n")
end
end

do
local _ENV = _ENV
package.preload[ "luassert.match" ] = function( ... ) local arg = _G.arg;
local namespace = require 'luassert.namespaces'
local util = require 'luassert.util'

local matcher_mt = {
  __call = function(self, value)
    return self.callback(value) == self.mod
  end,
}

local state_mt = {
  __call = function(self, ...)
    local keys = util.extract_keys("matcher", self.tokens)
    self.tokens = {}

    local matcher

    for _, key in ipairs(keys) do
      matcher = namespace.matcher[key] or matcher
    end

    if matcher then
      for _, key in ipairs(keys) do
        if namespace.modifier[key] then
          namespace.modifier[key].callback(self)
        end
      end

      local arguments = {...}
      arguments.n = select('#', ...) -- add argument count for trailing nils
      local matches = matcher.callback(self, arguments, util.errorlevel())
      return setmetatable({
        name = matcher.name,
        mod = self.mod,
        callback = matches,
      }, matcher_mt)
    else
      local arguments = {...}
      arguments.n = select('#', ...) -- add argument count for trailing nils

      for _, key in ipairs(keys) do
        if namespace.modifier[key] then
          namespace.modifier[key].callback(self, arguments, util.errorlevel())
        end
      end
    end

    return self
  end,

  __index = function(self, key)
    for token in key:lower():gmatch('[^_]+') do
      table.insert(self.tokens, token)
    end

    return self
  end
}

local match = {
  _ = setmetatable({mod=true, callback=function() return true end}, matcher_mt),

  state = function() return setmetatable({mod=true, tokens={}}, state_mt) end,

  is_matcher = function(object)
    return type(object) == "table" and getmetatable(object) == matcher_mt
  end,

  is_ref_matcher = function(object)
    local ismatcher = (type(object) == "table" and getmetatable(object) == matcher_mt)
    return ismatcher and object.name == "ref"
  end,
}

local mt = {
  __index = function(self, key)
    return rawget(self, key) or self.state()[key]
  end,
}

return setmetatable(match, mt)
end
end

do
local _ENV = _ENV
package.preload[ "luassert.matchers" ] = function( ... ) local arg = _G.arg;
-- load basic machers
require('luassert.matchers.core')
require('luassert.matchers.composite')
end
end

do
local _ENV = _ENV
package.preload[ "luassert.matchers.composite" ] = function( ... ) local arg = _G.arg;
local assert = require('luassert.assert')
local match = require ('luassert.match')
local s = require('say')

local function none(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 0, s("assertion.internal.argtolittle", { "none", 1, tostring(argcnt) }), level)
  for i = 1, argcnt do
    assert(match.is_matcher(arguments[i]), s("assertion.internal.badargtype", { 1, "none", "matcher", type(arguments[i]) }), level)
  end

  return function(value)
    for _, matcher in ipairs(arguments) do
      if matcher(value) then
        return false
      end
    end
    return true
  end
end

local function any(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 0, s("assertion.internal.argtolittle", { "any", 1, tostring(argcnt) }), level)
  for i = 1, argcnt do
    assert(match.is_matcher(arguments[i]), s("assertion.internal.badargtype", { 1, "any", "matcher", type(arguments[i]) }), level)
  end

  return function(value)
    for _, matcher in ipairs(arguments) do
      if matcher(value) then
        return true
      end
    end
    return false
  end
end

local function all(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 0, s("assertion.internal.argtolittle", { "all", 1, tostring(argcnt) }), level)
  for i = 1, argcnt do
    assert(match.is_matcher(arguments[i]), s("assertion.internal.badargtype", { 1, "all", "matcher", type(arguments[i]) }), level)
  end

  return function(value)
    for _, matcher in ipairs(arguments) do
      if not matcher(value) then
        return false
      end
    end
    return true
  end
end

assert:register("matcher", "none_of", none)
assert:register("matcher", "any_of", any)
assert:register("matcher", "all_of", all)
end
end

do
local _ENV = _ENV
package.preload[ "luassert.matchers.core" ] = function( ... ) local arg = _G.arg;
-- module will return the list of matchers, and registers matchers with the main assert engine

-- matchers take 1 parameters;
-- 1) state
-- 2) arguments list. The list has a member 'n' with the argument count to check for trailing nils
-- 3) level The level of the error position relative to the called function
-- returns; function (or callable object); a function that, given an argument, returns a boolean

local assert = require('luassert.assert')
local astate = require('luassert.state')
local util = require('luassert.util')
local s = require('say')

local function format(val)
  return astate.format_argument(val) or tostring(val)
end

local function unique(state, arguments, level)
  local deep = arguments[1]
  return function(value)
    local list = value
    for k,v in pairs(list) do
      for k2, v2 in pairs(list) do
        if k ~= k2 then
          if deep and util.deepcompare(v, v2, true) then
            return false
          else
            if v == v2 then
              return false
            end
          end
        end
      end
    end
    return true
  end
end

local function near(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 1, s("assertion.internal.argtolittle", { "near", 2, tostring(argcnt) }), level)
  local expected = tonumber(arguments[1])
  local tolerance = tonumber(arguments[2])
  local numbertype = "number or object convertible to a number"
  assert(expected, s("assertion.internal.badargtype", { 1, "near", numbertype, format(arguments[1]) }), level)
  assert(tolerance, s("assertion.internal.badargtype", { 2, "near", numbertype, format(arguments[2]) }), level)

  return function(value)
    local actual = tonumber(value)
    if not actual then return false end
    return (actual >= expected - tolerance and actual <= expected + tolerance)
  end
end

local function matches(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 0, s("assertion.internal.argtolittle", { "matches", 1, tostring(argcnt) }), level)
  local pattern = arguments[1]
  local init = arguments[2]
  local plain = arguments[3]
  local stringtype = "string or object convertible to a string"
  assert(type(pattern) == "string", s("assertion.internal.badargtype", { 1, "matches", "string", type(arguments[1]) }), level)
  assert(init == nil or tonumber(init), s("assertion.internal.badargtype", { 2, "matches", "number", type(arguments[2]) }), level)

  return function(value)
    local actualtype = type(value)
    local actual = nil
    if actualtype == "string" or actualtype == "number" or
      actualtype == "table" and (getmetatable(value) or {}).__tostring then
      actual = tostring(value)
    end
    if not actual then return false end
    return (actual:find(pattern, init, plain) ~= nil)
  end
end

local function equals(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 0, s("assertion.internal.argtolittle", { "equals", 1, tostring(argcnt) }), level)
  return function(value)
    return value == arguments[1]
  end
end

local function same(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  assert(argcnt > 0, s("assertion.internal.argtolittle", { "same", 1, tostring(argcnt) }), level)
  return function(value)
    if type(value) == 'table' and type(arguments[1]) == 'table' then
      local result = util.deepcompare(value, arguments[1], true)
      return result
    end
    return value == arguments[1]
  end
end

local function ref(state, arguments, level)
  local level = (level or 1) + 1
  local argcnt = arguments.n
  local argtype = type(arguments[1])
  local isobject = (argtype == "table" or argtype == "function" or argtype == "thread" or argtype == "userdata")
  assert(argcnt > 0, s("assertion.internal.argtolittle", { "ref", 1, tostring(argcnt) }), level)
  assert(isobject, s("assertion.internal.badargtype", { 1, "ref", "object", argtype }), level)
  return function(value)
    return value == arguments[1]
  end
end

local function is_true(state, arguments, level)
  return function(value)
    return value == true
  end
end

local function is_false(state, arguments, level)
  return function(value)
    return value == false
  end
end

local function truthy(state, arguments, level)
  return function(value)
    return value ~= false and value ~= nil
  end
end

local function falsy(state, arguments, level)
  local is_truthy = truthy(state, arguments, level)
  return function(value)
    return not is_truthy(value)
  end
end

local function is_type(state, arguments, level, etype)
  return function(value)
    return type(value) == etype
  end
end

local function is_nil(state, arguments, level)      return is_type(state, arguments, level, "nil")      end
local function is_boolean(state, arguments, level)  return is_type(state, arguments, level, "boolean")  end
local function is_number(state, arguments, level)   return is_type(state, arguments, level, "number")   end
local function is_string(state, arguments, level)   return is_type(state, arguments, level, "string")   end
local function is_table(state, arguments, level)    return is_type(state, arguments, level, "table")    end
local function is_function(state, arguments, level) return is_type(state, arguments, level, "function") end
local function is_userdata(state, arguments, level) return is_type(state, arguments, level, "userdata") end
local function is_thread(state, arguments, level)   return is_type(state, arguments, level, "thread")   end

assert:register("matcher", "true", is_true)
assert:register("matcher", "false", is_false)

assert:register("matcher", "nil", is_nil)
assert:register("matcher", "boolean", is_boolean)
assert:register("matcher", "number", is_number)
assert:register("matcher", "string", is_string)
assert:register("matcher", "table", is_table)
assert:register("matcher", "function", is_function)
assert:register("matcher", "userdata", is_userdata)
assert:register("matcher", "thread", is_thread)

assert:register("matcher", "ref", ref)
assert:register("matcher", "same", same)
assert:register("matcher", "matches", matches)
assert:register("matcher", "match", matches)
assert:register("matcher", "near", near)
assert:register("matcher", "equals", equals)
assert:register("matcher", "equal", equals)
assert:register("matcher", "unique", unique)
assert:register("matcher", "truthy", truthy)
assert:register("matcher", "falsy", falsy)
end
end

do
local _ENV = _ENV
package.preload[ "luassert.mock" ] = function( ... ) local arg = _G.arg;
-- module will return a mock module table, and will not register any assertions
local spy = require 'luassert.spy'
local stub = require 'luassert.stub'

local function mock_apply(object, action)
  if type(object) ~= "table" then return end
  if spy.is_spy(object) then
    return object[action](object)
  end
  for k,v in pairs(object) do
    mock_apply(v, action)
  end
  return object
end

local mock
mock = {
  new = function(object, dostub, func, self, key)
    local visited = {}
    local function do_mock(object, self, key)
      local mock_handlers = {
        ["table"] = function()
          if spy.is_spy(object) or visited[object] then return end
          visited[object] = true
          for k,v in pairs(object) do
            object[k] = do_mock(v, object, k)
          end
          return object
        end,
        ["function"] = function()
          if dostub then
            return stub(self, key, func)
          elseif self==nil then
            return spy.new(object)
          else
            return spy.on(self, key)
          end
        end
      }
      local handler = mock_handlers[type(object)]
      return handler and handler() or object
    end
    return do_mock(object, self, key)
  end,

  clear = function(object)
    return mock_apply(object, "clear")
  end,

  revert = function(object)
    return mock_apply(object, "revert")
  end
}

return setmetatable(mock, {
  __call = function(self, ...)
    -- mock originally was a function only. Now that it is a module table
    -- the __call method is required for backward compatibility
    return mock.new(...)
  end
})
end
end

do
local _ENV = _ENV
package.preload[ "luassert.modifiers" ] = function( ... ) local arg = _G.arg;
-- module will not return anything, only register assertions/modifiers with the main assert engine
local assert = require('luassert.assert')

local function is(state)
  return state
end

local function is_not(state)
  state.mod = not state.mod
  return state
end

assert:register("modifier", "is", is)
assert:register("modifier", "are", is)
assert:register("modifier", "was", is)
assert:register("modifier", "has", is)
assert:register("modifier", "does", is)
assert:register("modifier", "not", is_not)
assert:register("modifier", "no", is_not)
end
end

do
local _ENV = _ENV
package.preload[ "luassert.namespaces" ] = function( ... ) local arg = _G.arg;
-- stores the list of namespaces
return {}
end
end

do
local _ENV = _ENV
package.preload[ "luassert.spy" ] = function( ... ) local arg = _G.arg;
-- module will return spy table, and register its assertions with the main assert engine
local assert = require('luassert.assert')
local util = require('luassert.util')

-- Spy metatable
local spy_mt = {
  __call = function(self, ...)
    local arguments = {...}
    arguments.n = select('#',...)  -- add argument count for trailing nils
    table.insert(self.calls, util.copyargs(arguments))
    local function get_returns(...)
      local returnvals = {...}
      returnvals.n = select('#',...)  -- add argument count for trailing nils
      table.insert(self.returnvals, util.copyargs(returnvals))
      return ...
    end
    return get_returns(self.callback(...))
  end
}

local spy   -- must make local before defining table, because table contents refers to the table (recursion)
spy = {
  new = function(callback)
    callback = callback or function() end
    if not util.callable(callback) then
      error("Cannot spy on type '" .. type(callback) .. "', only on functions or callable elements", util.errorlevel())
    end
    local s = setmetatable({
      calls = {},
      returnvals = {},
      callback = callback,

      target_table = nil, -- these will be set when using 'spy.on'
      target_key = nil,

      revert = function(self)
        if not self.reverted then
          if self.target_table and self.target_key then
            self.target_table[self.target_key] = self.callback
          end
          self.reverted = true
        end
        return self.callback
      end,

      clear = function(self)
        self.calls = {}
        self.returnvals = {}
        return self
      end,

      called = function(self, times, compare)
        if times or compare then
          local compare = compare or function(count, expected) return count == expected end
          return compare(#self.calls, times), #self.calls
        end

        return (#self.calls > 0), #self.calls
      end,

      called_with = function(self, args)
        return util.matchargs(self.calls, args) ~= nil
      end,

      returned_with = function(self, args)
        return util.matchargs(self.returnvals, args) ~= nil
      end
    }, spy_mt)
    assert:add_spy(s)  -- register with the current state
    return s
  end,

  is_spy = function(object)
    return type(object) == "table" and getmetatable(object) == spy_mt
  end,

  on = function(target_table, target_key)
    local s = spy.new(target_table[target_key])
    target_table[target_key] = s
    -- store original data
    s.target_table = target_table
    s.target_key = target_key

    return s
  end
}

local function set_spy(state, arguments, level)
  state.payload = arguments[1]
  if arguments[2] ~= nil then
    state.failure_message = arguments[2]
  end
end

local function returned_with(state, arguments, level)
  local level = (level or 1) + 1
  local payload = rawget(state, "payload")
  if payload and payload.returned_with then
    return state.payload:returned_with(arguments)
  else
    error("'returned_with' must be chained after 'spy(aspy)'", level)
  end
end

local function called_with(state, arguments, level)
  local level = (level or 1) + 1
  local payload = rawget(state, "payload")
  if payload and payload.called_with then
    return state.payload:called_with(arguments)
  else
    error("'called_with' must be chained after 'spy(aspy)'", level)
  end
end

local function called(state, arguments, level, compare)
  local level = (level or 1) + 1
  local num_times = arguments[1]
  if not num_times and not state.mod then
    state.mod = true
    num_times = 0
  end
  local payload = rawget(state, "payload")
  if payload and type(payload) == "table" and payload.called then
    local result, count = state.payload:called(num_times, compare)
    arguments[1] = tostring(num_times or ">0")
    util.tinsert(arguments, 2, tostring(count))
    arguments.nofmt = arguments.nofmt or {}
    arguments.nofmt[1] = true
    arguments.nofmt[2] = true
    return result
  elseif payload and type(payload) == "function" then
    error("When calling 'spy(aspy)', 'aspy' must not be the original function, but the spy function replacing the original", level)
  else
    error("'called' must be chained after 'spy(aspy)'", level)
  end
end

local function called_at_least(state, arguments, level)
  local level = (level or 1) + 1
  return called(state, arguments, level, function(count, expected) return count >= expected end)
end

local function called_at_most(state, arguments, level)
  local level = (level or 1) + 1
  return called(state, arguments, level, function(count, expected) return count <= expected end)
end

local function called_more_than(state, arguments, level)
  local level = (level or 1) + 1
  return called(state, arguments, level, function(count, expected) return count > expected end)
end

local function called_less_than(state, arguments, level)
  local level = (level or 1) + 1
  return called(state, arguments, level, function(count, expected) return count < expected end)
end

assert:register("modifier", "spy", set_spy)
assert:register("assertion", "returned_with", returned_with, "assertion.returned_with.positive", "assertion.returned_with.negative")
assert:register("assertion", "called_with", called_with, "assertion.called_with.positive", "assertion.called_with.negative")
assert:register("assertion", "called", called, "assertion.called.positive", "assertion.called.negative")
assert:register("assertion", "called_at_least", called_at_least, "assertion.called_at_least.positive", "assertion.called_less_than.positive")
assert:register("assertion", "called_at_most", called_at_most, "assertion.called_at_most.positive", "assertion.called_more_than.positive")
assert:register("assertion", "called_more_than", called_more_than, "assertion.called_more_than.positive", "assertion.called_at_most.positive")
assert:register("assertion", "called_less_than", called_less_than, "assertion.called_less_than.positive", "assertion.called_at_least.positive")

return setmetatable(spy, {
  __call = function(self, ...)
    return spy.new(...)
  end
})
end
end

do
local _ENV = _ENV
package.preload[ "luassert.state" ] = function( ... ) local arg = _G.arg;
-- maintains a state of the assert engine in a linked-list fashion
-- records; formatters, parameters, spies and stubs

local state_mt = {
  __call = function(self)
    self:revert()
  end
}

local spies_mt = { __mode = "kv" }

local nilvalue = {} -- unique ID to refer to nil values for parameters

-- will hold the current state
local current

-- exported module table
local state = {}

------------------------------------------------------
-- Reverts to a (specific) snapshot.
-- @param self (optional) the snapshot to revert to. If not provided, it will revert to the last snapshot.
state.revert = function(self)
  if not self then
    -- no snapshot given, so move 1 up
    self = current
    if not self.previous then
      -- top of list, no previous one, nothing to do
      return
    end
  end
  if getmetatable(self) ~= state_mt then error("Value provided is not a valid snapshot", 2) end
  
  if self.next then
    self.next:revert()
  end
  -- revert formatters in 'last'
  self.formatters = {}
  -- revert parameters in 'last'
  self.parameters = {}
  -- revert spies/stubs in 'last'
  for s,_ in pairs(self.spies) do
    self.spies[s] = nil
    s:revert()
  end
  setmetatable(self, nil) -- invalidate as a snapshot
  current = self.previous
  current.next = nil
end

------------------------------------------------------
-- Creates a new snapshot.
-- @return snapshot table
state.snapshot = function()
  local s = current
  local new = setmetatable ({
    formatters = {},
    parameters = {},
    spies = setmetatable({}, spies_mt),
    previous = current,
    revert = state.revert,
  }, state_mt)
  if current then current.next = new end
  current = new
  return current
end


--  FORMATTERS
state.add_formatter = function(callback)
  table.insert(current.formatters, 1, callback)
end

state.remove_formatter = function(callback, s)
  s = s or current
  for i, v in ipairs(s.formatters) do
    if v == callback then
      table.remove(s.formatters, i)
      break
    end
  end
  -- wasn't found, so traverse up 1 state
  if s.previous then
    state.remove_formatter(callback, s.previous)
  end
end

state.format_argument = function(val, s, fmtargs)
  s = s or current
  for _, fmt in ipairs(s.formatters) do
    local valfmt = fmt(val, fmtargs)
    if valfmt ~= nil then return valfmt end
  end
  -- nothing found, check snapshot 1 up in list
  if s.previous then
    return state.format_argument(val, s.previous, fmtargs)
  end
  return nil -- end of list, couldn't format
end


--  PARAMETERS
state.set_parameter = function(name, value)
  if value == nil then value = nilvalue end
  current.parameters[name] = value
end

state.get_parameter = function(name, s)
  s = s or current
  local val = s.parameters[name]
  if val == nil and s.previous then
    -- not found, so check 1 up in list
    return state.get_parameter(name, s.previous)
  end
  if val ~= nilvalue then
    return val
  end
  return nil
end

--  SPIES / STUBS
state.add_spy = function(spy)
  current.spies[spy] = true
end

state.snapshot()  -- create initial state

return state
end
end

do
local _ENV = _ENV
package.preload[ "luassert.stub" ] = function( ... ) local arg = _G.arg;
-- module will return a stub module table
local assert = require 'luassert.assert'
local spy = require 'luassert.spy'
local util = require 'luassert.util'
local unpack = require 'luassert.compatibility'.unpack

local stub = {}

function stub.new(object, key, ...)
  if object == nil and key == nil then
    -- called without arguments, create a 'blank' stub
    object = {}
    key = ""
  end
  local return_values_count = select("#", ...)
  local return_values = {...}
  assert(type(object) == "table" and key ~= nil, "stub.new(): Can only create stub on a table key, call with 2 params; table, key", util.errorlevel())
  assert(object[key] == nil or util.callable(object[key]), "stub.new(): The element for which to create a stub must either be callable, or be nil", util.errorlevel())
  local old_elem = object[key]    -- keep existing element (might be nil!)

  local fn = (return_values_count == 1 and util.callable(return_values[1]) and return_values[1])
  local defaultfunc = fn or function()
    return unpack(return_values, 1, return_values_count)
  end
  local oncalls = {}
  local callbacks = {}
  local stubfunc = function(...)
    local args = {...}
    args.n = select('#', ...)
    local match = util.matchargs(oncalls, args)
    if match then
      return callbacks[match](...)
    end
    return defaultfunc(...)
  end

  object[key] = stubfunc          -- set the stubfunction
  local s = spy.on(object, key)   -- create a spy on top of the stub function
  local spy_revert = s.revert     -- keep created revert function

  s.revert = function(self)       -- wrap revert function to restore original element
    if not self.reverted then
      spy_revert(self)
      object[key] = old_elem
      self.reverted = true
    end
    return old_elem
  end

  s.returns = function(...)
    local return_args = {...}
    local n = select('#', ...)
    defaultfunc = function()
      return unpack(return_args, 1, n)
    end
    return s
  end

  s.invokes = function(func)
    defaultfunc = function(...)
      return func(...)
    end
    return s
  end

  s.by_default = {
    returns = s.returns,
    invokes = s.invokes,
  }

  s.on_call_with = function(...)
    local match_args = {...}
    match_args.n = select('#', ...)
    match_args = util.copyargs(match_args)
    return {
      returns = function(...)
        local return_args = {...}
        local n = select('#', ...)
        table.insert(oncalls, match_args)
        callbacks[match_args] = function()
          return unpack(return_args, 1, n)
        end
        return s
      end,
      invokes = function(func)
        table.insert(oncalls, match_args)
        callbacks[match_args] = function(...)
          return func(...)
        end
        return s
      end
    }
  end

  return s
end

local function set_stub(state, arguments)
  state.payload = arguments[1]
  state.failure_message = arguments[2]
end

assert:register("modifier", "stub", set_stub)

return setmetatable(stub, {
  __call = function(self, ...)
    -- stub originally was a function only. Now that it is a module table
    -- the __call method is required for backward compatibility
    return stub.new(...)
  end
})
end
end

do
local _ENV = _ENV
package.preload[ "luassert.util" ] = function( ... ) local arg = _G.arg;
local util = {}
function util.deepcompare(t1,t2,ignore_mt,cycles,thresh1,thresh2)
  local ty1 = type(t1)
  local ty2 = type(t2)
  -- non-table types can be directly compared
  if ty1 ~= 'table' or ty2 ~= 'table' then return t1 == t2 end
  local mt1 = debug.getmetatable(t1)
  local mt2 = debug.getmetatable(t2)
  -- would equality be determined by metatable __eq?
  if mt1 and mt1 == mt2 and mt1.__eq then
    -- then use that unless asked not to
    if not ignore_mt then return t1 == t2 end
  else -- we can skip the deep comparison below if t1 and t2 share identity
    if rawequal(t1, t2) then return true end
  end

  -- handle recursive tables
  cycles = cycles or {{},{}}
  thresh1, thresh2 = (thresh1 or 1), (thresh2 or 1)
  cycles[1][t1] = (cycles[1][t1] or 0)
  cycles[2][t2] = (cycles[2][t2] or 0)
  if cycles[1][t1] == 1 or cycles[2][t2] == 1 then
    thresh1 = cycles[1][t1] + 1
    thresh2 = cycles[2][t2] + 1
  end
  if cycles[1][t1] > thresh1 and cycles[2][t2] > thresh2 then
    return true
  end

  cycles[1][t1] = cycles[1][t1] + 1
  cycles[2][t2] = cycles[2][t2] + 1

  for k1,v1 in next, t1 do
    local v2 = t2[k1]
    if v2 == nil then
      return false, {k1}
    end

    local same, crumbs = util.deepcompare(v1,v2,nil,cycles,thresh1,thresh2)
    if not same then
      crumbs = crumbs or {}
      table.insert(crumbs, k1)
      return false, crumbs
    end
  end
  for k2,_ in next, t2 do
    -- only check whether each element has a t1 counterpart, actual comparison
    -- has been done in first loop above
    if t1[k2] == nil then return false, {k2} end
  end

  cycles[1][t1] = cycles[1][t1] - 1
  cycles[2][t2] = cycles[2][t2] - 1

  return true
end

function util.shallowcopy(t)
  if type(t) ~= "table" then return t end
  local copy = {}
  for k,v in next, t do
    copy[k] = v
  end
  return copy
end

function util.deepcopy(t, deepmt, cache)
  local spy = require 'luassert.spy'
  if type(t) ~= "table" then return t end
  local copy = {}

  -- handle recursive tables
  local cache = cache or {}
  if cache[t] then return cache[t] end
  cache[t] = copy

  for k,v in next, t do
    copy[k] = (spy.is_spy(v) and v or util.deepcopy(v, deepmt, cache))
  end
  if deepmt then
    debug.setmetatable(copy, util.deepcopy(debug.getmetatable(t, nil, cache)))
  else
    debug.setmetatable(copy, debug.getmetatable(t))
  end
  return copy
end

-----------------------------------------------
-- Copies arguments as a list of arguments
-- @param args the arguments of which to copy
-- @return the copy of the arguments
function util.copyargs(args)
  local copy = {}
  local match = require 'luassert.match'
  local spy = require 'luassert.spy'
  for k,v in pairs(args) do
    copy[k] = ((match.is_matcher(v) or spy.is_spy(v)) and v or util.deepcopy(v))
  end
  return { vals = copy, refs = util.shallowcopy(args) }
end

-----------------------------------------------
-- Finds matching arguments in a saved list of arguments
-- @param argslist list of arguments from which to search
-- @param args the arguments of which to find a match
-- @return the matching arguments if a match is found, otherwise nil
function util.matchargs(argslist, args)
  local function matches(t1, t2, t1refs)
    local match = require 'luassert.match'
    for k1,v1 in pairs(t1) do
      local v2 = t2[k1]
      if match.is_matcher(v1) then
        if not v1(v2) then return false end
      elseif match.is_matcher(v2) then
        if match.is_ref_matcher(v2) then v1 = t1refs[k1] end
        if not v2(v1) then return false end
      elseif (v2 == nil or not util.deepcompare(v1,v2)) then
        return false
      end
    end
    for k2,v2 in pairs(t2) do
      -- only check wether each element has a t1 counterpart, actual comparison
      -- has been done in first loop above
      local v1 = t1[k2]
      if v1 == nil then
        -- no t1 counterpart, so try to compare using matcher
        if match.is_matcher(v2) then
          if not v2(v1) then return false end
        else
          return false
        end
      end
    end
    return true
  end
  for k,v in ipairs(argslist) do
    if matches(v.vals, args, v.refs) then
      return v
    end
  end
  return nil
end

-----------------------------------------------
-- table.insert() replacement that respects nil values.
-- The function will use table field 'n' as indicator of the
-- table length, if not set, it will be added.
-- @param t table into which to insert
-- @param pos (optional) position in table where to insert. NOTE: not optional if you want to insert a nil-value!
-- @param val value to insert
-- @return No return values
function util.tinsert(...)
  -- check optional POS value
  local args = {...}
  local c = select('#',...)
  local t = args[1]
  local pos = args[2]
  local val = args[3]
  if c < 3 then
    val = pos
    pos = nil
  end
  -- set length indicator n if not present (+1)
  t.n = (t.n or #t) + 1
  if not pos then
    pos = t.n
  elseif pos > t.n then
    -- out of our range
    t[pos] = val
    t.n = pos
  end
  -- shift everything up 1 pos
  for i = t.n, pos + 1, -1 do
    t[i]=t[i-1]
  end
  -- add element to be inserted
  t[pos] = val
end
-----------------------------------------------
-- table.remove() replacement that respects nil values.
-- The function will use table field 'n' as indicator of the
-- table length, if not set, it will be added.
-- @param t table from which to remove
-- @param pos (optional) position in table to remove
-- @return No return values
function util.tremove(t, pos)
  -- set length indicator n if not present (+1)
  t.n = t.n or #t
  if not pos then
    pos = t.n
  elseif pos > t.n then
    local removed = t[pos]
    -- out of our range
    t[pos] = nil
    return removed
  end
  local removed = t[pos]
  -- shift everything up 1 pos
  for i = pos, t.n do
    t[i]=t[i+1]
  end
  -- set size, clean last
  t[t.n] = nil
  t.n = t.n - 1
  return removed
end

-----------------------------------------------
-- Checks an element to be callable.
-- The type must either be a function or have a metatable
-- containing an '__call' function.
-- @param object element to inspect on being callable or not
-- @return boolean, true if the object is callable
function util.callable(object)
  return type(object) == "function" or type((debug.getmetatable(object) or {}).__call) == "function"
end
-----------------------------------------------
-- Checks an element has tostring.
-- The type must either be a string or have a metatable
-- containing an '__tostring' function.
-- @param object element to inspect on having tostring or not
-- @return boolean, true if the object has tostring
function util.hastostring(object)
  return type(object) == "string" or type((debug.getmetatable(object) or {}).__tostring) == "function"
end

-----------------------------------------------
-- Find the first level, not defined in the same file as the caller's
-- code file to properly report an error.
-- @param level the level to use as the caller's source file
-- @return number, the level of which to report an error
function util.errorlevel(level)
  local level = (level or 1) + 1 -- add one to get level of the caller
  local info = debug.getinfo(level)
  local source = (info or {}).source
  local file = source
  while file and (file == source or source == "=(tail call)") do
    level = level + 1
    info = debug.getinfo(level)
    source = (info or {}).source
  end
  if level > 1 then level = level - 1 end -- deduct call to errorlevel() itself
  return level
end

-----------------------------------------------
-- Extract modifier and namespace keys from list of tokens.
-- @param nspace the namespace from which to match tokens
-- @param tokens list of tokens to search for keys
-- @return table, list of keys that were extracted
function util.extract_keys(nspace, tokens)
  local namespace = require 'luassert.namespaces'

  -- find valid keys by coalescing tokens as needed, starting from the end
  local keys = {}
  local key = nil
  local i = #tokens
  while i > 0 do
    local token = tokens[i]
    key = key and (token .. '_' .. key) or token

    -- find longest matching key in the given namespace
    local longkey = i > 1 and (tokens[i-1] .. '_' .. key) or nil
    while i > 1 and longkey and namespace[nspace][longkey] do
      key = longkey
      i = i - 1
      token = tokens[i]
      longkey = (token .. '_' .. key)
    end

    if namespace.modifier[key] or namespace[nspace][key] then
      table.insert(keys, 1, key)
      key = nil
    end
    i = i - 1
  end

  -- if there's anything left we didn't recognize it
  if key then
    error("luassert: unknown modifier/" .. nspace .. ": '" .. key .."'", util.errorlevel(2))
  end

  return keys
end

return util
end
end

do
local _ENV = _ENV
package.preload[ "say" ] = function( ... ) local arg = _G.arg;
local unpack = table.unpack or unpack

local registry = { }
local current_namespace
local fallback_namespace

local s = {

  _COPYRIGHT   = "Copyright (c) 2012 Olivine Labs, LLC.",
  _DESCRIPTION = "A simple string key/value store for i18n or any other case where you want namespaced strings.",
  _VERSION     = "Say 1.3",

  set_namespace = function(self, namespace)
    current_namespace = namespace
    if not registry[current_namespace] then
      registry[current_namespace] = {}
    end
  end,

  set_fallback = function(self, namespace)
    fallback_namespace = namespace
    if not registry[fallback_namespace] then
      registry[fallback_namespace] = {}
    end
  end,

  set = function(self, key, value)
    registry[current_namespace][key] = value
  end
}

local __meta = {
  __call = function(self, key, vars)
    if vars ~= nil and type(vars) ~= "table" then
      error(("expected parameter table to be a table, got '%s'"):format(type(vars)), 2)
    end
    vars = vars or {}
    vars.n = math.max((vars.n or 0), #vars)

    local str = registry[current_namespace][key] or registry[fallback_namespace][key]

    if str == nil then
      return nil
    end
    str = tostring(str)
    local strings = {}

    for i = 1, vars.n or #vars do
      table.insert(strings, tostring(vars[i]))
    end

    return #strings > 0 and str:format(unpack(strings)) or str
  end,

  __index = function(self, key)
    return registry[key]
  end
}

s:set_fallback('en')
s:set_namespace('en')

s._registry = registry

return setmetatable(s, __meta)
end
end

require "lua-string"
inspect = require "inspect"

local v = ("Hello world!"):trimend("!"):sub(6):trim():totable()
print(inspect(v))
