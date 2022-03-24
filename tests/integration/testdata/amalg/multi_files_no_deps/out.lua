package.preload[ "mymod" ] = assert( (loadstring or load)( "local mymodule = {}\
\
function mymodule.foo()\
    print(\"Hello World!\")\
end\
\
return mymodule\
", '@'.."./mymod.lua" ) )

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
", '@'.."main.lua" ) )( ... )

