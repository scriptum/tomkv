#!/bin/sh

BITRATE=600
PASSES=1
OGGQ=3
HQ=0

usage() {
  echo "Usage: $0 [-b bitrate] [-o oggquality] [-qp] file [...]"
  echo "-b - bitrate, default 600"
  echo "-o - ogg vorbis quality, default 3"
  echo "-q - very high quality, very slow"
  echo "-p - use 2 pass encoding (default 1 pass)"
}

which mencoder | grep mencoder > /dev/null

if [ $? -eq 1 ]
then
  echo "You need mencoder."
  exit 1
fi

mencoder -x264encopts 2>&1 | grep "x264encopts is not an MEncoder option" > /dev/null

if [ $? -eq 0 ]
then
  echo "Mencoder compiled without H.264 support. Install libx264-dev and recompile mplayer."
  exit 1
fi

which oggenc | grep oggenc > /dev/null

if [ $? -eq 1 ]
then
  echo "You need oggenc."
  exit 1
fi

while getopts ":b:o:phq" opt; do
  case "$opt" in
    b) BITRATE=$OPTARG ;;
    p) 
      PASSES=2
      echo "Two pass encoding enabled"
    ;;
    o) OGGQ=$OPTARG ;;
    q) 
      HQ=1
      echo "HIGH QUALITY - SLOW AS HELL"
    ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
    ;;
    h)
      echo "Invalid option: -$OPTARG" >&2
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

TMPDIR=/tmp/mencoder_x86_64
mkdir -p $TMPDIR

OPTS=bitrate=${BITRATE}:subq=5:8x8dct:frameref=2:bframes=3:b_pyramid=normal:weight_b
if [ $HQ = "1" ]
then
  OPTS=bitrate=${BITRATE}:subq=6:partitions=all:8x8dct:me=umh:frameref=15:bframes=4:weight_b:me_range=64:trellis=2
fi
# FILTER="-vf scale=512:-10"
for file in "$@"; do
  echo encoding "$file"

  if [ $PASSES = "2" ]
  then
    nice mencoder -o /dev/null -nosound -ovc x264 \
    -x264encopts "${OPTS}:pass=1" \
    ${FILTER} "$file" 
    OPTS=$OPTS:pass=2
  fi

  nice mencoder -o $TMPDIR/video.h264 -nosound -ovc x264 \
  -x264encopts "${OPTS}" \
  ${FILTER} "$file"

  mkfifo $TMPDIR/audio.wav >/dev/null 2>&1
  nice oggenc -q $OGGQ $TMPDIR/audio.wav -o $TMPDIR/audio.ogg >/dev/null 2>&1 &
  mplayer -quiet "$file" -vc dummy -nocache -vo null -ao pcm:fast:file=$TMPDIR/audio.wav >/dev/null 2>&1

  nice mkvmerge -o "$file.mkv" $TMPDIR/video.h264 $TMPDIR/audio.ogg >/dev/null 2>&1
done
rm -fr $TMPDIR
