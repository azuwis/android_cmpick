#!/bin/bash

function echochanged()
{
    local func=$1
    shift

    $func $* | tee $OUT/.log

    # Install: <file>
    LOC=$(cat $OUT/.log | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' | grep 'Install' | cut -d ':' -f 2)

    # Copy: <file>
    LOC=$LOC $(cat $OUT/.log | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' | grep 'Copy' | cut -d ':' -f 2)

    for FILE in $LOC; do
        # Get target file name (i.e. system/bin/adb)
        TARGET=$(echo $FILE | sed "s#$OUT/##")

        # Don't send files that are not in /system.
        if ! echo $TARGET | egrep '^system\/' > /dev/null ; then
            continue
        elif echo $TARGET | egrep '^system\/(usr\/share\/vim|etc\/(nano|bash))\/' > /dev/null; then
            continue
        else
            echo "adb push $FILE $TARGET"
        fi
    done
    rm -f $OUT/.log
    return 0
}

function repolog() {
    T=$(gettop)
    if [ x"$1" == x"sync" ]; then
        repo sync -n -j16  2>&1 | tee $T/out/.synclog
    else
        cat $T/out/.synclog |  while read a b c
        do
            if [ x"$a" == x"From" ]; then
                project=`echo $b | sed 's/git:\/\/[^/]*\///'`
                dir=`repo list | awk -F': ' '{if ($2 == "'$project'") print $1}'`
            elif echo $b | grep -q '^cm-'; then
                change=$a
                pushd $dir >&/dev/null
                echo -e "\033[32mPROJECT: $dir BRANCH: $b"
                git log --stat --color=always $change "$@"
                popd >&/dev/null
                echo
            fi
        done | less -R
    fi
}

function repomerge()
{
    repo forall "$@" -v -p -c bash -c '
        branches=`ls -1 .git/refs/heads/ | grep -vE "^(build$|halo$|test)"`
        if [ $(echo $branches | wc -w) -lt 2 ]; then
            # less than 2 branch, nothing to do
            exit 0
        fi
        if [ -e .git/refs/heads/build ]; then
            git checkout build
            failed=0
            for i in $branches
            do
                if ! git merge --ff-only $i; then
                    failed=1
                    break
                fi
            done
            if [ $failed -eq 0 ]; then
                # all git merge --ff-only successed
                exit 0
            fi
            repo abandon build .
        fi
        repo start build .
        for i in $branches
        do
            git merge --no-edit --no-ff --rerere-autoupdate $i
            if [ -e .git/MERGE_MSG ]; then
                git commit --file=.git/MERGE_MSG
            fi
        done
        '
}

function repopush()
{
    repo forall "$@" -v -p -c bash -c '
        if [ x"$(ls -1 .git/refs/heads/)" != x ]; then
            if [ ! -e .git/refs/remotes/azuwis ]; then
                git remote add azuwis git://github.com/${REPO_PROJECT/CyanogenMod/azuwis}
            fi
            for i in `ls -1 .git/refs/heads/ | grep -vE "^(build|auto)$"`
            do
                git push --force azuwis $i
            done
        fi
        '
}

function get_cm_picks()
{
    cat $(gettop)/vendor/azuwis/cherry-pick/$1 | while read url
    do
        if echo $url | grep -q '^#' || [ x"$url" == x ]; then
            continue
        fi
        echo $url | grep -o '[0-9]*'
    done
}

function cmpick()
{
    branches=$(get_cm_picks "$1")
    case "$1" in
        auto)
            echo "repopick -b" $branches
            repopick -b $branches
            ;;
        *)
            echo "repopick -s $1" $branches
            repopick -s "$1" $branches
            ;;
    esac
}
