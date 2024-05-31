#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ESPTOOL_PATH="$SCRIPT_DIR/tools/esptool/esptool.py"

# 检查 esptool.py 是否存在
if [ ! -f "$ESPTOOL_PATH" ]; then
  echo "Error: esptool.py not found in $ESPTOOL_PATH"
  exit 1
fi

# 执行 esptool.py 脚本并传入所有参数
python "$ESPTOOL_PATH" "$@"
