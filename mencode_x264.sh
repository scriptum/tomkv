#!/bin/sh

BITRATE=600
PASSES=1
OGGQ=3
HQ=0
FAST=0
FILTER=""
THREADS=auto
TMPBASE="."
usage() {
	echo "Usage: $0 [-b bitrate] [-s scale] [-t threads] [-T tmpdir] [-o oggquality] [-qpf] file..."
	echo "-b - bitrate, default 600"
	echo "-s - scale"
	echo "-t - encoding threads (default - auto)"
	echo "-T - where to place temp dir (default - current working dir)"
	echo "-o - ogg vorbis quality, default 3"
	echo "-q - very high quality, very slow"
	echo "-p - use 2 pass encoding (default 1 pass)"
}

check() {
	which $1 > /dev/null 2>&1
	if [ $? -eq 1 ]
	then
		echo "You need to install $1."
		exit 1
	fi
}

check mencoder
check oggenc
check mkvmerge

mencoder -x264encopts 2>&1 | grep "x264encopts is not an MEncoder option" > /dev/null

if [ $? -eq 0 ]
then
	echo "Mencoder compiled without H.264 support. Install libx264-dev and recompile mplayer."
	exit 1
fi

while getopts "b:o:phfqs:t:T:F:" opt; do
	case "$opt" in
		b) BITRATE="$OPTARG" ;;
		p)
			PASSES=2
			echo "Two pass encoding enabled"
		;;
		o) OGGQ="$OPTARG" ;;
		s) FILTER="-vf scale=$OPTARG:-10" ;;
		T) TMPBASE="$OPTARG" ;;
		t) THREADS="$OPTARG" ;;
		q)
			HQ=1
			echo "HIGH QUALITY - SLOW AS HELL"
		;;
		f)
			FAST=1
			echo "Fast coding enabled (preview mode)"
		;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			usage
			exit 1
		;;
		h)
			usage
			exit 0
		;;
		:)
			echo echo "Option -$OPTARG requires an argument." >&2
			exit 1
		;;
	esac
done
shift $(( OPTIND - 1 ))

if [ $# -lt 1 ]
then
	echo "Specify at least one video file."
	exit 1
fi

TMPDIR=./.mencoder
mkdir -p $TMPDIR

GENERAL_OPTS="weight_b:threads=${THREADS}:bitrate=${BITRATE}"

OPTS="subq=5:8x8dct:frameref=2:bframes=3:b_pyramid=normal:${GENERAL_OPTS}"

if [ $FAST = "1" ]
then
	OPTS="subq=4:bframes=2:b_pyramid=normal:${GENERAL_OPTS}"
else
	if [ $HQ = "1" ]
	then
		OPTS="subq=6:partitions=all:8x8dct:me=umh:frameref=15:bframes=4:me_range=64:trellis=2:${GENERAL_OPTS}"
	fi
fi



for file in "$@"; do
	echo encoding "$file"

	if [ $PASSES = "2" ]
	then
		nice mencoder -o /dev/null -nosound -ovc x264 \
		-x264encopts "${OPTS}:pass=1" \
		${FILTER} "$file"
		if [ $? -ne 0 ]
		then exit 1
		fi
		OPTS=$OPTS:pass=2
	fi

	nice mencoder -o $TMPDIR/video.h264 -nosound -ovc x264 \
	-x264encopts "${OPTS}" -vf field=0 -fps 50000/1001 -ofps 25000/1001 \
	${FILTER} "$file"
	if [ $? -ne 0 ]
	then exit 1
	fi

	mkfifo $TMPDIR/audio.wav >/dev/null 2>&1
	nice oggenc -q $OGGQ $TMPDIR/audio.wav -o $TMPDIR/audio.ogg >/dev/null 2>&1 &
	mplayer -quiet "$file" -vc dummy -nocache -vo null -ao pcm:fast:file=$TMPDIR/audio.wav >/dev/null 2>&1

	nice mkvmerge -o "$file.mkv" $TMPDIR/video.h264 $TMPDIR/audio.ogg >/dev/null 2>&1
done
rm -fr $TMPDIR
