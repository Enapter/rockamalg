package analyzer

import (
	"errors"
	"fmt"
)

var errMissEnvUpvalue = errors.New("miss _ENV upvalue")

type resolver struct{}

func newResolver() *resolver {
	return &resolver{}
}

func (*resolver) ResolveListingRequires(listing listing) ([]string, error) {
	r := chunkResolver{make(map[string]struct{})}

	for _, chunk := range listing {
		err := r.ResolveChunkRequires(chunk)
		if err != nil {
			return nil, fmt.Errorf("resolve chunk requires: %w", err)
		}
	}

	return r.ResolvedRequires(), nil
}

type chunkResolver struct {
	resolved map[string]struct{}
}

func (c *chunkResolver) ResolveChunkRequires(ch chunk) error {
	requireID, ok := findKey(ch.constants, "require")
	if !ok {
		return nil
	}

	envID, ok := findKey(ch.upvalues, "_ENV")
	if !ok {
		return errMissEnvUpvalue
	}

	checkIsRequire := func(i instruction) bool {
		return i.b == envID && i.c == -requireID
	}

	checkHasRegisters := func(i instruction, requireReg, constantReg int) bool {
		return i.a == requireReg && i.b == 2 && i.a+1 == constantReg
	}

	cursor := newCursor(ch.instructions)
	for cursor.HasNext() {
		gettabup, ok := cursor.MoveForwardUntil(func(i instruction) bool {
			return i.opcode == "GETTABUP"
		})
		if !ok || !checkIsRequire(gettabup) {
			continue
		}

		loadk, ok := cursor.MoveForward()
		if !ok || loadk.opcode != "LOADK" {
			continue
		}

		call, ok := cursor.MoveForward()
		if !ok || call.opcode != "CALL" || !checkHasRegisters(call, gettabup.a, loadk.a) {
			continue
		}

		req, ok := ch.constants[-loadk.b]
		if !ok {
			continue
		}

		c.resolved[req] = struct{}{}
	}

	return nil
}

func (c *chunkResolver) ResolvedRequires() []string {
	s := make([]string, 0, len(c.resolved))
	for v := range c.resolved {
		s = append(s, v)
	}
	return s
}

type cursor struct {
	instructions []instruction
	pc           int
}

type cursorPredFunc func(i instruction) bool

func newCursor(instructions []instruction) *cursor {
	return &cursor{
		instructions: instructions,
		pc:           -1,
	}
}

func (c *cursor) HasNext() bool {
	return c.pc+1 < len(c.instructions)
}

func (c *cursor) MoveForward() (instruction, bool) {
	if !c.HasNext() {
		return instruction{}, false
	}
	c.pc++
	return c.instructions[c.pc], true
}

func (c *cursor) MoveForwardUntil(fn cursorPredFunc) (instruction, bool) {
	for c.HasNext() {
		next, _ := c.MoveForward()
		if fn(next) {
			return next, true
		}
	}
	return instruction{}, false
}

func findKey(values map[int]string, value string) (int, bool) {
	for i, v := range values {
		if v == value {
			return i, true
		}
	}
	return 0, false
}
