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
