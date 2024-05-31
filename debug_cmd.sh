#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ESPTOOL_PATH="$SCRIPT_DIR/tools/esptool/esptool.py"

# 检查 esptool.py 是否存在
if [ ! -f "$ESPTOOL_PATH" ]; then
  echo "Error: esptool.py not found in $ESPTOOL_PATH"
  exit 1
fi

# 默认设置
NEIGHBOR_TEST_MODE=false

# 帮助信息
show_help() {
  echo "Usage: $0 [command] [options]"
  echo
  echo "Commands:"
  echo "  neighbor-test          Perform the neighboring channel test"
  echo "  debug_help             Show this help message"
  echo
  echo "Options:"
  echo "  Any options will be passed directly to esptool.py"
}

# 解析参数
if [ "$1" == "neighbor-test" ]; then
  NEIGHBOR_TEST_MODE=true
  shift
elif [ "$1" == "debug_help" ]; then
  show_help
  exit 0
else
  REMAINING_ARGS=("$@")
fi

if $NEIGHBOR_TEST_MODE; then
  # 读取 Flash 容量
  FLASH_SIZE_OUTPUT=$(python "$ESPTOOL_PATH" flash_id)
  FLASH_SIZE_LINE=$(echo "$FLASH_SIZE_OUTPUT" | grep "Detected flash size")
  FLASH_SIZE=$(echo "$FLASH_SIZE_LINE" | grep -oP '\d+MB')

  if [ -z "$FLASH_SIZE" ]; then
    echo "Error: Could not detect flash size."
    exit 1
  fi

  # 将 Flash 大小转换为字节数
  case "$FLASH_SIZE" in
    "1MB")
      SIZE=$((1 * 1024 * 1024))
      ;;
    "2MB")
      SIZE=$((2 * 1024 * 1024))
      ;;
    "4MB")
      SIZE=$((4 * 1024 * 1024))
      ;;
    "8MB")
      SIZE=$((8 * 1024 * 1024))
      ;;
    "16MB")
      SIZE=$((16 * 1024 * 1024))
      ;;
    *)
      echo "Error: Unsupported flash size $FLASH_SIZE."
      exit 1
      ;;
  esac

  START_ADDR=0x00000
  CHUNK_SIZE=0x1000  # 4K

  # 计算结束地址
  END_ADDR=$((START_ADDR + SIZE))

  # 逐个4K空间进行擦除、写入和读取数据
  for ((ADDR=START_ADDR; ADDR<END_ADDR; ADDR+=CHUNK_SIZE)); do
    echo "Erasing region starting at $ADDR..."
    python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE

    echo "Writing zero_4k_file to $ADDR..."
    python "$ESPTOOL_PATH" -p /dev/ttyUSB0 write_flash $ADDR ./flash_bin/zero_4k_file

    echo "Reading back written data from $ADDR..."
    python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read

    # 比较写入的数据和读回的数据
    cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read
    if [ $? -ne 0 ]; then
      echo "Error: Mismatch found at address $ADDR"
      exit 1
    fi

    # 邻道读取（前一个块）
    if [ $ADDR -ne 0 ]; then
      PREV_ADDR=$((ADDR - CHUNK_SIZE))
      echo "Reading back neighboring data from $PREV_ADDR..."
      python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $PREV_ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_neighbor

      # 比较前一个块的数据和源数据
      cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_neighbor
      if [ $? -ne 0 ]; then
        echo "Error: Mismatch found at neighboring address $PREV_ADDR"
        exit 1
      fi
    fi
  done

  # 输出邻道测试模式激活的消息
  echo "Neighboring channel test mode: active"
else
  # 执行 esptool.py 脚本并传入剩余参数
  python "$ESPTOOL_PATH" "${REMAINING_ARGS[@]}"
fi
