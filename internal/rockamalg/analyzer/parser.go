package analyzer

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// listing is a listing of the compiled bytecode for Lua's virtual machine.
// A listing could contain several chunks.
// Each chunk consists of a header and several segments: instructions, constants, locals and upvalues.
// Lua compiler emits new chunk for main and each declared function.
//
// listing example:
//
//	main <(string):0,0> (2 instructions at 00000029D9FA72D0)
//	0+ params, 2 slots, 1 upvalue, 1 local, 0 constants, 1 function
//	1       [1]     CLOSURE         0 0     ; 00000029D9FA86D0
//	2       [1]     RETURN          0 1
//	constants (0) for 00000029D9FA72D0:
//	locals (1) for 00000029D9FA72D0:
//	0       a       2       3
//	upvalues (1) for 00000029D9FA72D0:
//	0       _ENV    1       0
//
//	function <(string):1,1> (2 instructions at 00000029D9FA86D0)
//	0+ params, 3 slots, 0 upvalues, 3 locals, 0 constants, 0 functions
//	1       [1]     VARARG          0 4
//	2       [1]     RETURN          0 1
//	constants (0) for 00000029D9FA86D0:
//	locals (3) for 00000029D9FA86D0:
//	0       a       2       3
//	1       b       2       3
//	2       c       2       3
//	upvalues (0) for 00000029D9FA86D0
type listing []chunk

type chunk struct {
	instructions []instruction
	constants    map[int]string
	upvalues     map[int]string
}

// Instruction represents Lua's virtual machine instruction.
// Opcode identifies the instruction, other fields represent operands.
type instruction struct {
	opcode string
	a      int
	b      int
	c      int
}

var (
	errMissHeaderLine     = errors.New("miss header line")
	errParseMetadata      = errors.New("parse metadata and instructions count header")
	errMissLocalsSegment  = errors.New("miss locals segment")
	errWrongSegmentLength = errors.New("wrong required segment length")
	errParseSegment       = errors.New("parse segment")
	errWrongTokensLength  = errors.New("wrong tokens length")
)

type parser struct{}

func newParser() *parser {
	return &parser{}
}

func (p *parser) ParseListing(buf *bytes.Buffer) (listing, error) {
	cp := chunksParser{
		Scanner: bufio.NewScanner(buf),
	}

	var chunks []chunk
	for cp.Scan() {
		ch, err := cp.ParseChunk()
		if err != nil {
			return nil, fmt.Errorf("parse chunk: %w", err)
		}
		chunks = append(chunks, ch)
	}

	return chunks, nil
}

type chunksParser struct {
	*bufio.Scanner
	metadata string
}

func (p *chunksParser) ParseChunk() (chunk, error) {
	h, err := p.parseHeader()
	if err != nil {
		return chunk{}, fmt.Errorf("parse header: %w", err)
	}

	p.metadata = h.metadata

	instructions, err := p.parseInstructionSegment(h.instructionCount)
	if err != nil {
		return chunk{}, p.buildError(fmt.Errorf("parse instruction segment: %w", err))
	}

	constants, err := p.parseSegment("constants")
	if err != nil {
		return chunk{}, p.buildError(fmt.Errorf("parse constants segment: %w", err))
	}

	localsLength, err := p.parseSegmentLength("locals")
	if err != nil {
		return chunk{}, p.buildError(fmt.Errorf("parse locals segment length: %w", err))
	}

	if ok := p.skipLines(localsLength); !ok {
		return chunk{}, p.buildError(errMissLocalsSegment)
	}

	upvalues, err := p.parseSegment("upvalues")
	if err != nil {
		return chunk{}, p.buildError(fmt.Errorf("parse upvalues segment: %w", err))
	}

	return chunk{
		instructions: instructions,
		constants:    constants,
		upvalues:     upvalues,
	}, nil
}

func (p *chunksParser) skipLine() bool {
	return p.skipLines(1)
}

func (p *chunksParser) skipLines(count int) bool {
	for i := 0; i < count; i++ {
		if !p.Scan() {
			return false
		}
	}
	return true
}

func (p *chunksParser) nextLine() (string, bool) {
	if !p.Scan() {
		return "", false
	}
	return p.Text(), true
}

func (p *chunksParser) buildError(err error) error {
	return fmt.Errorf("%s: %w", p.metadata, err)
}

var headerRegexp = regexp.MustCompile(`<(?P<meta>.*.lua:\d+,\d+)>[[:space:]]\((?P<count>\d+)`)

type header struct {
	metadata         string
	instructionCount int
}

// parseHeader parses header of a chunk.
//
// header example:
//
//	main <(string):0,0> (2 instructions at 00000029D9FA72D0)
//	0+ params, 2 slots, 1 upvalue, 1 local, 0 constants, 1 function
func (p *chunksParser) parseHeader() (header, error) {
	h, ok := p.nextLine()
	if !ok {
		return header{}, errMissHeaderLine
	}

	matches := headerRegexp.FindStringSubmatch(h)
	if matches == nil {
		return header{}, errParseMetadata
	}

	countStr := matches[headerRegexp.SubexpIndex("count")]
	metaStr := matches[headerRegexp.SubexpIndex("meta")]

	count, err := strconv.Atoi(countStr)
	if err != nil {
		return header{}, fmt.Errorf("map instructions count to int: %w", err)
	}

	if !p.skipLine() {
		return header{}, fmt.Errorf("%s: %w", metaStr, errMissHeaderLine)
	}

	return header{metaStr, count}, nil
}

