package rockamalg

import "errors"

var (
	errRockspecDepsSimultaneously = errors.New("rockspec and deps are not allowed simultaneously")
	errLuaMissed                  = errors.New("lua is missed")
	errRockspecIsNotRegularFile   = errors.New("rockspec is not a regular file")
)
