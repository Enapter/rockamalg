package server

import "errors"

var (
	errRockspecUnexpected             = errors.New("unexpected rockspec parsing result")
	errRockspecPackageOrVersionMissed = errors.New("package or version are missed")
)