// parseInstructionSegment parses instruction segment.
//
// instruction segment example:
//
//	1	[1]	CALL     	0 1 1
//	2	[1]	GETTABUP 	0 0 -1	; _ENV "require"
//	3	[2]	LOADK    	1 -6	; "yopta.utils"
//	4	[2]	CALL     	0 2 2
func (p *chunksParser) parseInstructionSegment(count int) ([]instruction, error) {
	instructions := make([]instruction, count)
	for i := range instructions {
		iline, ok := p.nextLine()
		if !ok {
			return nil,
				fmt.Errorf("%w: required - %d, found - %d", errWrongSegmentLength, count, i+1)
		}

		instruction, err := p.parseInstructionLine(iline)
		if err != nil {
			return nil, fmt.Errorf("parse instruction line: %w", err)
		}

		instructions[i] = instruction
	}

	return instructions, nil
}

// parseSegment parses single segment.
//
// constant example:
//
//	1	"require"
//	2	"mymod"
//	3	"mymodule"
//	4	"foo"
//	5	"yopta_utils"
//	6	"yopta.utils"
//	7	"say_it"
//
// upvalues example:
//
//	0	_ENV	1	0
func (p *chunksParser) parseSegment(name string) (map[int]string, error) {
	length, err := p.parseSegmentLength(name)
	if err != nil {
		return nil, fmt.Errorf("parse segment length: %w", err)
	}

	segValues := make(map[int]string, length)
	for i := 0; i < length; i++ {
		l, ok := p.nextLine()
		if !ok {
			return nil,
				fmt.Errorf("%w: required - %d, found - %d", errWrongSegmentLength, length, i+1)
		}

		idx, v, err := p.parseSegmentLine(l)
		if err != nil {
			return nil, fmt.Errorf("parse segment line %w", err)
		}

		segValues[idx] = v
	}

	return segValues, err
}

// parseSegmentLength parses segment length.
//
// segment header example:
//
//	constants (7) for 0x60000264c080:
func (p *chunksParser) parseSegmentLength(segName string) (int, error) {
	reg, err := regexp.Compile(segName + `[[:space:]]\((\d+)\)`)
	if err != nil {
		return 0, err
	}

	line, ok := p.nextLine()
	if !ok {
		return 0, fmt.Errorf("%w: miss segment %s length line", errParseSegment, segName)
	}

	matches := reg.FindStringSubmatch(line)
	if matches == nil {
		return 0, fmt.Errorf("%w: find %s length", errParseSegment, segName)
	}

	return strconv.Atoi(matches[1])
}

// parseInstructionLine parses single instruction line.
//
// instruction line examples:
//
//	14	[5]	RETURN   	0 1
//	1	[1]	CALL     	0 1 1
func (p *chunksParser) parseInstructionLine(str string) (instruction, error) {
	const (
		minTokens   = 4
		minOperands = 2
	)
	tokens := strings.Split(str, "\t")[1:]

	if len(tokens) < minTokens {
		return instruction{},
			fmt.Errorf("%w: instruction line, min tokens: %d, found: %d", errWrongTokensLength, minTokens, len(tokens))
	}

	opcode, operandsLine := tokens[2], tokens[3]
	a, b, c, err := p.parseOperandsLine(operandsLine)
	if err != nil {
		return instruction{}, fmt.Errorf("parse operands line: %w", err)
	}

	return instruction{
		opcode: strings.TrimSpace(opcode),
		a:      a,
		b:      b,
		c:      c,
	}, nil
}

// parseOperandsLine parses operands.
//
// operands line example:
//
//	0 1 1
func (p *chunksParser) parseOperandsLine(line string) (int, int, int, error) {
	const minOperands = 2
	fields := strings.Fields(line)

	if len(fields) < minOperands {
		return 0, 0, 0,
			fmt.Errorf("%w: instruction should have at least %d operands, found: %d",
				errWrongTokensLength, minOperands, len(fields),
			)
	}

	a, err := strconv.Atoi(fields[0])
	if err != nil {
		return 0, 0, 0, fmt.Errorf("convert operand a to int: %w", err)
	}

	b, err := strconv.Atoi(fields[1])
	if err != nil {
		return 0, 0, 0, fmt.Errorf("convert operand b to int: %w", err)
	}

	var c int
	if len(fields) > minOperands {
		c, err = strconv.Atoi(fields[2])
		if err != nil {
			return 0, 0, 0, fmt.Errorf("convert operand c to int: %w", err)
		}
	}

	return a, b, c, nil
}

// parse segment line parses single segment line.
//
// segment line examples:
//
//	1	"require"
//	0	_ENV	1	0
func (*chunksParser) parseSegmentLine(line string) (int, string, error) {
	const minTokens = 2
	tokens := strings.Split(line, "\t")[1:]

	if len(tokens) < minTokens {
		return 0, "",
			fmt.Errorf("%w: min segment line tokens: %d, found: %d", errWrongTokensLength, minTokens, len(tokens))
	}

	i, err := strconv.Atoi(tokens[0])
	return i, strings.ReplaceAll(tokens[1], "\"", ""), err
}
