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
