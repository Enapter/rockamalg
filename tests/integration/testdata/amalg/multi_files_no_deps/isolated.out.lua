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

package.preload[ "yopta.unused" ] = assert( (loadstring or load)( "local mod = {}\
\
function mod.say_it()\
    print(\"Hmmm...\")\
end\
\
return mod\
", '@'.."./yopta/unused.lua" ) )

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
local x = 10\
\
local r = \"\"\
\
if x >= 10 then\
    r = require(\"hello\")\
else\
    r = require(\"goodbye\")\
end\
\
r.say(2)\
", '@'.."main.lua" ) )( ... )

