#!/bin/bash

set -e -o pipefail

function __usage() {
    cat << EOF
Usage rockamalg [args...] <fw.lua|fw_dir>

Description:
    rockamalg amalgamates lua files with all dependencies inside one lua file.

Args:
    --rockspec|-r - use rockspec file name
    --deps|-d     - generate rockspec from dependencies (see below)
    --output|-o   - output firmware file name
    fw.lua        - firmware single lua file
    fw_dir        - firmware directory (should contain main.lua as entry point)

Examples:
    rockamalg -o out.lua -r el.rockspec fw
    rockamalg -o out.lua -d deps firmware.lua

Dependencies file
    The dependencies should be multiline file in rockspec format.
    Note, that Lua version should not be specified and commas and quotes are omitted.

    Example:
        lua-string ~> 1.2
        inspect ~> 3.1.2
        beemovie

EOF
}

function usage_with_error() {
    echo "Error: $1" >&2
    echo
    __usage
    exit 1

}

function rock_modules() {
    lua5.3 << EOF
f = loadfile("$1")
f()
for k,v in pairs(build["modules"]) do
    print(k)
end
EOF
}

function generate_rockspec() {
    local rockspec=$1
    local deps=$2

    {
        cat << EOF
rockspec_format = '3.0'
package = 'generated'
version = 'dev-1'
source = {
    url = 'generated'
}
dependencies = {
    'lua ~> 5.3',
EOF
        sed -e '/^$/d' -e "s/^/'/" -e "s/$/',/" "${deps}"
        echo "}"
    } > "$rockspec"
}

function main() {
    local rockspec=""
    local deps=""
    local output=""
    local firmware=""

    while (("$#")); do
        case "$1" in
            --rockspec|-r)
                rockspec="$2"
                shift
                ;;
            --deps|-d)
                deps="$2"
                shift
                ;;
            --output|-o)
                output="$2"
                shift
                ;;
            -*)
                echo "Error: Unsupported flag $1" >&2
                __usage
                exit 1
                ;;
            *)
                firmware="$1"
                ;;
        esac
        shift
    done

    [[ -n "${rockspec}" ]] && [[ -n "${deps}" ]] && usage_with_error "rockspec or deps are not allowed simultaneously"
    [[ -z "${output}" ]] && usage_with_error "output filename is required"
    [[ -z "${firmware}" ]] && usage_with_error "input firmware is required"

    output="/app/${output}"

    if [[ -n "${deps}" ]]; then
        echo -n "Generating rockspec... "
        rockspec=/tmp/generated-dev-1.rockspec
        generate_rockspec "$rockspec" "${deps}"
        echo "Done"
    fi

    if [[ -n "${rockspec}" ]]; then
        echo -n "Installing dependencies... "
        luarocks install --only-deps "$rockspec" > /dev/null
        echo "Done"
    fi

    echo -n "Calculating requires... "
    local modules=""
    for rock in $(luarocks list --porcelain | grep -v amalg | awk '{print $1}'); do
        m=$(rock_modules "$(luarocks show --rockspec "${rock}")")
        modules="${modules} $(echo "${m}" | tr '\n' ' ')"
    done
    echo "Done"

    if [[ -d "${firmware}" ]]; then
        cd "${firmware}"
        firmware="main.lua"
        modules="${modules} $(find . -name \*.lua | grep -v main.lua | sed -e 's/\.\///' -e 's/.lua//' -e 's/\//\./' -e 's/\(.*\)\.init/\1/')"
    fi

    echo -n "Amalgamation... "
    amalg.lua -d -o "${output}" -s "${firmware}" ${modules} > /dev/null
    echo "Done"
}

main "$@"
