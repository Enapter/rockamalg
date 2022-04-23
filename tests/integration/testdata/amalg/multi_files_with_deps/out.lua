package.preload[ "goodbye" ] = assert( (loadstring or load)( "local goodbye = {}\
\
local sayer = require(\"yopta.sayer\")\
\
function goodbye.say(n)\
    sayer.say_each(n, \"goodbye\")\
end\
\
return goodbye\
", '@'.."./goodbye.lua" ) )

package.preload[ "hello" ] = assert( (loadstring or load)( "local hello = {}\
\
local sayer = require(\"yopta.sayer\")\
\
function hello.say(n)\
    sayer.say_each(n, \"hello\")\
end\
\
return hello\
", '@'.."./hello.lua" ) )

package.preload[ "inspect" ] = assert( (loadstring or load)( "local inspect ={\
  _VERSION = 'inspect.lua 3.1.0',\
  _URL     = 'http://github.com/kikito/inspect.lua',\
  _DESCRIPTION = 'human-readable representations of tables',\
  _LICENSE = [[\
    MIT LICENSE\
\
    Copyright (c) 2013 Enrique García Cota\
\
    Permission is hereby granted, free of charge, to any person obtaining a\
    copy of this software and associated documentation files (the\
    \"Software\"), to deal in the Software without restriction, including\
    without limitation the rights to use, copy, modify, merge, publish,\
    distribute, sublicense, and/or sell copies of the Software, and to\
    permit persons to whom the Software is furnished to do so, subject to\
    the following conditions:\
\
    The above copyright notice and this permission notice shall be included\
    in all copies or substantial portions of the Software.\
\
    THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS\
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF\
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.\
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY\
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,\
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE\
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\
  ]]\
}\
\
local tostring = tostring\
\
inspect.KEY       = setmetatable({}, {__tostring = function() return 'inspect.KEY' end})\
inspect.METATABLE = setmetatable({}, {__tostring = function() return 'inspect.METATABLE' end})\
\
local function rawpairs(t)\
  return next, t, nil\
end\
\
-- Apostrophizes the string if it has quotes, but not aphostrophes\
-- Otherwise, it returns a regular quoted string\
local function smartQuote(str)\
  if str:match('\"') and not str:match(\"'\") then\
    return \"'\" .. str .. \"'\"\
  end\
  return '\"' .. str:gsub('\"', '\\\\\"') .. '\"'\
end\
\
-- \\a => '\\\\a', \\0 => '\\\\0', 31 => '\\31'\
local shortControlCharEscapes = {\
  [\"\\a\"] = \"\\\\a\",  [\"\\b\"] = \"\\\\b\", [\"\\f\"] = \"\\\\f\", [\"\\n\"] = \"\\\\n\",\
  [\"\\r\"] = \"\\\\r\",  [\"\\t\"] = \"\\\\t\", [\"\\v\"] = \"\\\\v\"\
}\
local longControlCharEscapes = {} -- \\a => nil, \\0 => \\000, 31 => \\031\
for i=0, 31 do\
  local ch = string.char(i)\
  if not shortControlCharEscapes[ch] then\
    shortControlCharEscapes[ch] = \"\\\\\"..i\
    longControlCharEscapes[ch]  = string.format(\"\\\\%03d\", i)\
  end\
end\
\
local function escape(str)\
  return (str:gsub(\"\\\\\", \"\\\\\\\\\")\
             :gsub(\"(%c)%f[0-9]\", longControlCharEscapes)\
             :gsub(\"%c\", shortControlCharEscapes))\
end\
\
local function isIdentifier(str)\
  return type(str) == 'string' and str:match( \"^[_%a][_%a%d]*$\" )\
end\
\
local function isSequenceKey(k, sequenceLength)\
  return type(k) == 'number'\
     and 1 <= k\
     and k <= sequenceLength\
     and math.floor(k) == k\
end\
\
local defaultTypeOrders = {\
  ['number']   = 1, ['boolean']  = 2, ['string'] = 3, ['table'] = 4,\
  ['function'] = 5, ['userdata'] = 6, ['thread'] = 7\
}\
\
local function sortKeys(a, b)\
  local ta, tb = type(a), type(b)\
\
  -- strings and numbers are sorted numerically/alphabetically\
  if ta == tb and (ta == 'string' or ta == 'number') then return a < b end\
\
  local dta, dtb = defaultTypeOrders[ta], defaultTypeOrders[tb]\
  -- Two default types are compared according to the defaultTypeOrders table\
  if dta and dtb then return defaultTypeOrders[ta] < defaultTypeOrders[tb]\
  elseif dta     then return true  -- default types before custom ones\
  elseif dtb     then return false -- custom types after default ones\
  end\
\
  -- custom types are sorted out alphabetically\
  return ta < tb\
end\
\
-- For implementation reasons, the behavior of rawlen & # is \"undefined\" when\
-- tables aren't pure sequences. So we implement our own # operator.\
local function getSequenceLength(t)\
  local len = 1\
  local v = rawget(t,len)\
  while v ~= nil do\
    len = len + 1\
    v = rawget(t,len)\
  end\
  return len - 1\
end\
\
local function getNonSequentialKeys(t)\
  local keys, keysLength = {}, 0\
  local sequenceLength = getSequenceLength(t)\
  for k,_ in rawpairs(t) do\
    if not isSequenceKey(k, sequenceLength) then\
      keysLength = keysLength + 1\
      keys[keysLength] = k\
    end\
  end\
  table.sort(keys, sortKeys)\
  return keys, keysLength, sequenceLength\
end\
\
local function countTableAppearances(t, tableAppearances)\
  tableAppearances = tableAppearances or {}\
\
  if type(t) == 'table' then\
    if not tableAppearances[t] then\
      tableAppearances[t] = 1\
      for k,v in rawpairs(t) do\
        countTableAppearances(k, tableAppearances)\
        countTableAppearances(v, tableAppearances)\
      end\
      countTableAppearances(getmetatable(t), tableAppearances)\
    else\
      tableAppearances[t] = tableAppearances[t] + 1\
    end\
  end\
\
  return tableAppearances\
end\
\
local copySequence = function(s)\
  local copy, len = {}, #s\
  for i=1, len do copy[i] = s[i] end\
  return copy, len\
end\
\
local function makePath(path, ...)\
  local keys = {...}\
  local newPath, len = copySequence(path)\
  for i=1, #keys do\
    newPath[len + i] = keys[i]\
  end\
  return newPath\
end\
\
local function processRecursive(process, item, path, visited)\
  if item == nil then return nil end\
  if visited[item] then return visited[item] end\
\
  local processed = process(item, path)\
  if type(processed) == 'table' then\
    local processedCopy = {}\
    visited[item] = processedCopy\
    local processedKey\
\
    for k,v in rawpairs(processed) do\
      processedKey = processRecursive(process, k, makePath(path, k, inspect.KEY), visited)\
      if processedKey ~= nil then\
        processedCopy[processedKey] = processRecursive(process, v, makePath(path, processedKey), visited)\
      end\
    end\
\
    local mt  = processRecursive(process, getmetatable(processed), makePath(path, inspect.METATABLE), visited)\
    if type(mt) ~= 'table' then mt = nil end -- ignore not nil/table __metatable field\
    setmetatable(processedCopy, mt)\
    processed = processedCopy\
  end\
  return processed\
end\
\
\
\
-------------------------------------------------------------------\
\
local Inspector = {}\
local Inspector_mt = {__index = Inspector}\
\
function Inspector:puts(...)\
  local args   = {...}\
  local buffer = self.buffer\
  local len    = #buffer\
  for i=1, #args do\
    len = len + 1\
    buffer[len] = args[i]\
  end\
end\
\
function Inspector:down(f)\
  self.level = self.level + 1\
  f()\
  self.level = self.level - 1\
end\
\
function Inspector:tabify()\
  self:puts(self.newline, string.rep(self.indent, self.level))\
end\
\
function Inspector:alreadyVisited(v)\
  return self.ids[v] ~= nil\
end\
\
function Inspector:getId(v)\
  local id = self.ids[v]\
  if not id then\
    local tv = type(v)\
    id              = (self.maxIds[tv] or 0) + 1\
    self.maxIds[tv] = id\
    self.ids[v]     = id\
  end\
  return tostring(id)\
end\
\
function Inspector:putKey(k)\
  if isIdentifier(k) then return self:puts(k) end\
  self:puts(\"[\")\
  self:putValue(k)\
  self:puts(\"]\")\
end\
\
function Inspector:putTable(t)\
  if t == inspect.KEY or t == inspect.METATABLE then\
    self:puts(tostring(t))\
  elseif self:alreadyVisited(t) then\
    self:puts('<table ', self:getId(t), '>')\
  elseif self.level >= self.depth then\
    self:puts('{...}')\
  else\
    if self.tableAppearances[t] > 1 then self:puts('<', self:getId(t), '>') end\
\
    local nonSequentialKeys, nonSequentialKeysLength, sequenceLength = getNonSequentialKeys(t)\
    local mt                = getmetatable(t)\
\
    self:puts('{')\
    self:down(function()\
      local count = 0\
      for i=1, sequenceLength do\
        if count > 0 then self:puts(',') end\
        self:puts(' ')\
        self:putValue(t[i])\
        count = count + 1\
      end\
\
      for i=1, nonSequentialKeysLength do\
        local k = nonSequentialKeys[i]\
        if count > 0 then self:puts(',') end\
        self:tabify()\
        self:putKey(k)\
        self:puts(' = ')\
        self:putValue(t[k])\
        count = count + 1\
      end\
\
      if type(mt) == 'table' then\
        if count > 0 then self:puts(',') end\
        self:tabify()\
        self:puts('<metatable> = ')\
        self:putValue(mt)\
      end\
    end)\
\
    if nonSequentialKeysLength > 0 or type(mt) == 'table' then -- result is multi-lined. Justify closing }\
      self:tabify()\
    elseif sequenceLength > 0 then -- array tables have one extra space before closing }\
      self:puts(' ')\
    end\
\
    self:puts('}')\
  end\
end\
\
function Inspector:putValue(v)\
  local tv = type(v)\
\
  if tv == 'string' then\
    self:puts(smartQuote(escape(v)))\
  elseif tv == 'number' or tv == 'boolean' or tv == 'nil' or\
         tv == 'cdata' or tv == 'ctype' then\
    self:puts(tostring(v))\
  elseif tv == 'table' then\
    self:putTable(v)\
  else\
    self:puts('<', tv, ' ', self:getId(v), '>')\
  end\
end\
\
-------------------------------------------------------------------\
\
function inspect.inspect(root, options)\
  options       = options or {}\
\
  local depth   = options.depth   or math.huge\
  local newline = options.newline or '\\n'\
  local indent  = options.indent  or '  '\
  local process = options.process\
\
  if process then\
    root = processRecursive(process, root, {}, {})\
  end\
\
  local inspector = setmetatable({\
    depth            = depth,\
    level            = 0,\
    buffer           = {},\
    ids              = {},\
    maxIds           = {},\
    newline          = newline,\
    indent           = indent,\
    tableAppearances = countTableAppearances(root)\
  }, Inspector_mt)\
\
  inspector:putValue(root)\
\
  return table.concat(inspector.buffer)\
end\
\
setmetatable(inspect, { __call = function(_, ...) return inspect.inspect(...) end })\
\
return inspect\
\
", '@'.."/opt/rockamalg/.cache/share/lua/5.3/inspect.lua" ) )

