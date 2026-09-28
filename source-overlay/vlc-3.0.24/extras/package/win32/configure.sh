#!/bin/sh

OPTIONS="
      --enable-lua
      --enable-faad
      --enable-flac
      --enable-theora
      --enable-avcodec --enable-merge-ffmpeg
      --enable-mpc
      --enable-libass
      --enable-live555
      --enable-shout
      --enable-goom
      --enable-sse --enable-mmx
      --enable-libcddb
      --enable-zvbi --disable-telx
      --enable-nls"

fix_windows_libtool_paths() {
    [ -f libtool ] || return 0

    cxx=${CXX:-x86_64-w64-mingw32-g++}
    command -v "$cxx" >/dev/null 2>&1 || return 0

    script_dir=$(cd "$(dirname "$0")" && pwd)
    workspace_root=$(cd "$script_dir"/../../../../.. && pwd)
    workspace_alias=$(cygpath -m "$workspace_root" 2>/dev/null || printf '')

    case "$workspace_alias" in
        ''|*' '*)
            printf '%s\n' "warning: skipping libtool C++ path fixup; no space-free workspace alias is available" >&2
            return 0
            ;;
    esac

    dllcrt2=$("$cxx" -print-file-name=dllcrt2.o 2>/dev/null) || return 0
    crtbegin=$("$cxx" -print-file-name=crtbegin.o 2>/dev/null) || return 0
    crtend=$("$cxx" -print-file-name=crtend.o 2>/dev/null) || return 0

    workspace_prefix=${dllcrt2%%/tools/msys64/*}
    case "$dllcrt2" in
        "$workspace_prefix"/tools/msys64/*) ;;
        *)
            printf '%s\n' "warning: skipping libtool C++ path fixup; unexpected MinGW runtime layout: $dllcrt2" >&2
            return 0
            ;;
    esac

    aliasify_path() {
        case "$1" in
            "$workspace_prefix"/*)
                printf '%s%s\n' "${workspace_alias%/}" "${1#$workspace_prefix}"
                ;;
            *)
                printf '%s\n' "$1"
                ;;
        esac
    }

    dllcrt2=$(aliasify_path "$dllcrt2")
    crtbegin=$(aliasify_path "$crtbegin")
    crtend=$(aliasify_path "$crtend")

    raw_lib_dirs=$("$cxx" -print-search-dirs | sed -n 's/^libraries: =//p')
    old_ifs=$IFS
    IFS=';'
    compiler_lib_search_dirs=''
    for dir in $raw_lib_dirs; do
        [ -n "$dir" ] || continue
        dir=$(aliasify_path "$dir")
        case "$dir" in
            *' '*)
                continue
                ;;
        esac
        case " $compiler_lib_search_dirs " in
            *" $dir "*) ;;
            *)
                if [ -n "$compiler_lib_search_dirs" ]; then
                    compiler_lib_search_dirs="$compiler_lib_search_dirs $dir"
                else
                    compiler_lib_search_dirs="$dir"
                fi
                ;;
        esac
    done
    IFS=$old_ifs

    compiler_lib_search_path=''
    for dir in $compiler_lib_search_dirs; do
        if [ -n "$compiler_lib_search_path" ]; then
            compiler_lib_search_path="$compiler_lib_search_path -L$dir"
        else
            compiler_lib_search_path="-L$dir"
        fi
    done

    libtool_tmp=libtool.dualsubs.tmp
    awk \
        -v sys_path="$compiler_lib_search_dirs" \
        -v lib_dirs="$compiler_lib_search_dirs" \
        -v predeps="$dllcrt2 $crtbegin" \
        -v postdeps="$crtend" \
        -v lib_path="$compiler_lib_search_path" \
        '
        BEGIN { in_cxx = 0 }
        /^sys_lib_search_path_spec=/ {
            print "sys_lib_search_path_spec=\"" sys_path "\""
            next
        }
        /^# ### BEGIN LIBTOOL TAG CONFIG: CXX$/ {
            in_cxx = 1
            print
            next
        }
        /^# ### END LIBTOOL TAG CONFIG: CXX$/ {
            in_cxx = 0
            print
            next
        }
        in_cxx && /^compiler_lib_search_dirs=/ {
            print "compiler_lib_search_dirs=\"" lib_dirs "\""
            next
        }
        in_cxx && /^predep_objects=/ {
            print "predep_objects=\"" predeps "\""
            next
        }
        in_cxx && /^postdep_objects=/ {
            print "postdep_objects=\"" postdeps "\""
            next
        }
        in_cxx && /^compiler_lib_search_path=/ {
            print "compiler_lib_search_path=\"" lib_path "\""
            next
        }
        { print }
        ' libtool > "$libtool_tmp" && mv "$libtool_tmp" libtool
}

sh "$(dirname "$0")"/../../../configure ${OPTIONS} "$@"
status=$?

if [ "$status" -eq 0 ]; then
    fix_windows_libtool_paths
fi

exit "$status"
