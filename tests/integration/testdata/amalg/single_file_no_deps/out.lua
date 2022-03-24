assert( (loadstring or load)( "print(\"single Lua file\")\
", '@'.."testdata/amalg/single_file_no_deps/single.lua" ) )( ... )

