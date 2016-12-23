#!/bin/bash

NAME=${0##*/}
CONTAINER=mkv
FILTERS=""
OPTS_BEFORE=""
ACODER="libvorbis -ar 44100"
VCODEC="libx264"
OPTS=""
NOSUBS=-sn
CROP=0
DELOGO=0
SCALE=""
HQ=0
AUDIO_CHANNEL=auto
AUDIO_LANG=${LANG%%_*}
[[ -z $AUDIO_LANG ]] && AUDIO_LANG=ru

usage() {
  cat <<EOF
Usage: $NAME [options] file...
Simple tool to compress your video for mobile device or video archive. It uses 
modern codecs with high compression ratio.
By default it uses H.264 for video and Vorbis (ogg) for audio, but you can use
H.265 and OPUS for low bitrates.
Typical usage: $NAME -O5q <input>

Arguments:
    -q      very high quality profile (use this for final conversion)
    -a NUM|STREAM
            select audio channel: a stream number or name (default - first 
            audio stream for your locale taken from LANG environment)
    -a STREAM1:STREAM2:...
            you may specify several audio streams which will be reordered by
            its description
    -b TIME
            begin time (00:00:00)
    -c NUM  set crf quality (default 23 for h264, 28 for h265)
    -d      deinterlace
    -e TIME
            end time
    -f      fast mode
    -l X,Y,WIDTH,HEIGHT
            delogo (x,y,w,h), e.g. 58,34,118,18
    -L      delogo (autodetect)
    -n NUM  denoise, improves compressability (typical value: 4-8)
    -o NUM[k]
            audio bitrate (48k)
    -p      postprocess
    -r NUM[k]
            maximum bitrate (no limit)
    -s WIDTHxHEIGHT
            maximum scale e.g. 768x480
    -t TUNE tune for video type [animation|film|grain]
    -u      smartblur, improves compressability, good for source with blocking
            artifacts
    -V      copy video
    -A      copy audio
    -O      encode audio with opus instead of vorbis (default bitrate is 32k)
    -C      crop video (crop area will be detected automatically)
    -S      keep subtitles
    -5      encode video with x265 instead of x264
    -9      encode video with VP9 instead of x264

    -h      help
EOF
  exit $1
}

[[ $# -eq 0 ]] && usage -1

check() {
  if ! type -p $1 > /dev/null; then
    [ -n "$2" ] && shift
    echo "You need to install '$1'."
    exit 1
  fi
}

check ffmpeg
check convert ImageMagick

cropdetect()
{
  local area
  area=$(ffmpeg -ss 10:00 -i "$1" -vf cropdetect=32:16:0 -f null -vframes 1000 /dev/null |& grep cropdetect | sed s/.*crop=// | sort | uniq -c | sort -n  | tail -1 | awk '{print $2}')
  echo "Detected crop area: $area" 1>&2
  echo "crop=$area"
}

logodetect()
{
  local crop="" area
  [[ -n $CROPF ]] && crop=,$CROPF
  for j in {1..10}; do
  ffmpeg -ss $j:00 -i "$1" \
    -vf "select='eq(pict_type,PICT_TYPE_I)'$crop,edgedetect=0.5,boxblur=1" \
    -vsync vfr -vframes 10 .tmp_logodetect$j%02d.jpg 2> /dev/null &
  done
  wait
  area=$(convert -compose add .tmp_logodetect*.jpg  -level 5000%,0% -flatten \
    -shave 5x5 -bordercolor white -border 5x5 -level 90%,0 -normalize -threshold 50% -morphology Dilate Diamond:10 -trim info: | \
    sed -e s/.*JPEG// -e 's/[x+]/ /g' | \
    awk '{printf "%d:%d:%d:%d", $5, $6, $1, $2}')
  echo "Detected logo area: $area" 1>&2
  echo "delogo=$area,"
  rm .tmp_logodetect*.jpg
}


while getopts "a:b:c:de:fhl:n:o:pqr:s:t:uACLOSV459" opt; do
  case "$opt" in
    a) AUDIO_CHANNEL="$OPTARG";;
    b) OPTS_BEFORE+="-ss $OPTARG ";;
    c) CRF="$OPTARG";;
    d) FILTERS+="kerndeint,";;
    e) OPTS+="-to $OPTARG ";;
    f) OPTS+="-preset fast ";;
    # h) FILTERS+="deshake,";;
    l) DELOGO="delogo=$OPTARG,";;
    L) DELOGO=1;;
    n) FILTERS+="hqdn3d=$OPTARG,";;
    o) ARATE="${OPTARG%k}";;
    p) FILTERS+="pp=de,";;
    q) HQ=1;;
    r) MAXRATE=${OPTARG%k}; OPTS+="-maxrate ${MAXRATE}k -bufsize ${MAXRATE}0k " ;;
    s)
      W="${OPTARG%x*}"
      H="${OPTARG#*x}"
      
      SCALE="scale='if(gt(a,$W/$H),$W,trunc(oh*a/2)*2)':'if(gt(a,$W/$H),trunc(ow/a/2)*2,$H)':flags=lanczos,"
    ;;
    t) OPTS+="-tune $OPTARG ";;
    u) FILTERS+="smartblur=5:lt=1:ct=1,";;
    A) ARATE="copy";;
    C) CROP=1;;
    O) ACODER="libopus"; [[ -z $ARATE ]] && ARATE=32;;
    S) NOSUBS="";;
    V) VCODEC="copy";;
    4) VCODEC="libx264";;
    5) VCODEC="libx265"; [[ -z $CRF ]] && CRF=27;;
    9) VCODEC="libvpx-vp9"; CONTAINER=webm;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage 1
    ;;
    h)
      usage 0
    ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage 1
    ;;
  esac
