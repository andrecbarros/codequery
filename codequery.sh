#!/bin/sh
#@0.2.2 2014.05.07 22:57:00 GMT-3
#
# Bash script used to generate (and backup) the database used by codequery.
#
# Author: Andre C. Barros <andre.cbarros@yahoo.com>
# License: MIT or BSD or GPL2+

trap 'rval=$? ; IFS=${_IFS} ; [ $rval != 0 ] && echo "Error: $rval"' EXIT
_IFS=$IFS

NL='
'
BELL=$( echo -en '\a' )

usage () {
  echo -e "codequery.sh [option] [path [.. ]]\n" \
          "  -p <name> (project)        Project name;\n" \
          "  -c <class[.[iI]][,..]>     ctags <class> E { C, C++, C#, Go, Fortran, .. };\n" \
          "  -t <type[.[iI]][,..]>      Where <type> E { C, c, cpp, java, py, go, rb,\n" \
          "                             php, js, cs, perl, f };\n" \
          "  -d [#[=+-],..] (depth)     Set depth search (= min max, + min, - max);\n" \
          "  -i                         Set case insensitive source name match;\n" \
          "  -I                         Set case sensitive source name match (default);\n" \
          "  -n <[[iI].]def:pattern>|   \`find -[i]name 'pattern'\`. If ! is present\n" \
          "     <[[!][iI].]:pattern>    <pattern> is used for exclusion on all searches;\n" \
          "  -r <[[iI].]def:pattern>|   \`file -[i]regex 'pattern'\`. See '-n'. <def> is a\n" \
          "     <[[!][iI].]:pattern>    type/class definition to be reused (saves <pattern>);\n" \
          "  -o <find opts> (options)   Extra 'find' options (affect all searches);\n" \
          "  -a <pattern> (avoid)       Avoid internal files of revision control system,\n" \
          "                             '-' disables default pattern, '+' enables it;\n" \
          "  -b <ext> (backup)          Backup database appending '.<est>' to existing one,\n" \
          "                             '-' disables, '+' enables default (2 rotating backups);\n" \
          "  -k (keep)                  Keep the list of processed files (default is delete);\n" \
          "  -A (absolue)               Absolute paths (default is relative);\n" \
          "  -R (dry-run)               Do not touch the database (semi fake run);\n" \
          "  -D (debug)                 Print out the control structures;\n" \
          "  -E (edebug)                Print out the extra type/class/defs control structures;\n" \
          "  -S[+-] [name] (save)       Save options to <name> (default: ~/.codequery.sh.opts).\n" \
          "                             S: save only app paths; S-: save -d[nr]oaA; S+: S + S-.\n" \
          "  -L[+-] [name] (load)       Load default options (see -S);\n" \
          "  --ctags=<path>             Where to find ctags;\n" \
          "  --cscope=<path>            Where to find cscope;\n" \
          "  --pycscope=<path>          Where to find pycscope;\n" \
          "  --starscope=<path>         Where to find starscope;\n" \
          "  --cqmakedb=<path>          Where to find cqmakedb;\n" \
          "  -v (verbose)               Display what is happenning;\n" \
          "  -h (help)                  Display this help and exit.\n\n" \
          "Default values are assigned from current directory name for <project> and 'c'\n" \
          "for <type> if they were not set. At least one command line argument must be provided."
}

# ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
vars_init () {
  rval=            # return value
  prj=             # project name
  tag=             # source type tag
  tags=            # pre defined source types to be tagged
  etags=           # extra source types to be tagged
  etagsid=0        # for "anonymous" source types to be tagged
  mf=cscope.files  # matched source files list
  ct=cscope.out    # cscope output file
  tt=tags.out      # ctags output file (used also as temporary file)
  cm=              # case match sense (sensitive or insensitive)
  min=             # mindepth
  max=             # maxdepth
  bkp=+            # backup of the old database; default is to have a rotating 2 backups

  rm_fl=1          # remove the list of all processed files?
  dryrun=          # dry-run morph command
  verbose=         # verbose: show the command to be executed
  findopts=        # 'find' extra options (affects all searches)
  findavoid=       # file types to be excluded from all searches
  
  save_to=         # Where things will be saved
  save_opt=
  load_from=       # From where load saved things
  load_opt=
  
  # processed files list
  fl=codequery.files
  all="$fl.all"
  
  # Avoid reading on revision control system structure
  davoid='\(.*/\|\)\(\.\(git\|svn\|hg\|bzr\|cvs\)\|CVS\)/.*'
  avoid=$davoid
  
  # arguments provided and project file types scanned
  opts=
  pfts=
  
  # Source files regex pattern
  rx_C=".*\.\([ch]\)\(\|\1\|pp\?\|xx\|++\)"
  rx_c=".*\.[ch]"
  rx_cpp=".*\.\([ch]\)\(\1\|pp\?\|xx\|++\)"
  rx_cs=".*\.c\(s\|sharp\|#\)"
  rx_f=".*\.f\(\|or\|pp\|tn\|66\|77\|90\|95\|03\|08\|15\)"
  rx_go=".*\.go"
  rx_java=".*\.java"
  rx_php=".*\.php"
  rx_pl=".*\.p\([lm]\|erl\|lx\)"
  rx_py=".*\.py\(\|[xdi]\)"
  rx_rb=".*\.rb"
  rx_js=".*\.js"
  
  # what tools are available on system
  #_ctags=
  #_cscope=
  #_pycscope=
  #_starscope=
  #_cqmakedb=
  
  # Default file types
  re_types="C:$rx_C
c:$rx_c
cpp:$rx_cpp
ct:$rx_cs
f:$rx_f
go:$rx_go
java:$rx_java
php:$rx_php
pl:$rx_pl
py:$rx_py
rb:$rx_rb
js:$rx_js"

  re_ctags=    # ctags file types
  re_etags=    # extra file types
  
  val=
  arg=
  aux=
  cwd=$( pwd )     # current dir
  pdir=            # project dir
  bdir=            # find base dir
}

# ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
clean_up () {
  # Remove temporary files
  #
  local f
  
  for f in "$pdir/$mf" "$pdir/$fl" "$pdir/$ct"{,.tmp} "$pdir/$tt" $@; do [ -f "$f" ] && rm -f "$f"; done
}

# ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
scope_match () {
  # Process known file types with cscope like tools
  #
  if [ -s "$pdir/$mf" ]; then

    echo -ne "" > "$pdir/$ct.tmp"

    case "$1" in
      C|C++|c|cpp)
        eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_cscope:+${_cscope} -cb -i '$pdir/$mf' -f '$pdir/$ct.tmp' ;} ${verbose:+set +x}"
        ;;
      Java|js)
        eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_cscope:+${_cscope} -cbR -i '$pdir/$mf' -f '$pdir/$ct.tmp' ;} ${verbose:+set +x}"
        ;;
      Python|py)
        eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_pycscope:+${_pycscope} -i '$pdir/$mf' -f '$pdir/$ct.tmp' ;} ${verbose:+set +x}"
        ;;
      Go|Ruby|go|rb)
        eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_starscope:+${_starscope} -i '$pdir/$mf' -f '$pdir/$ct.tmp' ;} ${verbose:+set +x}"
        ;;
    esac
    [ -s "$pdir/$ct.tmp" ] && cat "$pdir/$ct.tmp" >> "$pdir/$ct"

    pfts="${pfts}${pfts:+ }.$2$1"
  fi
}

# ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
scope_match_types () {
  # Process files with cscope like tools, matching them against known types
  #
  if [ -s "$pdir/$tt" ]; then
    
    if [ ${#_cscope} != 0 ]; then
      cat "$pdir/$tt" | sed -n "\=$rx_C$=I p" > "$pdir/$mf"
      [ -s "$pdir/$mf" ] && eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_cscope} -cb -i '$pdir/$mf' -f '$pdir/$ct.tmp' ; ${verbose:+set +x}"
      [ -s "$pdir/$ct.tmp" ] && cat "$pdir/$ct.tmp" >> "$pdir/$ct"

      cat "$pdir/$tt" | sed -n "\=$rx_java$=I p" > "$pdir/$mf"
      [ -s "$pdir/$mf" ] && eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_cscope} -cbR -i '$pdir/$mf' -f '$pdir/$ct.tmp' ; ${verbose:+set +x}"
      [ -s "$pdir/$ct.tmp" ] && cat "$pdir/$ct.tmp" >> "$pdir/$ct"
    fi

    if [ ${#_pycscope} != 0 ]; then
      cat "$pdir/$tt" | sed -n "\=$rx_py$=I p" > "$pdir/$mf"
      [ -s "$pdir/$mf" ] && eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_pycscope} -i '$pdir/$mf' -f '$pdir/$ct' ; ${verbose:+set +x}"
      [ -s "$pdir/$ct.tmp" ] && cat "$pdir/$ct.tmp" >> "$pdir/$ct"
    fi
    
    if [ ${#_starscope} != 0 ]; then
      cat "$pdir/$tt" | sed -n "\=$rx_go$=I p" > "$pdir/$mf"
      [ -s "$pdir/$mf" ] && eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_starscope} -i '$pdir/$mf' -f '$pdir/$ct' ; ${verbose:+set +x}"
      [ -s "$pdir/$ct.tmp" ] && cat "$pdir/$ct.tmp" >> "$pdir/$ct"

      cat "$pdir/$tt" | sed -n "\=$rx_rb$=I p" > "$pdir/$mf"
      [ -s "$pdir/$mf" ] && eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_starscope} -i '$pdir/$mf' -f '$pdir/$ct' ; ${verbose:+set +x}"
      [ -s "$pdir/$ct.tmp" ] && cat "$pdir/$ct.tmp" >> "$pdir/$ct"
    fi

    pfts="${pfts}${pfts:+ }.$2$1"
  fi
}

# ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
find_src () {
  local _tag= _cm= _min= _max=
  
  echo -ne "" > "$pdir/$mf"
  
  # Depth search?
  _max=${tag##*,}
  tag=${tag%,*}
  _min=${tag##*,}
  tag=${tag%,*}
  
  case "$tag" in
    [[:alnum:]]*)  # Default file types
      _tag=${tag%.i}
      [ "$tag" != "${_tag}" ] && _cm=i
      aux=$( echo "$re_types" | sed -n "s;^${_tag}:\(.*\);\1;; T; p; q" 2>/dev/null )
      [ $? != 0 -o ${#aux} = 0 ] && echo "WARNING ($FUNCNAME:$LINENO): invalid file type '$tag'." && return
        
      eval "${verbose:+echo '${PS4}<type> search (START): \"$tag\"'}"

      eval "find '$1' ${findopts:+\( $findopts \)} ${_min:+-mindepth ${_min}} ${_max:+-maxdepth ${_max}} \
                      -type f ${avoid:+\( ! -regex '$avoid' \)} ${findavoid:+\( $findavoid \)} \
                      -${_cm}regex '$aux'" >> "$pdir/$mf"
      rval=$?; [ $rval != 0 ] && echo "WARNING ($FUNCNAME:$LINENO): 'find' returned error code '$rval'." && return

      scope_match "${_tag}" ""

      eval "${verbose:+echo '${PS4}<type> search (END): \"$tag\"'}"
      ;;
      
    :*)  # ctags file types
      if [ ${#_ctags} != 0 ]; then
        tag=${tag#:}
        _tag=${tag%.i}
        [ "$tag" != "${_tag}" ] && _cm=i
        aux=$( echo "$re_ctags" | sed -n "s;^${_tag}:\(.*\);\1;; T; p; q" 2>/dev/null )
        [ $? != 0 -o ${#aux} = 0 ] && echo "WARNING ($FUNCNAME:$LINENO): invalid ctags file type '$tag'." && return
        
        eval "${verbose:+echo '${PS4}<ctags> search (START): \"$tag\"'}"
        
        eval "find '$1' ${findopts:+\( $findopts \)} ${_min:+-mindepth ${_min}} ${_max:+-maxdepth ${_max}} \
                        -type f ${avoid:+\( ! -regex '$avoid' \)} ${findavoid:+\( $findavoid \)} \
                        -${_cm}regex '$aux'" >> "$pdir/$mf"
        rval=$?; [ $rval != 0 ] && echo "WARNING ($FUNCNAME:$LINENO): 'find' returned error code '$rval'." && return

        scope_match "${_tag}" ":"
        
        eval "${verbose:+echo '${PS4}<ctags> search (END): \"$tag\"'}"
      fi
      ;;
      
    =*)  # Extra file types
      tag=${tag#=}
      _tag=${tag%.i}
      [ "$tag" != "${_tag}" ] && _cm=i
      if [ ${#_tag} != 0 ]; then
        aux=$( echo "$re_etags" | sed -n "s;^${_tag}:\(.*\);\1;; T; p; q" 2>/dev/null )
        [ $? != 0 -o ${#aux} = 0 ] && echo "WARNING ($FUNCNAME:$LINENO): invalid extra file type '${tag}'." && return
      fi
      if [ ${_tag:0:1} = n ]; then
        val=name
      else
        val=regex
      fi
      eval "${verbose:+echo '${PS4}<def> search (START): \"$tag\"'}"

      eval "find '$1' ${findopts:+\( $findopts \)} ${_min:+-mindepth ${_min}} ${_max:+-maxdepth ${_max}} \
                      -type f ${avoid:+\( ! -regex '$avoid' \)} ${findavoid:+\( $findavoid \)} \
                      -${_cm}$val '$aux'" > "$pdir/$tt"
      rval=$?; [ $rval != 0 ] && echo "WARNING ($FUNCNAME:$LINENO): 'find' returned error code '$rval'." && return

      scope_match_types "${_tag}" "="

      eval "${verbose:+echo '${PS4}<def> search (END): \"$tag\"'}"
      
      mv -f "$pdir/$tt" "$pdir/$mf"
      ;;
      
    *)
      echo "ERROR ($FUNCNAME:$LINENO): invalid file type '$tag'."
      exit 1
      ;;
  esac
  cat "$pdir/$mf" >> "$pdir/$fl"
}

# ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
tag_src () {
  local ext
  
  eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_ctags:+${_ctags} --fields=+i -n -R -L '$pdir/$fl' -f '$pdir/$tt' ;} ${verbose:+set +x}"
  
  if [ "$bkp" != - ]; then
    # Backup the current project
    #
    if [ "$bkp" = + ]; then
      ext=..bk1
      for aux in ..bk0 .; do 
        [ -f "$pdir/$prj.db${aux#.}" ] && eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} mv -f '$pdir/$prj.db${aux#.}' '$pdir/$prj.db${ext#.}' ; ${verbose:+set +x}"
        ext=$aux;
      done
    else
      eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} mv -f '$pdir/$prj.db' '$pdir/$prj.db${bkp}' ; ${verbose:+set +x}"
    fi
  fi
  aux=
  [ -s "$pdir/$ct" ] && aux="-c '$pdir/$ct'"
  eval "${verbose:+set -x ;} ${dryrun:+$dryrun '(${FUNCNAME:-<main>}:$LINENO)'} ${_cqmakedb:+${_cqmakedb} -s '$pdir/$prj.db' $aux ${_ctags:+-t '$pdir/$tt'} -p ;} ${verbose:+set +x}"
}

# """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# << main >>
#

vars_init

[ -f "$pdir/$fl" ] && rm -f "$pdir/$fl"

aux=$( getopt -o p:c:t:d:iIn:r:o:a:b:kARDES::L::vh --long project:,class:,types:,depth:,,,name:,regex:,options:,avoid:,backup:,keep,absolute,dry-run,debug,edebug,save::,save+::,save-::,load::,load+::,load-::,ctags:,cscope:,pycscope:,starscope:,cqmakedb:,verbose,help -- "$@" )
rval=$? ; [ $? != 0 ] && usage && exit $rval

eval set -- "$aux"
while true ; do
  case "$1" in
    -p|--project)
      opts="${opts}p"
      [ -z "${2//[![:alnum:]]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid project name '${2:-<empty>}'." && exit 1
      
      prj=$2
      shift
      ;;
      
    -c|--class|\
    -t|--types)
      aux=${1##*-}
      opts="${opts}${aux:0:1}"
      if [ ${aux:0:1} = c ]; then aux=: ; else aux= ; fi
      
      [ ${#2} = 0 -o -n "${2//[[:alnum:],.${aux:+_#+-}]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid project file type '${2:-<empty>}'." && exit 1
      
      for tag in ${2//[[:space:],]/ }; do
        val=$tag
        tag=${tag%.[iI]}
        if [ "$val" != "$tag" ]; then
          val=${tag##*.}
          val=${val#I}
        else
          val=$cm
        fi

        # Do not add tag if it is already present
        #
        if [ ${#tags} != 0 ]; then
          echo "$BELL${tags}$BELL" | grep -F "$BELL$aux$tag${val:+.$val},$min,$max$BELL" 2>/dev/null
          rval=$?
        else
          rval=1
        fi
        [ $rval != 0 ] && tags="$tags${tags:+$BELL}$aux$tag${val:+.$val},$min,$max"
      done
      shift
      ;;
      
    -d|--depth)
      opts="${opts}d"
      aux=${2//[[:space:]]/}
      [ -z "${2//[[:space:],=+-]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid search depth limit '$<2:-empty>'." && exit 1
      
      for aux in ${2//[[:space:],]/ }; do
        if [ "${aux: -1}" = '=' ]; then
          min=${aux:0:-1}
          max=$min
        elif [ "${aux: -1}" = + ]; then
          min=${aux:0:-1}
        elif [ "${aux: -1}" = - ]; then
          max=${aux:0:-1}
        else
          max=$aux
        fi

        [ -n "${min//[[:digit:]]/}" -o -n "${max//[[:digit:]]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): min/max must be numeric or empty '$2'." && exit 1
      done
      shift
      ;;
      
    -i)
      opts="${opts}i"
      cm=i
      ;;
      
    -I)
      opts="${opts}s"
      cm=
      ;;
      
    -n|--name|\
    -r|--regex)
      aux=${1##*-}
      opts="${opts}${aux:0:1}"
      tag=${2%%:*}
      [ "$tag" = "$2" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid <[[!][iI].]type:pattern> control structure '$2'." && exit 1
      
      val=${tag%%.*}
      if [ "$val" != "$tag" ]; then
        ! [ ".${val,,}" = .i -o ".${val,,}" = '.!' -o ".${val,,}" = '.!i' ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid <[[!][iI].]type:pattern> control structure '$2'." && exit 1
        bdir=${val/[iI]/} # Save '!', if any
        val=${val//[I!]/}
      else
        val=$cm
      fi
      
      # 'patterns' can be reused if a 'type' was associated to it and, as so,
      # requests where only case sensitiveness or depth were changed can be
      # handled without the need to pass the 'pattern' again (the control
      # structure will end with ':' on this case)
      #
      tag=${tag#*.}
      aux=${2#*:}
      
      [ -n "${tag//[[:alnum:]._#+-]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid project file type '$tag'." && exit 1

      if [ ${#bdir} != 0 ]; then  # '!'
        [ ${#tag} != 0 -o -z "${aux//[[:space:]]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid <[[!][iI].]type:pattern> control structure '$2'." && exit 1
        
        if [ ${opts: -1} = n ]; then tag=name; else tag=regex; fi
        findavoid="$findavoid${findavoid:+ -a }\! -$val$tag '$aux'"
      else
        # Do not add tag if it is already present
        #
        if [ ${#tag} != 0 ]; then
          if [ ${#etags} != 0 ]; then
            echo "$BELL${etags}$BELL" | grep -F "$BELL=${opts: -1}${tag}${val:+.$val},$min,$max$BELL" 2>/dev/null
            rval=$?
          else
            rval=1
          fi
          [ $rval != 0 ] && etags="$etags${etags:+$BELL}=${opts: -1}$tag${val:+.$val},$min,$max"
          
          rval=$( echo "$re_etags" | sed -n "\;^${opts: -1}$tag:; {=; q}" )
          if [ ${#rval} = 0 ]; then 
            [ ${#aux} = 0 ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid <[[!][iI].]type:pattern> control structure '$2'." && exit 1
            
            re_etags="$re_etags${re_etags:+$NL}${opts: -1}$tag:$aux"
          fi
        elif [ -n "${aux//[[:space:]]/}" ]; then
          # Always create a new id on this case
          #
          etags="$etags${etags:+$BELL}=${opts: -1}%$((++etagsid))${val:+.$val},$min,$max"
          re_etags="$re_etags${re_etags:+$NL}${opts: -1}%$etagsid:$aux"
        else
          echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid <[[!][iI].]type:pattern> control structure '$2'." && exit 1
        fi
      fi
      shift
      ;;
      
    -o|--options)
      [ -z "${2//[![:alnum:]]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid 'find' options '$2'." && exit 1
      findopts=$2
      ;;
      
    -a|--avoid)
      opts="${opts}a"
      aux=${2//[[:space:]]/}
      [ ${#aux} = 0 ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid revision control system regex '$2'." && exit 1
      
      if [ "$aux" = + ]; then
        avoid=$davoid
      elif [ "$aux" = - ]; then
        avoid=
      else
        avoid=$aux
      fi
      shift
      ;;
      
    -b|--backup)
      opts="${opts}b"
      [ ${#2} = 0 -o -n "${2//[![:space:]]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid backup extension '$2'." && exit 1
      
      if [ "${2#[[:alnum:]]}" != "$2" ]; then
        bkp=".$2"
      else
        bkp=$2
      fi
      shift
      ;;

    -k|--keep)
      opts="${opts}k"
      rm_fl=
      ;;
      
    -A|--absolute)
      opts="${opts}A"
      ;;
      
    -R|--dry-run)
      opts="${opts}R"
      dryrun=echo
      ;;
      
    -D|--debug)
      opts="${opts}D"
      ;;
      
    -E|--edebug)
      opts="${opts}E"
      ;;
    
    -S|--save|--save+|--save-)
      opts="${opts}S"
      save_opt=S
      if [ "$1" = -S ]; then
        aux=${2:0:1}
        [ -n "${aux//[!+-]/}" ] && save_opt=$aux && aux=${2:1}
      else
        aux=${1##*e}
        [ .$aux != . ] && save_opt=$aux
        aux=$2
      fi
      [ .$aux = . ] && aux=~/.codequery.sh.opts
      save_to=$aux
      if [ -e "${save_to}" ]; then
        aux=$( sed -n '1 { /^#codequery.sh#$/p; }; q' -- "${save_to}" ) \
        [ $? != 0 -o ${#aux} = 0 ] \
          && echo "WARNING (${FUNCNAME:-<main>}:$LINENO): cowardly avoiding overwrite '${save_to}' - 1st line is not '#codequery.sh#'." \
          && save_opt=
      fi
      ;;
      
    -L|--load|--load+|--load-)
      opts="${opts}L"
      load_opt=L
      if [ "$1" = -L ]; then
        aux=${2:0:1}
        [ -n "${aux//[!+-]/}" ] && load_opt=$aux && aux=${2:1}
      else
        aux=${1##*e}
        [ .$aux != . ] && load_opt=$aux
        aux=$2
      fi
      [ .$aux = . ] && aux=~/.codequery.sh.opts
      load_from=$aux
      if [ -e "${load_from}" ]; then
        aux=$( sed -n '1 { /^#codequery.sh#$/p; }; q' -- "${load_from}" )
        [ $? != 0 -o ${#aux} = 0 ] \
          && echo "WARNING (${FUNCNAME:-<main>}:$LINENO): Ignoring values from '${load_from}' - 1st line is not '#codequery.sh#'." \
          && load_opt=
      else
        echo "WARNING (${FUNCNAME:-<main>}:$LINENO): Ignoring values from '${load_from}' - file does no exist or is empty."
        load_opt=
      fi
      shift
      ;;
      
    --ctags|\
    --cscope|\
    --pycscope|\
    --starscope|\
    --cqmakedb)
      opts="${opts}P"
      if [ ${#2} != 0 ]; then
        [ -z "${2//[[:space:]]/}" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid '${1##*-}' path '$2'." && exit 1

        which "$2" 2>/dev/null
        [ $? != 0 ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid '${1##*-}' path '$2'." && exit 1
      fi
      eval _${1##*-}=$2
      shift
      ;;

    -v|--verbose)
      opts="${opts}v"
      # Test if the script was not already started with 'set -x' first
      [[ "${-/x/}" = "$-" ]] && verbose=-
      ;;

    -h|--help)
      opts="${opts}h"
      ;;

    --)
      shift
      break
      ;;
  esac
  shift
done

if [ ! ${#@} = 0 ]; then
  arg="${@//\ /$BELL}"
  arg="${arg// /$NL}"
else
  [ -z "$opts" ] && usage && exit 0

  arg=.
fi

# Tools available or disabled
#
if [ -n "${opts//[!L]/}" ] && [ .${load_opt} = .L -o .${load_opt} = .+ ]; then
  for aux in ctags cscope pycscope starscope cqmakedb; do
    [ ! -v _$aux ] \
      && val=$( cat "${load_from}" | sed -n "s;^[ \t]*$aux[ \t]*=[ \t]*;;; T; s;[ \t]$;;; s;\(['\"]\|\)\(.*\)\1;\2;p" 2>/dev/null ) \
      && [ $? = 0 ] && eval _$aux=$val
  done
fi
for aux in ctags cscope pycscope starscope cqmakedb; do
  [ ! -v _$aux ] && val=$( which $aux 2>/dev/null ) && [ $? = 0 ] && eval _$aux=$val
done
if [ -n "${opts//[!L]/}" ] && [ .${load_opt} = .- -o .${load_opt} = .+ ]; then
  for aux in findopts min max avoid findavoid tags etags; do
    [ ! -v _$aux ] \
      && val=$( cat "${load_from}" | sed -n "s;^[ \t]*$aux[ \t]*=[ \t]*;;; T; s;[ \t]$;;; s;\(['\"]\|\)\(.*\)\1;\2;p" 2>/dev/null ) \
      && [ $? = 0 ] && eval $aux=$val
  done
fi

# Generate the regex equivalent to ctags file match expression
#
[ ${#_ctags} != 0 ] && \
  re_ctags=$( ${_ctags} --list-maps |\
              sed -e 's=^[ \t]*\([^ \t]\+\)[ \t]\+\(.*[^ \t]\)[ \t]*$=\1:\\(\2\\)=; s=[ \t]\+=\\|=g; s=\.=\\.=g; s=\*=.*=g; s=\(\\[(|]\)\([[:alnum:][]\)=\1\\(.*/\\|\\)\2=g' )

# If project name was set then the user must have write rights to the directory it will
# be saved and, as so, it should be safe to set $pdir
#
if [ -n "${opts//[!p]/}" ]; then
  [ "${prj:0:1}" != / -a -n "${opts//[!A]/}" ] && prj=$( readlink -m "$cwd/$prj" )
  pdir=$( dirname "$prj" )
  [ ! -d "$pdir" ] && echo "ERROR (${FUNCNAME:-<main>}:$LINENO): invalid project directory name '$pdir'." && exit 1
  
  prj=$( basename "$prj" )
fi

# Default file types
#
[ -z "$tags" -a -z "$etags" ] && tags=c,,

# Print control information?
#
if [ -n "${opts//[!E]/}" ]; then
  [ ${#re_types} != 0 ]   && echo "Regex types : '${re_types//$NL/$NL               }'"
  [ ${#re_ctags} != 0 ]   && echo "Regex ctags : '${re_ctags//$NL/$NL               }'"
  [ ${#re_etags} != 0 ]   && echo "Extra defs  : '${re_etags//$NL/$NL               }'"

  [ ${#_ctags} != 0 ]     && echo "ctags       : '${_ctags}'"
  [ ${#_cscope} != 0 ]    && echo "cscope      : '${_cscope}'"
  [ ${#_pycscope} != 0 ]  && echo "pycscope    : '${_pycscope}'"
  [ ${#_starscope} != 0 ] && echo "starscope   : '${_starscope}'"
  [ ${#_cqmakedb} != 0 ]  && echo "cqmakedb    : '${_cqmakedb}'"
fi
if [ -n "${opts//[!Dv]/}" ]; then
  [ ${#opts} != 0 ]       && echo "Arg. options: '$opts'"
  [ ${#prj} != 0 ]        && echo "Project name: '$prj'" \
                          && echo "Project path: '$pdir'"
fi
if [ -n "${opts//[!D]/}" ]; then
  [ ${#tags} != 0 ]       && echo "Type / class: '${tags//$BELL/$NL               }'"
  [ ${#etags} != 0 ]      && echo "Extra defs  : '${etags//$BELL/$NL               }'"
  [ ${#avoid} != 0 ]      && echo "RCS (avoid) : '$avoid'"
  [ ${#findopts} != 0 ]   && echo "Find options: '${findopts}'"
  [ ${#findavoid} != 0 ]  && echo "Find (avoid): '${findavoid}'"
fi

# Help? Print & exit
#
[ -n "${opts//[!h]/}" ] && usage && exit 0

clean_up "$pdir/$all"

# Save the options?
#
[ -n "${opts//[!S]/}" -a ${#save_opt} != 0 ] && eval "${dryrun:+$dryrun \"} echo '#codequery.sh#' > '${save_to}' ${dryrun:+\"}"
if [ -n "${opts//[!S]/}" ] && [ .${save_opt} = .S -o .${save_opt} = .+ ]; then
  for aux in ctags cscope pycscope starscope cqmakedb; do
    # val=${!aux}
    eval val=\${_$aux}
    eval "${dryrun:+$dryrun \"} echo '$aux = \"${val}\"' >> '${save_to}' ${dryrun:+\"}"
  done
fi
if [ -n "${opts//[!S]/}" ] && [ .${save_opt} = .- -o .${save_opt} = .+ ]; then
  for aux in findopts min max avoid findavoid tags etags; do
    # val=${!aux}
    eval val=\${$aux}
    eval "${dryrun:+$dryrun \"} echo '$aux = \"${val}\"' >> '${save_to}' ${dryrun:+\"}"
  done
fi

IFS=$NL
for val in $( echo "$arg" | sed -e "s;^[ \t]\+;;; s;[ \t]\+$;;; s;$BELL; ;g;" ); do

  # Split dir ($bdir) and possible project name ($val). Note that $val will be
  # discarded if a proper project name is set
  #
  [ "${val:0:1}" != / -a -n "${opts//[!A]/}" ] && val=$( readlink -m "$cwd/$val" )
  if [ ! -d "$val" ]; then
    bdir=$( dirname "$val" )
    [ ! -d "$bdir" ] && echo "WARNING (${FUNCNAME:-<main>}:$LINENO): skipping invalid dir '$aux'." && continue
    
    val=$( basename "$val" )
  else
    bdir=$val
    val=
  fi
    
  # Assign default project name and set directories where things will be written.
  #
  if [ -z "${prj//[[:space:]]/}" ]; then
    if [ ${#val} = 0 ]; then
      if [ ".$bdir" = .. -o ".$bdir" = ... ]; then aux=$cwd; else aux=$bdir; fi
      prj=$( basename "$aux" |\
             sed -e 's=^[[:space:]]\+==; s=[[:space:]]\+$==; s=[[:space:]]\+= =; s=^\(.*\)[-_][0-9]\+\..*=\1=;' )
    else
      prj=$val
    fi
    [ -z "${prj//[![:alnum:]]/}" ] && echo "WARNING (${FUNCNAME:-<main>}:$LINENO): skipping invalid project name '$prj'." && continue
    
    pdir=$cwd

    if [ -n "${opts//[!Dv]/}" ]; then
      echo "Project name: '$prj'"
      echo "Project path: '$pdir'"
    fi
  fi
  [ -n "${opts//[!Dv]/}" ] && echo "Source path : '$bdir'$NL"

  # Process source files
  #
  for tag in ${tags//$BELL/$NL} ${etags//$BELL/$NL}; do find_src "$bdir"; done
  
  # Generate the database if anything matched and save the list of all files
  #
  [ -s "$pdir/$fl" ] && tag_src && [ -n "${opts//[!k]/}" ] && cat "$pdir/$fl" >> "$pdir/$all"
  
  [ -n "${opts//[!Dv]/}" ] && echo "${NL}Found files : '$pfts'"

  # Prepare for next iteration
  #
  clean_up ${rm_fl:+"$pdir/$all"}
  pfts=
  
  [ -z "${opts//[!p]/}" ] && prj=
done
