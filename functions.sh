#!/bin/bash
#
# Define bash functions here
#
# Loaded after environment.sh and aliases.sh
#

#
# Shell Functions
#

# Takes two (generally sibling) commands to execute based on whether or not
# stdin is being written to. $1 is executed if input is being piped in,
# $2 is executed otherwise.
#
# Generally speaking it's simpler and cleaner to just write a function that
# checks [[ -t 0 ]] (like this function), however this function enables
# defining concise aliases that react to stdin being piped. See the
# clipboard examples in aliases.sh - those three lines would take up almost
# 20 if defined in their own (near-identical) functions.
if_stdin() {
  has_stdin="${1:?Must specify a command for stdin}"
  shift
  no_stdin="${1:?Must specify a command for no stdin}"
  shift
  # Need to use eval to support things like > redirection
  # Which in turn means we need to escape any remaining args
  local args
  if (( $# )); then
    args=$(printf '%q ' "$@")
  fi
  if ! [[ -t 0 ]]; then
    eval "$has_stdin $args"
  else
    eval "$no_stdin $args"
  fi
}

# Buffers all output of the passed command, and only prints on error
# Uses eval to support pipes and multiple commands, but defining a
# wrapper function is generally recommended.
# http://unix.stackexchange.com/a/41388/19157
# TODO try http://joeyh.name/code/moreutils/ on Cygwin and just wrap chronic
# if it's on the PATH.
quiet_success() {
  local output
  output=$( eval "$@" 2>&1 )
  local ret=$?
  if (( ret != 0 )); then
    echo "$output"
    return $ret
  fi
}

# Prints the currently open screen sesions
command -v screen > /dev/null && screens() {
  screen -ls |
    grep '^'$'\t' |
    awk '{ print $1 }' |
    sed 's/[0-9]*\.//' |
    sort
}

# Opens a screen session with the given name, either creating a new session or
# attaching to one that already exists. Also enables logging for the session.
command -v screen > /dev/null && screenopen() {
  local logfile="/tmp/screen.${1:?Must specify a screen session name.}.log"
  # http://serverfault.com/a/248387
  local screenrc
  screenrc=$(mktemp)
  cat <<EOF >$screenrc
logfile $logfile
source $HOME/.screenrc
EOF
  screen -d -R "$1" -L -c "$screenrc"
  rm "$screenrc"
  echo "Logfile at $logfile"
}

# Grep ps command
# Inspiration: http://www.commandlinefu.com/commands/view/977/
# Alternately: http://code.google.com/p/psgrep/
# TODO how is this better than pgrep?
# https://github.com/koalaman/shellcheck/wiki/SC2009
psgrep() {
  if [[ -z "$2" ]]
  then
    local psargs="aux"
    local greparg="$1"
  else
    local psargs="$1"
    local greparg="$2"
  fi
  # shellcheck disable=SC2001
  greparg=$(echo "$greparg" | sed 's|\(.\)$|[\1]|')
  # shellcheck disable=SC2086
  ps $psargs | head -n 1
  # shellcheck disable=SC2009,SC2086
  ps $psargs | grep -i "$greparg"
}

# Send an email when the process passed as an argument terminates
emailme() {
  if [[ -z "$1" ]]
  then
    echo "Usage: emailme cmd cmdargs..."
    echo "Usage: EMAIL=user@example.com emailme cmd cmdargs..."
    return 0
  fi

  if [[ -z "$EMAIL" ]]
  then
    echo 'No EMAIL value found' >&2
    # shellcheck disable=SC2119
    emailme >&2 # usage
    return 1
  fi

  local cmd=$1
  shift
  time $cmd "$@"

  printf "From: %s\nTo: %s\nSubject: Finished running %s\n\nRan: %s\n\nStatus: %s\n" \
    "$EMAIL" "$EMAIL" "$cmd" "${cmd} $*" "$?" \
    | sendmail -t
  pgem_log "Emailed $EMAIL"
}

# Extracts archives of different types
# http://www.shell-fu.org/lister.php?id=375
extract() {
  if [[ -f "$1" ]] ; then
    case "$1" in
      *.tar.bz2)   tar xvjf "$1"    ;;
      *.tar.gz)    tar xvzf "$1"    ;;
      *.bz2)       bunzip2 "$1"     ;;
      *.rar)       unrar x "$1"     ;;
      *.gz)        gunzip "$1"      ;;
      *.tar)       tar xvf "$1"     ;;
      *.tbz2)      tar xvjf "$1"    ;;
      *.tgz)       tar xvzf "$1"    ;;
      *.zip|*.jar) unzip "$1"       ;;
      *.Z)         uncompress "$1"  ;;
      *.7z)        7z x "$1"        ;;
      *)
        echo "'$1' cannot be extracted via extract"
        return 2
        ;;
    esac
  else
    echo "'$1' is not a valid file"
    return 1
  fi
}

# Waits for processes that aren't a child process of this shell
# Pair with:
#   long_running_command & wait # this prints the PID of long_running_command
# to wait for a process in another shell to finish
wait_ext() {
  # Warn if the first PID is not found before we start waiting, since that
  # could mean the provided PID is incorrect
  [[ -e "/proc/$1" ]] || echo "Warning, no PID $1 found."
  while (( "$#" )); do
    while [[ -e "/proc/$1" ]]; do sleep 1; done
    shift
  done
}

# Returns a non-zero exit code if the provided port is not in use
# http://unix.stackexchange.com/q/5277
listening() {
  nc -q 0 localhost "$1" < /dev/null
}

# Busy-waits until the specified ports are accepting requests
wait_port() {
  while (( "$#" )); do
    while ! listening "$1"; do sleep 1; done
    shift
  done
}

# Launches a Bash shell without any .rc customizations
# Useful for testing behavior that might be impacted by your environment.
# https://stackoverflow.com/a/41554230/113632
pristine_bash() {
  env -i bash --noprofile --norc
}

#
# Git Functions
#

# Syncs a fork with the upstream repo
# https://help.github.com/articles/syncing-a-fork/
gitsyncfork() {
  git fetch upstream &&
  git checkout master &&
  git merge upstream/master &&
  echo "Ready to push with 'git push'"
}

# Rebase all commits not found in the upstream master (i.e. in a PR)
# generally in order to squash them all into one commit.
# https://stackoverflow.com/a/15055649/113632
gitsquash() {
  git rebase -i upstream/master
  echo "Push rebased changes with 'git push -f'"
}

#
# Dev Functions
#

# Creates a Java pseudo-REPL for quick prototyping.
# Launches an editor with a new Java file, then compiles and runs the file
# after the editor exits.
# Re-running in the same shell session opens the same file.
java_demo() {
  local dir="${TMP:-/tmp}"
  local class="Demo$$"
  local path="$dir/$class.java"
  if ! [[ -f "$path" ]] ; then
    cat << EOF > $path
import java.util.*;

public class $class {
  public static void main(String[] args) {
    
  }
}
EOF
  fi
  # cd to /tmp to support Cygwin - Java doesn't like absolute Cygwin paths
  (cd "$dir" &&
   vi $class.java &&
   echo "javac $path" >&2 && javac "$class.java" &&
   echo "java -cp $dir $class" >&2   && java -cp . "$class"
  )
}
