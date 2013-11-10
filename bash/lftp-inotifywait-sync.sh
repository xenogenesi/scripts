#/bin/bash

# License: WTFPL www.wtfpl.ne

# 1. create a config file with USER PASSWORD HOST RDIR LFTPOPT variables (see below)
# 2. cd into *local* working directory
# 3. launch the script: bash /path/lftp-sync.sh </path/config file> [-m]
#    [optional -m] for initial mirror (download) of the whole ftp directory

# NOTICE limits/bugs:
# -r recursive: /proc/sys/fs/inotify/max_user_watches. (default 8192)
# see inotifywait man page for bugs, mkdir -p sub/dir will miss subdirs 
#     (mput is used with -d to create full path but empty dirs will fail)

# TODO: check coherency with queue-parallel
#       set cmd:queue-parallel 7
# TODO: lftp more verbose??
# TODO: test force-ssl/tls

if [ $# -lt 1 ]; then
	echo "Invald arguments." >&2
	echo "usage: ${0##*/} [config file]" >&2
	exit 1
fi

# config file format
# USER=user
# PASSWORD=password
# HOST=host
# RDIR=dir/subdir ## root dir untested!
# LFTPOPT="set cmd:verbose yes; set ssl:verify-certificate no; set ftp:passive-mode true;"
# LFTPMIRROPT="--parallel=7"

if [ -f "$1" ]; then
	. "$1"
	shift
fi

while [ $# -gt 0 ]; do
	if [ "$1" = "-m" ]; then
		# mirror the remote content of the dir $RDIR directory into current directory (*NOT* $RDIR itself)
		shift
		lftp -e "$LFTPOPT mirror -c $LFTPMIRROPT $RDIR $PWD; exit" -u $USER,$PASSWORD $HOST
	fi
done

LASTPUT=
ftp_put() {
	# create and modify call mput twice on same file (but we want create for touch only)
	SUM=$(sum "$1")
	if [ "$1:$SUM" = "$LASTPUT" ]; then
		echo "*ignored:$SUM* queue mput -d $1" >&2
	else
		echo "queue mput -d $1" >&2
		echo "queue mput -d $1"
		LASTPUT="$1:$SUM"
	fi
}

ftp_rm() {
	echo "queue rm -fr $1" >&2
	echo "queue rm -fr $1"
}

ftp_mv() {
	echo "queue mv $1 $2" >&2
	echo "queue mv $1 $2"
}

ftp_mkdir() {
	echo "queue mkdir -p $1" >&2
	echo "queue mkdir -p $1"
}

# --excludei ignore some vi/emacs tmp/swp files
inotifywait -r -m -e create,delete,modify,create,moved_to,moved_from \
	--excludei '(\.(#.*|sw[px]|.*~)|[45][0-9]+)' \
. | while read dir flags node; do
	ISDIR=0
	DELETE=0
	CLOSE_WRITE=0
	CLOSE=0
	MOVED_TO=0 # keep MOVED_FROM
	CREATE=0
	MODIFY=0
	aflags=(${flags//,/ })
	out=""
	for flag in "${aflags[@]}"; do
		eval "$flag=1"
	done
	if [ -z "$node" ]; then
		out="$dir"
	else
		out="$dir$node"
	fi
	if [ "$DELETE" = 1 ]; then
		# FIXME remove if rm -fr work for both
		if [ "$ISDIR" = 1 ]; then
			ftp_rm "$out"
		else
			ftp_rm "$out"
		fi
	# elif [ "$CLOSE_WRITE" = 1 ]; then
	# 	if [ "$CLOSE" = 1 ]; then
	# 		echo "close write close: $out"
	# 	else
	# 		echo "close write: $out"
	# 	fi
	elif [ "$MOVED_FROM" = 1 ]; then
		MOVED_FROM=$out
	elif [ "$MOVED_TO" = 1 ]; then
		# TODO check if may a moved_to come without a moved_from
		ftp_mv "$MOVED_FROM" "$out"
	elif [ "$MODIFY" = 1 ]; then
		ftp_put "$out"
	elif [ "$CREATE" = 1 ]; then
		if [ "$ISDIR" = 1 ]; then
			ftp_mkdir "$out"
		else
			ftp_put "$out"
		fi
	 # else
	 # 	# ignore, unhandled
	 # 	echo $out
	fi
done | lftp -e "$LFTPOPT; cd $RDIR;" -u $USER,$PASSWORD $HOST >&2
