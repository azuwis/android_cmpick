#!/bin/bash

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
        if [ -e .git/refs/heads/* ]; then
            if [ ! -e .git/refs/remotes/azuwis ]; then
                git remote add azuwis git://github.com/${REPO_PROJECT/CyanogenMod/azuwis}
            fi
            for i in `ls -1 .git/refs/heads/ | grep -vE "^(build|auto)$"
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
