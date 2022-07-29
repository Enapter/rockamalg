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
package.preload[ "yopta.unused" ] = function( ... ) local arg = _G.arg;
local mod = {}

function mod.say_it()
    print("Hmmm...")
end

return mod
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

local x = 10

local r = ""

if x >= 10 then
    r = require("hello")
else
    r = require("goodbye")
end

r.say(2)