done
if [[ $ARATE == copy ]]; then
  ACODEC="-c:a copy"
else
  [[ -z $ARATE ]] && ARATE=48
  ACODEC="-ac 2 -ab ${ARATE}k -c:a $ACODER"
fi
if [[ -n $CRF ]]; then
  if [[ $VCODEC == libx265 ]]; then
      CRFOPTS="-x265-params crf=$CRF"
    [[ -n $MAXRATE ]] && CRFOPTS+=":vbv_bufsize=${MAXRATE}0:vbv_maxrate=$MAXRATE"
    
  else
    CRFOPTS="-crf $CRF"
  fi
  if [[ $VCODEC == libvpx-vp9 ]]; then
    OPTS+="-b:v 0 "
  fi
fi
if [[ $HQ == 1 ]]; then
  if [[ $VCODEC == libvpx-vp9 ]]; then
    OPTS+="-speed 0 -tile-columns 0 -frame-parallel 0 -lag-in-frames 25 -g 9999 -slices 1 -cpu-used 0 "
  elif [[ $VCODEC == libx264 ]]; then
    OPTS+="-preset veryslow "
    # OPTS+="-x264opts psy_rd=4,4:bframes=16 "
  else
    OPTS+="-preset veryslow "
  fi
fi

show_tags()
{
  ffprobe -v error -print_format csv -select_streams a -show_entries stream=index:stream_tags "$@" 2>/dev/null
}

OPTS="$ACODEC -c:v $VCODEC $CRFOPTS $OPTS $NOSUBS"

shift $((OPTIND-1))

for i in "$@"; do
  newname="${i%.*}.$CONTAINER"
  j=1
  while [[ -f $newname ]]; do
    newname="${i%.*}_$j.$CONTAINER"
    ((j++))
  done
  F="$FILTERS"
  CROPF=""
  if [[ $CROP == 1 ]]; then
    CROPF=$(cropdetect "$i")
    F+=$CROPF,
  fi
  if [[ $DELOGO == 1 ]]; then
    F+=$(logodetect "$i")
  elif [[ $DELOGO == delogo* ]]; then
    F+=$DELOGO
  fi
  case $AUDIO_CHANNEL in
  [0-9]*)
    AOPTS="-map 0:0 -map 0:$AUDIO_CHANNEL "
  ;;
  auto) 
    N=$(show_tags "$i" | grep ,$AUDIO_LANG | head -1 | cut -d, -f2)
    [[ -n $N ]] && AOPTS="-map 0:0 -map 0:$N "
  ;;
  *)
    TAGS=$(show_tags "$i")
    AOPTS="-map 0:0 "
    for AC in ${AUDIO_CHANNEL//:/ }; do
      N=$(echo "$TAGS" | grep -iF "$AC" | head -1 | cut -d, -f2)
      [[ -n $N ]] && AOPTS+="-map 0:$N "
    done
  ;;
  esac
  F+=$SCALE
  [[ -n $F ]] && F="-vf ${F%,}"
  echo ffmpeg $OPTS_BEFORE -i "'$i'" $AOPTS $OPTS -pix_fmt yuv420p $F "'$newname'"
  ffmpeg $OPTS_BEFORE -i "$i" $AOPTS $OPTS -pix_fmt yuv420p $F "$newname"
done
