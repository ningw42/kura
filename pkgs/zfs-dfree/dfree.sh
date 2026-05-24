CUR_PATH="$(realpath "$1")"
FSTYPE=$(df -PT "$CUR_PATH" | tail -1 | awk '{print $2}')

if [ "$FSTYPE" = 'zfs' ]; then
  # df gives us the dataset name in column 1
  DATASET=$(df -PT "$CUR_PATH" | tail -1 | awk '{print $1}')

  USED=$(zfs get -o value -Hp used "$DATASET")
  AVAIL=$(zfs get -o value -Hp available "$DATASET")

  AVAIL_KB=$(( AVAIL / 1024 ))
  TOTAL_KB=$(( (USED + AVAIL) / 1024 ))

  echo "$TOTAL_KB $AVAIL_KB"
else
  df -PT "$CUR_PATH" | tail -1 | awk '{print $3" "$5}'
fi