package.preload[ "lua-string" ] = assert( (loadstring or load)( "local boolvalues = {\13\
\9[\"1\"] = \"0\";\13\
\9[\"true\"] = \"false\";\13\
\9[\"on\"] = \"off\";\13\
\9[\"yes\"] = \"no\";\13\
\9[\"y\"] = \"n\"\13\
}\13\
local eschars = {\13\
\9\"\\\"\", \"'\", \"\\\\\"\13\
}\13\
local escregexchars = {\13\
\9\"(\", \")\", \".\", \"%\", \"+\", \"-\", \"*\", \"?\", \"[\", \"]\", \"^\", \"$\"\13\
}\13\
local mt = getmetatable(\"\")\13\
\13\
local function includes(tbl, item)\13\
\9for k, v in pairs(tbl) do\13\
\9\9if v == item then\13\
\9\9\9return true\13\
\9\9end\13\
\9end\13\
\9return false\13\
end\13\
\13\
--- Overloads `*` operator. Works the same as `string.rep()` function.\13\
--- @param n number Multiplier.\13\
--- @return string rs String multiplied `n` times.\13\
function mt:__mul(n)\13\
\9if type(self) == \"number\" then\13\
\9\9return n * self\13\
\9end\13\
\9if type(n) ~= \"number\" then\13\
\9\9error(string.format(\"attempt to mul a '%1' with a 'string'\", type(n)))\13\
\9end\13\
\9return self:rep(n)\13\
end\13\
\13\
--- Overloads `[]` operator. It's possible to access individual chars with this operator. Index could be negative. In\13\
--- that case the counting will start from the end.\13\
--- @param i number Index at which retrieve a char.\13\
--- @return string ch Single character at specified index. Nil if the index is larger than length of the string.\13\
function mt:__index(i)\13\
\9if string[i] then\13\
\9\9return string[i]\13\
\9end\13\
\9i = i < 0 and #self + i + 1 or i\13\
\9local rs = self:sub(i, i)\13\
\9return #rs > 0 and rs or nil\13\
end\13\
\13\
--- Splits the string by supplied separator. If the `pattern` parameter is set to true then the separator is considered\13\
--- as a regular expression.\13\
--- @param sep string Separator by which separate the string.\13\
--- @param pattern? boolean `true` for separator to be considered as a pattern. `false` by default.\13\
--- @return string[] t Table of substrings separated by `sep` string.\13\
function string:split(sep, pattern)\13\
\9if sep == \"\" then\13\
\9\9return self:totable()\13\
\9end\13\
\9local rs = {}\13\
\9local previdx = 1\13\
\9while true do\13\
\9\9local startidx, endidx = self:find(sep, previdx, not pattern)\13\
\9\9if not startidx then\13\
\9\9\9table.insert(rs, self:sub(previdx))\13\
\9\9\9break\13\
\9\9end\13\
\9\9table.insert(rs, self:sub(previdx, startidx - 1))\13\
\9\9previdx = endidx + 1\13\
\9end\13\
\9return rs\13\
end\13\
\13\
--- Trims string's characters from its endings. Trims whitespaces by default. The `chars` argument is a regex string\13\
--- containing which characters to trim.\13\
--- @param chars? string Pattern that represents which characters to trim from the ends. Whitespaces by default.\13\
--- @return string s String with trimmed characters on both sides.\13\
function string:trim(chars)\13\
\9chars = chars or \"%s\"\13\
\9return self:trimstart(chars):trimend(chars)\13\
end\13\
\13\
--- Trims string's characters from its left side. Trims whitespaces by default. The `chars` argument is a regex string\13\
--- containing which characters to trim\13\
--- @param chars? string Pattern that represents which characters to trim from the start. Whitespaces by default.\13\
--- @return string s String with trimmed characters at the start.\13\
function string:trimstart(chars)\13\
\9return self:gsub(\"^[\"..(chars or \"%s\")..\"]+\", \"\")\13\
end\13\
\13\
--- Trims string's characters from its right side. Trims whitespaces by default. The `chars` argument is a regex string\13\
--- containing which characters to trim.\13\
--- @param chars? string Pattern that represents Which characters to trim from the end. Whitespaces by default.\13\
--- @return string s String with trimmed characters at the end.\13\
function string:trimend(chars)\13\
\9return self:gsub(\"[\"..(chars or \"%s\")..\"]+$\", \"\")\13\
end\13\
\13\
--- Pads the string at the start with specified string until specified length.\13\
--- @param len number To which length pad the string.\13\
--- @param str? string String to pad the string with. \" \" by default\13\
--- @return string s Padded string or the string itself if this parameter is less than string's length.\13\
function string:padstart(len, str)\13\
\9str = str or \" \"\13\
\9local selflen = self:len()\13\
\9return (str:rep(math.ceil((len - selflen) / str:len()))..self):sub(-(selflen < len and len or selflen))\13\
end\13\
\13\
--- Pads the string at the end with specified string until specified length.\13\
--- @param len number To which length pad the string.\13\
--- @param str? string String to pad the string with. \" \" by default\13\
--- @return string s Padded string or the string itself if this parameter is less than string's length.\13\
function string:padend(len, str)\13\
\9str = str or \" \"\13\
\9local selflen = self:len()\13\
\9return (self..str:rep(math.ceil((len - selflen) / str:len()))):sub(1, selflen < len and len or selflen)\13\
end\13\
\13\
--- If the string starts with specified prefix then returns string itself, otherwise pads the string until it starts\13\
--- with the prefix.\13\
--- @param prefix string String to ensure this string starts with.\13\
--- @return string s String that starts with specified prefix.\13\
function string:ensurestart(prefix)\13\
\9local prefixlen = prefix:len()\13\
\9if prefixlen > self:len() then\13\
\9\9return prefix:ensureend(self)\13\
\9end\13\
\9local left = self:sub(1, prefixlen)\13\
\9local i = 1\13\
\9while not prefix:endswith(left) and i <= prefixlen do\13\
\9\9i = i + 1\13\
\9\9left = left:sub(1, -2)\13\
\9end\13\
\9return prefix:sub(1, i - 1)..self\13\
end\13\
\13\
--- If the string ends with specified suffix then returns string itself, otherwise pads the string until it ends with\13\
--- the suffix.\13\
--- @param suffix string String to ensure this string ends with.\13\
--- @return string s String that ends with specified prefix.\13\
function string:ensureend(suffix)\13\
\9local suffixlen = suffix:len()\13\
\9if suffixlen > self:len() then\13\
\9\9return suffix:ensurestart(self)\13\
\9end\13\
\9local right = self:sub(-suffixlen)\13\
\9local i = suffixlen\13\
\9while not suffix:startswith(right) and i >= 1 do\13\
\9\9i = i - 1\13\
\9\9right = right:sub(2)\13\
\9end\13\
\9return self..suffix:sub(i + 1)\13\
end\13\
\13\
--- Adds backslashes before `\"`, `'` and `\\` characters.\13\
--- @param eschar? string Escape character. `\\` by default.\13\
--- @param eschartbl? string[] Characters to escape. `{\"\\\"\", \"'\", \"\\\\\"}` by default.\13\
--- @return string s String with escaped characters.\13\
function string:esc(eschar, eschartbl)\13\
\9local s = \"\"\13\
\9eschar = eschar or \"\\\\\"\13\
\9eschartbl = eschartbl or eschars\13\
\9for char in self:iter() do\13\
\9\9s = includes(eschartbl, char) and s..eschar..char or s..char\13\
\9end\13\
\9return s\13\
end\13\
\13\
--- Strips backslashes from the string.\13\
--- @param eschar? string Escape character. `\\` by default.\13\
--- @return string s Unescaped string with stripped escape character.\13\
function string:unesc(eschar)\13\
\9local s = \"\"\13\
\9local i = 0\13\
\9eschar = eschar or \"\\\\\"\13\
\9while i <= #self do\13\
\9\9local char = self:sub(i, i)\13\
\9\9if char == eschar then\13\
\9\9\9i = i + 1\13\
\9\9\9s = s..self:sub(i, i)\13\
\9\9else\13\
\9\9\9s = s..char\13\
\9\9end\13\
\9\9i = i + 1\13\
\9end\13\
\9return s\13\
end\13\
\13\
--- Escapes pattern special characters so the string can be used in pattern matching functions as is.\13\
--- @return string s String with escaped pattern special characters.\13\
function string:escpattern()\13\
\9return self:esc(\"%\", escregexchars)\13\
end\13\
\13\
--- Unescapes pattern special characters.\13\
--- @return string s Unescaped string with stripped pattern `%` escape character.\13\
function string:unescpattern()\13\
\9return self:unesc(\"%\")\13\
end\13\
\13\
--- Escapes pattern special characters so the string can be used in pattern matching functions as is.\13\
--- @return string s String with escaped pattern special characters.\13\
--- @deprecated\13\
function string:escregex()\13\
\9return self:esc(\"%\", escregexchars)\13\
end\13\
\13\
--- Unescapes pattern special characters.\13\
--- @return string s Unescaped string with stripped pattern `%` escape character.\13\
--- @deprecated\13\
function string:unescregex()\13\
\9return self:unesc(\"%\")\13\
end\13\
\13\
--- Returns an iterator which can be used in `for ... in` loops.\13\
--- @return fun(): string f Iterator.\13\
function string:iter()\13\
\9local i = 0\13\
\9return function ()\13\
\9\9i = i + 1\13\
\9\9return i <= self:len() and self:sub(i, i) or nil\13\
\9end\13\
end\13\
\13\
--- Truncates string to a specified length with optional suffix.\13\
--- @param len number Length to which truncate the string.\13\
--- @param suffix? string Optional string that will be added at the end.\13\
--- @return string s Truncated string.\13\
function string:truncate(len, suffix)\13\
\9if suffix then\13\
\9\9local newlen = len - suffix:len()\13\
\9\9return 0 < newlen and newlen < self:len() and self:sub(1, newlen)..suffix or self:sub(1, len)\13\
\9else\13\
\9\9return self:sub(1, len)\13\
\9end\13\
end\13\
\13\
--- Returns true if the string starts with specified string.\13\
--- @param prefix string String to test that this string starts with.\13\
--- @return boolean b `true` if the string starts with the specified prefix.\13\
function string:startswith(prefix)\13\
\9return self:sub(0, prefix:len()) == prefix\13\
end\13\
\13\
--- Returns true if the string ends with specified string.\13\
--- @param suffix string String to test that this string ends with.\13\
--- @return boolean b `true` if the string ends with the specified suffix.\13\
function string:endswith(suffix)\13\
\9return self:sub(self:len() - suffix:len() + 1) == suffix\13\
end\13\
\13\
--- Checks if the string is empty.\13\
--- @return boolean b `true` if the string's length is 0.\13\
function string:isempty()\13\
\9return self:len() == 0\13\
end\13\
\13\
--- Checks if the string consists of whitespace characters.\13\
--- @return boolean b `true` if the string consists of whitespaces or it's empty.\13\
function string:isblank()\13\
\9return self:match(\"^%s*$\") ~= nil\13\
end\13\
\13\
--- Converts \"1\", \"true\", \"on\", \"yes\", \"y\" and their contraries into real boolean. Case-insensetive.\13\
--- @return boolean | nil b Boolean corresponding to the string or nil if casting cannot be done.\13\
function string:tobool()\13\
\9local lowered = self:lower()\13\
\9for truthy, falsy in pairs(boolvalues) do\13\
\9\9if lowered == truthy then\13\
\9\9\9return true\13\
\9\9elseif lowered == falsy then\13\
\9\9\9return false\13\
\9\9end\13\
\9end\13\
\9return nil\13\
end\13\
\13\
--- Returns table containing all the chars in the string.\13\
--- @return string[] t Table that consists of the string's characters.\13\
function string:totable()\13\
\9local result = {}\13\
\9for ch in self:iter() do\13\
\9\9table.insert(result, ch)\13\
\9end\13\
\9return result\13\
end\13\
", '@'.."/opt/rockamalg/.cache/share/lua/5.3/lua-string/init.lua" ) )

