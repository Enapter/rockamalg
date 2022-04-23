local hello = {}

local sayer = require("yopta.sayer")

function hello.say(n)
    sayer.say_each(n, "hello")
end

return hello
