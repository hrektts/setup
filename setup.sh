#!/bin/sh

# # Coding conventions
#
# * globals are `like_this`.
# * locals are `_like_this`.
# * exported values are `LIKE_THIS`.
# * out-of-band return values are put into `RETVAL`.
#
# `set -u` is on, which means undefined variables are errors.
# Generally when evaluating a variable that may not exist I'll
# write `${mystery_variable-}`, which results in "" if the name
# is undefined.
#
# Every command should be expected to return 0 on success, and
# non-zero on failure. Additional return values may be passed
# the `$RETVAL` global or further `RETVAL_FOO` globals as needed.

set -eu

main() {
    manage_prerequisites
    retrieve_pkg_list
    provision_pkg ansible
    if test "darwin" != "$(get_os)" ; then
        provision_pkg git
    fi
    cleanup_pkg

    local _branch=${@:-"master"}

    if ${CI}; then
        HOMEBREW_CASK_OPTS="--appdir=/Applications" ansible-pull \
                          -U https://github.com/hrektts/setup.git \
                          -C $_branch \
                          -i hosts \
                          --vault-password-file vault.sh \
                          -vvv \
                          localhost.yml
    else
        HOMEBREW_CASK_OPTS="--appdir=/Applications" ansible-pull \
                          -U https://github.com/hrektts/setup.git \
                          -C $_branch \
                          -i hosts \
                          --ask-become-pass \
                          -vvv \
                          localhost.yml
    fi

    say "Finished. Hosts are ready!"
}

download_from() {
    if [ -z "$1" ]; then
        err "Bad nuber of arguments for function"
    fi

    local _filename=""
    [ 1 -lt $# ] && _filename="$2" || _filename="$(basename $1)"

    if type curl > /dev/null 2>&1; then
        curl -f -o $_filename "$1"
    elif type wget > /dev/null 2>&1; then
        wget -O $_filename "$1"
    else
        err "cURL not found"
    fi
}

manage_prerequisites() {
    case "$(get_os)" in
        darwin )
            # Command line tools
            if ! type xcode-select > /dev/null 2>&1; then
                xcode-select --install
            fi

            # Homebrew
            if ! type brew > /dev/null 2>&1; then
                /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
            fi
            my_brew update
            my_brew doctor
            my_brew cask update
            my_brew cask doctor
            ;;
        debian | ubuntu )
            # Add PPA for Ansible
            maybe_sudo apt-get update
            maybe_sudo apt-get -y install software-properties-common
            maybe_sudo apt-add-repository -y ppa:ansible/ansible
            ;;
        * )
            ;;
    esac
}

retrieve_pkg_list() {
    case "$(get_os)" in
        darwin )
            my_brew update
            my_brew cask update
            ;;
        debian | ubuntu )
            maybe_sudo apt-get update
            ;;
        * )
            ;;
    esac
}

provision_pkg() {
    if [ -z "$1" ]; then
        err "Bad nuber of arguments for function"
    fi

    case "$(get_os)" in
        darwin )
            my_brew missing "$@"
            my_brew install "$@"
            ;;
        debian | ubuntu )
            if [ -n "$(dpkg -l | grep " $1 ")" ]; then
                maybe_sudo apt-get -y upgrade "$@"
            else
                maybe_sudo apt-get -y install "$@"
            fi
            ;;
        * )
            exit 1
    esac

    return 0
}

cleanup_pkg() {
    case "$(get_os)" in
        darwin )
            my_brew cleanup
            ;;
        debian | ubuntu )
            maybe_sudo apt-get --purge -y autoremove
            ;;
        * )
            ;;
    esac
}

get_os() {
    local _os="unknown"
    if type uname > /dev/null 2>&1; then
        case "$(uname)" in
            Darwin )
                _os="darwin"
                ;;
            Linux )
                if [ -e /etc/debian_version ]; then
                    _os=$(get_debian_kind)
                else
                    _os="unknown"
                fi
                ;;
            * )
                _os="unknown"
                ;;
        esac
    fi

    echo $_os
}

get_debian_kind() {
    local _kind="unknown"
    if [ -e /etc/lsb-release ] &&
       [ -n "$(cat /etc/lsb-release | grep Ubuntu)" ]; then
        _kind="ubuntu"
    else
        _kind="debian"
    fi
    echo $_kind
}

maybe_sudo() {
    if test "root" != "$(whoami)" ; then
        if [ -n "${http_proxy-}" ] || [ -n "${HTTP_PROXY-}" ]; then
            sudo -E "$@"
        else
            sudo "$@"
        fi
    else
        $@
    fi
}

my_brew() {
    HOMEBREW_CASK_OPTS="--appdir=/Applications" brew "$@"
}

# Standard utilities

say() {
    echo "$0: $1"
}

say_err() {
    say "$1" >&2
}

err() {
    say "$1" >&2
    exit 1
}

main $@
