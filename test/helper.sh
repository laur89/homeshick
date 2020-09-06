#!/usr/bin/env bash

export_env_vars() {
  if [[ -n $BATS_TEST_DIRNAME ]]; then
    TESTDIR=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  else
    TESTDIR=$(cd "$SCRIPTDIR" && pwd)
  fi
  export TESTDIR
  _TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t homeshick)
  export _TMPDIR
  export REPO_FIXTURES="$_TMPDIR/repos"
  export HOME="$_TMPDIR/home"
  export NOTHOME="$_TMPDIR/nothome"

  export HOMESHICK_DIR
	HOMESHICK_DIR=$(cd "$TESTDIR/.." && pwd)

  # Check if expect is installed
  if type expect &>/dev/null; then
    export EXPECT_INSTALLED=true
  else
    export EXPECT_INSTALLED=false
  fi
}

remove_coreutils_from_path() {
  # Check if coreutils is in PATH
  system=$(uname -a)
  if [[ $system =~ "Darwin" && ! $system =~ "AppleTV" ]]; then
    if type brew &>/dev/null; then
      coreutils_path=$(brew --prefix coreutils 2>/dev/null)/libexec/gnubin
      if [[ -d $coreutils_path && $PATH == *$coreutils_path* ]]; then
        if [[ -z $HOMESHICK_KEEP_PATH || $HOMESHICK_KEEP_PATH == false ]]; then
          export PATH=${PATH//$coreutils_path/''}
          export PATH=${PATH//'::'/':'} # Remove any left over colons
        fi
      fi
    fi
  fi
}

mk_structure() {
  mkdir "$REPO_FIXTURES" "$HOME" "$NOTHOME"
}

ln_homeshick() {
  local hs_repo=$HOME/.homesick/repos/homeshick
  mkdir -p "$hs_repo"
  local repo_dir
  repo_dir=$(cd "$TESTDIR/.." && pwd)
  ln -s "$repo_dir/homeshick.sh" "$hs_repo/homeshick.sh"
  ln -s "$repo_dir/homeshick.csh" "$hs_repo/homeshick.csh"
  ln -s "$repo_dir/homeshick.fish" "$hs_repo/homeshick.fish"
  ln -s "$repo_dir/bin" "$hs_repo/bin"
  ln -s "$repo_dir/lib" "$hs_repo/lib"
  ln -s "$repo_dir/completions" "$hs_repo/completions"
}

rm_structure() {
  # Make sure _TMPDIR wasn't unset
  [[ -n $_TMPDIR ]] && rm -rf "$_TMPDIR"
}

setup_env() {
  remove_coreutils_from_path
  export_env_vars
  mk_structure
  # shellcheck source=../homeshick.sh
  source "$HOMESHICK_DIR/homeshick.sh"
}

setup() {
  setup_env
}

teardown() {
  rm_structure
}

fixture() {
  local name=$1
  if [[ ! -e "$REPO_FIXTURES/$name" ]]; then
    # shellcheck disable=SC1090
    source "$TESTDIR/fixtures/$name.sh"
  fi
}

castle() {
  local fixture_name=$1
  fixture "$fixture_name"
  homeshick --batch clone "$REPO_FIXTURES/$fixture_name" > /dev/null
}

is_symlink() {
  expected=$1
  path=$2
  target=$(readlink "$path")
  [ "$expected" = "$target" ]
}

get_inode_no() {
  stat -c %i "$1" 2>/dev/null || stat -f %i "$1"
}

# Snatched from http://stackoverflow.com/questions/4023830/bash-how-compare-two-strings-in-version-format
version_compare() {
  if [[ $1 == "$2" ]]; then
    return 0
  fi
  local IFS=.
  # shellcheck disable=SC2206
  local i ver1=($1) ver2=($2)
  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  for ((i=0; i<${#ver1[@]}; i++)); do
    if [[ -z ${ver2[i]} ]]; then
      # fill empty fields in ver2 with zeros
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      return 1
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      return 2
    fi
  done
  return 0
}

get_git_version() {
  if [[ -z $GIT_VERSION ]]; then
    read -r _ _ GIT_VERSION _ < <(command git --version)
    if [[ ! $GIT_VERSION =~ ([0-9]+)(\.[0-9]+){0,3} ]]; then
      skip 'could not detect git version'
    fi
  fi
  printf "%s" "$GIT_VERSION"
}

commit_repo_state() {
  local repo=$1
  (
    # Let cd just fail
    # shellcheck disable=SC2164
    cd "$repo"
    git config user.name "Homeshick user"
    git config user.email "homeshick@example.com"
    git add -A
    git commit -m "Commiting Repo State from test helper.sh."
  )
}