package.preload[ "mymod" ] = assert( (loadstring or load)( "local mymodule = {}\
\
function mymodule.foo()\
    print(\"Hello World!\")\
end\
\
return mymodule\
", '@'.."./mymod.lua" ) )

package.preload[ "yopta.sayer" ] = assert( (loadstring or load)( "local sayer = {}\
\
function sayer.say_each(n, word)\
    for i = 1, n do\
        sayer.say(word)\
    end\
end\
\
function sayer.say(word)\
    print(word)\
end\
\
return sayer\
", '@'.."./yopta/sayer.lua" ) )

package.preload[ "yopta.utils" ] = assert( (loadstring or load)( "local utils = {}\
\
function utils.say_it()\
    print(\"Yopta!\")\
end\
\
return utils\
", '@'.."./yopta/utils.lua" ) )

assert( (loadstring or load)( "mymodule = require \"mymod\"\
mymodule.foo()\
\
local yopta_utils = require \"yopta.utils\"\
yopta_utils.say_it()\
\
require \"lua-string\"\
inspect = require \"inspect\"\
\
local v = (\"Hello world!\"):trimend(\"!\"):sub(6):trim():totable()\
print(inspect(v))\
\
local x = 10\
\
local r = \"\"\
\
if x < 10 then\
    r = require(\"hello\")\
else\
    r = require(\"goodbye\")\
end\
\
r.say(2)\
", '@'.."main.lua" ) )( ... )

