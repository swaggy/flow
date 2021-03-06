#!/bin/bash -e
# Library of bash functions for flow internal usage.

out_file() {
    local pid=${1:-$pid}
    local test_out_dir=${TMPDIR:-/tmp/}
    echo "${test_out_dir}flow.commands.$pid"
}

title_file() {
    local pid=${1:-$pid}
    local test_out_dir=${TMPDIR:-/tmp/}
    echo "${test_out_dir}flow.commands.$pid.title"
}

failed_file() {
    local pid=${1:-$pid}
    local test_out_dir=${TMPDIR:-/tmp/}
    echo "${test_out_dir}flow.commands.$pid.failed"
}

success_title_line() {
    local pid=$1
    success_color_line "= $(cat $(title_file $pid)) ="
}

fail_title_line() {
    local pid=$1
    fail_color_line "= $(cat $(title_file $pid)) ="
}

success_color_line() {
    message="$1"
    echo -e "\033[92m${message}\033[0m"
}

fail_color_line() {
    message="$1"
    echo -e "\033[91m${message}\033[0m"
}

ongoing_progress_line() {
    if [[ $simple == true ]]; then return; fi
    local title=$1
    local phase=$2

    local char='?'
    case $phase in
        0) char="/"  ;;
        1) char="-"  ;;
        2) char="\\" ;;
        3) char="|"  ;;
        4) char="/"  ;;
        5) char="-"  ;;
        6) char="\\" ;;
        7) char="|"  ;;
    esac

    echo -e "$char $title"
}

success_progress_line() {
    if [[ $simple == true ]]; then return; fi
    local title=$1
    success_color_line "✔ $title"
}

fail_progress_line() {
    if [[ $simple == true ]]; then return; fi
    local title=$1
    fail_color_line "✘ $title"
}

move_up() {
    if [[ $simple == true ]]; then return; fi
    local lines=$1
    echo -e "\033[${lines}A"
}

hide_cursor() {
    if [[ $simple == true ]]; then return; fi
    echo -en '\033[?25l'
}

show_cursor() {
    if [[ $simple == true ]]; then return; fi
    echo -en '\033[?25h'
}

clear_line() {
    if [[ $simple == true ]]; then return; fi
    echo -en '\033[K'
}

is_running() {
    kill -s 0 $1 2>/dev/null
    return $?
}

async() {
    (
        pid=$(bash -c 'echo $PPID')
        out=$(out_file $pid)
        echo > $out
        if ! (export pid; eval $@ > $out 2>&1); then
            touch $(failed_file $pid)
        fi
    ) > /dev/null &
}

await() {
    local pid=$1
    if is_running $pid; then
        tail -f -n +1 $(out_file $pid) &  # Output in background.
        while is_running $pid; do
            sleep 0.2
        done
        kill -SIGQUIT $(jobs -p)  # Kill output log file job
    else
        cat $(out_file $pid)
    fi
    if [[ -e $(failed_file $pid) ]]; then
        exit 1
    else
        exit 0
    fi
}

group() {
    # Test args: each title has a matching command.
    if [[ $(($#%2)) != 0 ]]; then
        echo "Args to group must be even (pairs of title and command)."
        exit 1
    fi

    # Parse args and start commands.
    local command_pids=""
    local title=""
    local command=""
    for var in "$@"; do
        if [[ $title == "" ]]; then
            title="$var"
        elif [[ $command == "" ]]; then
            command="$var"

            async "$command"
            local pid=$!

            command_pids+=" $pid"
            echo $title > $(title_file $pid)

            title=""
            command=""
        fi
    done

    # Cleanup on exit.
    trap_cmd="for pid in $command_pids;"
    trap_cmd+='do cleanup $pid; done;'
    trap_cmd+='show_cursor'
    trap "$trap_cmd" EXIT

    if [[ $simple == true ]]; then
        echo "Running commands:"
        for pid in $command_pids; do
            echo "  $(cat $(title_file $pid))"
        done
    fi
    local success_pids=""
    local failed_pids=""
    local progress_phase=0  # For the progress indicator.
    while :; do
        local lines_printed=1  # Keep track of how many lines we output to backtrack, plus one for the newline.
        local all_done=true
        for pid in $command_pids; do
            clear_line
            lines_printed=$((lines_printed + 1))

            # Load the title from the file.
            local title=$(cat $(title_file $pid))

            if is_running $pid; then
                # Still running.
                ongoing_progress_line "$title" $progress_phase
                all_done=false
            else
                # Note: pids in the lists are space padded to prevent matching collions, e.g. 1 and 11.
                if [[ $success_pids == *" $pid "* ]]; then
                    success_progress_line "$title"
                    continue
                fi

                if [[ $failed_pids == *" $pid "* ]]; then
                    fail_progress_line "$title"
                    continue
                fi

                if [[ -e $(failed_file $pid) ]]; then
                    fail_progress_line "$title"
                    failed_pids+=" $pid "
                else
                    success_progress_line "$title"
                    success_pids+=" $pid "
                fi
            fi
        done

        if $all_done; then
            break;
        fi

        sleep 0.2

        # Move up that many lines.
        move_up $lines_printed

        # Increment the progress phase. It goes up to 7 and wraps around.
        progress_phase=$((progress_phase + 1))
        if [[ $progress_phase == 8 ]]; then
            progress_phase=0
        fi
    done

    local code=0  # Code to return with.

    # Print out the results, all successes then all failures.
    # The lists of pids are first sorted so that they're in ascending order,
    # which should be the order of their invocation.
    if [[ $success_pids != "" ]]; then
        echo
        success_color_line "Successes"
        echo -e "=========\n"
        success_pids=$(echo $success_pids | tr " " "\n" | sort -g | tr "\n" " ")
        for pid in $success_pids; do
            success_title_line $pid
            cat $(out_file $pid)
            echo
        done
    fi

    if [[ $failed_pids != "" ]]; then
        echo
        fail_color_line "Failures"
        echo -e "========\n"
        failed_pids=$(echo $failed_pids | tr " " "\n" | sort -g | tr "\n" " ")
        for pid in $failed_pids; do
            fail_title_line $pid
            cat $(out_file $pid)
            echo
        done

        code=1
    fi

    return $code
}

cleanup() {
    local pid=$1
    rm -f $(out_file $pid) $(title_file $pid) $(failed_file $pid)
}
