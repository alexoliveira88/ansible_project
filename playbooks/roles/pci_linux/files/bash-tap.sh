#'history' options
declare -rx HISTFILE="$HOME/.bash_history"
#chattr +a "$HISTFILE" # set append-only
declare -rx HISTSIZE=500000 #nbr of cmds in memory
declare -rx HISTFILESIZE=500000 #nbr of cmds on file
declare -rx HISTCONTROL="" #does not ignore spaces or duplicates
declare -rx HISTIGNORE="" #does not ignore patterns
declare -rx HISTCMD #history line number
history -r #to reload history from file if a prior HISTSIZE has truncated it
if groups | grep -q root; then declare -x TMOUT=3600; fi #timeout for root's sessions

#enable forward search (ctrl-s)
#http://ruslanspivak.com/2010/11/25/bash-history-incremental-search-forward/
stty -ixon

#history substitution ask for a confirmation
shopt -s histverify

#add timestamps in history - obsoleted with logger/syslog
#http://www.thegeekstuff.com/2008/08/15-examples-to-master-linux-command-line-history/#more-130
#declare -rx HISTTIMEFORMAT='%F %T '

#bash audit & traceabilty
#
#
declare -rx AUDIT_LOGINUSER="$(who -mu | awk '{print $1}')"
declare -rx AUDIT_LOGINPID="$(who -mu | awk '{print $6}')"
declare -rx AUDIT_USER="$USER" #defined by pam during su/sudo
declare -rx AUDIT_PID="$$"
declare -rx AUDIT_TTY="$(who -mu | awk '{print $2}')"
declare -rx AUDIT_SSH="$([ -n "$SSH_CONNECTION" ] && echo "$SSH_CONNECTION" | awk '{print $1":"$2"->"$3":"$4}')"
declare -rx AUDIT_STR="[$AUDIT_LOGINUSER/$AUDIT_LOGINPID as $AUDIT_USER/$AUDIT_PID on $AUDIT_TTY/$AUDIT_SSH]"
declare -rx AUDIT_SYSLOG="1" #to use a local syslogd
#
#PROMPT_COMMAND solution is working but the syslog message are sent *after* the command execution, 
#this causes 'su' or 'sudo' commands to appear only after logouts, and 'cd' commands to display wrong working directory
#http://jablonskis.org/2011/howto-log-bash-history-to-syslog/
#declare -rx PROMPT_COMMAND='history -a >(tee -a ~/.bash_history | logger -p user.info -t "$AUDIT_STR $PWD")' #avoid subshells here or duplicate execution will occurs!
#
#another solution is to use 'trap' DEBUG, which is executed *before* the command.
#http://superuser.com/questions/175799/does-bash-have-a-hook-that-is-run-before-executing-a-command
#http://www.davidpashley.com/articles/xterm-titles-with-bash.html
#set -o functrace; trap 'echo -ne "===$BASH_COMMAND===${_backvoid}${_frontgrey}\n"' DEBUG
set +o functrace #disable trap DEBUG inherited in functions, command substitutions or subshells, normally the default setting already
#enable extended pattern matching operators
shopt -s extglob
#function audit_DEBUG() {
#  echo -ne "${_backnone}${_frontgrey}"
#  (history -a >(logger -p user.info -t "$AUDIT_STR $PWD" < <(tee -a ~/.bash_history))) && sync && history -c && history -r
#  #http://stackoverflow.com/questions/103944/real-time-history-export-amongst-bash-terminal-windows
#  #'history -c && history -r' force a refresh of the history because 'history -a' was called within a subshell and therefore
#  #the new history commands that are appent to file will keep their "new" status outside of the subshell, causing their logging
#  #to re-occur on every function call...
#  #note that without the subshell, piped bash commands would hang... (it seems that the trap + process substitution interfer with stdin redirection)
#  #and with the subshell
#}
##enable trap DEBUG inherited for all subsequent functions; required to audit commands beginning with the char '(' for a subshell
#set -o functrace #=> problem: completion in commands avoid logging them
function audit_DEBUG() {
    #simplier and quicker version! avoid 'sync' and 'history -r' that are time consuming!
    if [ "$BASH_COMMAND" != "$PROMPT_COMMAND" ] #avoid logging unexecuted commands after Ctrl-C or Empty+Enter
    then
        echo -ne "${_backnone}${_frontgrey}"
        local AUDIT_CMD="$(history 1)" #current history command
        #remove in last history cmd its line number (if any) and send to syslog
        if [ -n "$AUDIT_SYSLOG" ]
        then
            if ! logger -p user.info -t stap[$$] "$AUDIT_STR $PWD" "${AUDIT_CMD##*( )?(+([0-9])[^0-9])*( )}"
            then
                echo error "$AUDIT_STR $PWD" "${AUDIT_CMD##*( )?(+([0-9])[^0-9])*( )}"
            fi
        else
            echo $( date +%F_%H:%M:%S ) "$AUDIT_STR $PWD" "${AUDIT_CMD##*( )?(+([0-9])[^0-9])*( )}" >>/var/log/userlog.info
        fi
    fi
    #echo "===cmd:$BASH_COMMAND/subshell:$BASH_SUBSHELL/fc:$(fc -l -1)/history:$(history 1)/histline:${AUDIT_CMD%%+([^ 0-9])*}===" #for debugging
}
function audit_EXIT() {
    local AUDIT_STATUS="$?"
    if [ -n "$AUDIT_SYSLOG" ]
    then
        logger -p user.info -t stap[$$] "$AUDIT_STR" "#=== bash session ended. ==="
    else
        echo $( date +%F_%H:%M:%S ) "$AUDIT_STR" "#=== bash session ended. ===" >>/var/log/userlog.info
    fi
    exit "$AUDIT_STATUS"
}
#make audit trap functions readonly; disable trap DEBUG inherited (normally the default setting already)
declare -fr +t audit_DEBUG
declare -fr +t audit_EXIT
if [ -n "$AUDIT_SYSLOG" ]
then
    logger -p user.info -t stap[$$] "$AUDIT_STR" "#=== New bash session started. ===" #audit the session openning
else
    echo $( date +%F_%H:%M:%S ) "$AUDIT_STR" "#=== New bash session started. ===" >>/var/log/userlog.info
fi
#when a bash command is executed it launches first the audit_DEBUG(),
#then the trap DEBUG is disabled to avoid a useless rerun of audit_DEBUG() during the execution of pipes-commands;
#at the end, when the prompt is displayed, re-enable the trap DEBUG
declare -rx PROMPT_COMMAND="trap 'audit_DEBUG; trap DEBUG' DEBUG"
declare -rx BASH_COMMAND #current command executed by user or a trap
declare -rx SHELLOPT #shell options, like functrace  
trap audit_EXIT EXIT #audit the session closing

