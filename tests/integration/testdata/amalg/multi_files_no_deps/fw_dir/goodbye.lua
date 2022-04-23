local goodbye = {}

local sayer = require("yopta.sayer")

function goodbye.say(n)
    sayer.say_each(n, "goodbye")
end

return goodbye
