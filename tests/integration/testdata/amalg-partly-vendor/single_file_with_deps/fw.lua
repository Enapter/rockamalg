require "lua-string"
inspect = require "inspect"

local v = ("Hello world!"):trimend("!"):sub(6):trim():totable()
print(inspect(v))
