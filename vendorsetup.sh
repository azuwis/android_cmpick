#!/bin/bash
pathadd() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        PATH="${PATH:+"$PATH:"}$1"
    fi
}

pathadd $T/vendor/azuwis/bin

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
    if [ x"$T" == x ]; then
        echo "try run \`. build/envsetup.sh\` first"
        return
    fi
    mkdir -p "$T/out"
    if [ x"$1" == x"sync" ]; then
        touch $T/out/.timestamp
        repo sync -n -j16
    else
        repo forall -v -p -c bash -c '
        T=$1
        shift
        if [ .git/refs/remotes/github/cm-11.0 -nt "$T/out/.timestamp" ]; then
             #git log --no-merges --color github/cm-11.0@{1}..github/cm-11.0 "$@"
             git log --no-merges --format="%n/%n%H" --name-only github/cm-11.0@{1}..github/cm-11.0 -- | repolog_filter | git log --no-merges --stat --color=always --stdin --no-walk "$@"
        fi
        ' -- "$T" "$@"
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
        branches=`ls -1 .git/refs/heads/ | grep -vE "^(build|auto)$"`
        if [ $(echo $branches | wc -w) -gt 0 ]; then
            echo pushing...
            if ! git remote | grep -qFx azuwis; then
                git remote add azuwis git://github.com/${REPO_PROJECT/CyanogenMod/azuwis}
            fi
            for i in $branches
            do
                # test if push needed
                if [ -e .git/refs/remotes/azuwis/$i ]; then
                    if [ $(git --no-pager log --oneline azuwis/$i..$i -- | wc -l) -eq 0 ]; then
                        exit 0
                    fi
                fi
                git push --force azuwis $i
            done
        fi
        '
}

function repolist()
{
    repo forall "$@" -v -c bash -c '
        branches=`ls -1 .git/refs/heads/ | grep -vE "^(build|auto)$"`
        if [ $(echo $branches | wc -w) -gt 0 ]; then
            echo $REPO_PATH
        fi
        '
}

function repoclean()
{
    repo checkout cm-11.0
    repo abandon build
    repo abandon auto
}

function get_cm_picks()
{
    cat $(gettop)/vendor/azuwis/cherry-pick/$1 | while read url
    do
        if echo $url | grep -q '^#' || [ x"$url" == x ]; then
            continue
        fi
        echo $url | grep -o '[0-9]*'
    done | sort -n
}

function cmpick()
{
    branches=$(get_cm_picks "$1")
    echo "repopick -s $1" $branches
    case "$1" in
        auto)
            repopick -b $branches
            ;;
        *)
            repopick -s "$1" $branches
            ;;
    esac
}
