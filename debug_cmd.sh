#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ESPTOOL_PATH="$SCRIPT_DIR/tools/esptool/esptool.py"

# 检查 esptool.py 是否存在
if [ ! -f "$ESPTOOL_PATH" ]; then
  echo -e "\033[31mError: esptool.py not found in $ESPTOOL_PATH\033[0m"
  exit 1
fi

# 帮助信息
show_help() {
  echo -e "\033[33mUsage: $0 [command] [options]\033[0m"
  echo
  echo "Commands:"
  echo "  neighbor-test          Perform the neighboring channel test"
  echo "  EECO                   Erase Even sector, Check Odd sector VT"
  echo "  EOCE                   Erase Odd sector, Check Even sector VT"
  echo "  debug_help             Show this help message"
  echo
  echo "Options:"
  echo "  Any options will be passed directly to esptool.py"
}

# 默认设置
COMMAND=""

# 解析参数
if [ "$1" == "neighbor-test" ]; then
  COMMAND="neighbor-test"
  shift
elif [ "$1" == "EECO" ]; then
  COMMAND="EECO"
  shift
elif [ "$1" == "EOCE" ]; then
  COMMAND="EOCE"
  shift
elif [ "$1" == "debug_help" ]; then
  show_help
  exit 0
else
  REMAINING_ARGS=("$@")
fi

if [ -n "$COMMAND" ]; then
  # 读取 Flash 容量
  echo -e "\033[34mReading flash size...\033[0m"
  FLASH_SIZE_OUTPUT=$(python "$ESPTOOL_PATH" flash_id)
  FLASH_SIZE_LINE=$(echo "$FLASH_SIZE_OUTPUT" | grep "Detected flash size")
  FLASH_SIZE=$(echo "$FLASH_SIZE_LINE" | grep -oP '\d+MB')

  if [ -z "$FLASH_SIZE" ]; then
    echo -e "\033[31mError: Could not detect flash size.\033[0m"
    exit 1
  fi

  # 将 Flash 大小转换为字节数，并设置相应的全零文件
  case "$FLASH_SIZE" in
    "1MB")
      SIZE=$((1 * 1024 * 1024))
      ZERO_FILE="./flash_bin/zero_1mb_file"
      ;;
    "2MB")
      SIZE=$((2 * 1024 * 1024))
      ZERO_FILE="./flash_bin/zero_2mb_file"
      ;;
    "4MB")
      SIZE=$((4 * 1024 * 1024))
      ZERO_FILE="./flash_bin/zero_4mb_file"
      ;;
    "8MB")
      SIZE=$((8 * 1024 * 1024))
      ZERO_FILE="./flash_bin/zero_8mb_file"
      ;;
    "16MB")
      SIZE=$((16 * 1024 * 1024))
      ZERO_FILE="./flash_bin/zero_16mb_file"
      ;;
    *)
      echo -e "\033[31mError: Unsupported flash size $FLASH_SIZE.\033[0m"
      exit 1
      ;;
  esac

  START_ADDR=0x00000
  CHUNK_SIZE=0x1000  # 4K

  if [ "$COMMAND" == "neighbor-test" ]; then
    echo -e "\033[34mStarting neighboring channel test...\033[0m"

    # 计算结束地址
    END_ADDR=$((START_ADDR + SIZE))

    # 逐个4K空间进行擦除、写入和读取数据
    for ((ADDR=START_ADDR; ADDR<END_ADDR; ADDR+=CHUNK_SIZE)); do
      echo -e "\033[34mErasing region starting at $ADDR...\033[0m"
      python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE

      echo -e "\033[34mWriting zero_4k_file to $ADDR...\033[0m"
      python "$ESPTOOL_PATH" -p /dev/ttyUSB0 write_flash $ADDR ./flash_bin/zero_4k_file

      echo -e "\033[34mReading back written data from $ADDR...\033[0m"
      python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read

      # 比较写入的数据和读回的数据
      cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read
      if [ $? -ne 0 ]; then
        echo -e "\033[31mError: Mismatch found at address $ADDR\033[0m"
        exit 1
      fi

      # 邻道读取（前一个块）
      if [ $ADDR -ne 0 ]; then
        PREV_ADDR=$((ADDR - CHUNK_SIZE))
        echo -e "\033[34mReading back neighboring data from $PREV_ADDR...\033[0m"
        python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $PREV_ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_neighbor

        # 比较前一个块的数据和源数据
        cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_neighbor
        if [ $? -ne 0 ]; then
          echo -e "\033[31mError: Mismatch found at neighboring address $PREV_ADDR\033[0m"
          exit 1
        fi
      fi
    done

    # 输出邻道测试模式激活的消息
    echo -e "\033[32mNeighboring channel test mode: active\033[0m"
  elif [ "$COMMAND" == "EECO" ] || [ "$COMMAND" == "EOCE" ]; then
    echo -e "\033[34mErasing entire flash...\033[0m"
    python "$ESPTOOL_PATH" erase_flash

    echo -e "\033[34mWriting entire flash with zero data from $ZERO_FILE...\033[0m"
    python "$ESPTOOL_PATH" -p /dev/ttyUSB0 write_flash $START_ADDR $ZERO_FILE

    if [ "$COMMAND" == "EECO" ]; then
      echo -e "\033[34mStarting EECO test: Erase Even sector, Check Odd sector VT...\033[0m"

      # 计算结束地址
      END_ADDR=$((START_ADDR + SIZE))

      # 擦除偶数扇区
      for ((ADDR=START_ADDR; ADDR<END_ADDR; ADDR+=CHUNK_SIZE*2)); do
        echo -e "\033[34mErasing even sector starting at $ADDR...\033[0m"
        python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE
      done

      # 检查奇数扇区
      for ((ADDR=START_ADDR + CHUNK_SIZE; ADDR<END_ADDR; ADDR+=CHUNK_SIZE*2)); do
        echo -e "\033[34mReading back odd sector data from $ADDR...\033[0m"
        python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_odd

        # 比较奇数扇区的数据和源数据
        cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_odd
        if [ $? -ne 0 ]; then
          echo -e "\033[31mError: Mismatch found at odd sector address $ADDR\033[0m"
          exit 1
        fi
      done

      # 输出 EECO 测试完成消息
      echo -e "\033[32mEECO test mode: complete\033[0m"
    elif [ "$COMMAND" == "EOCE" ]; then
      echo -e "\033[34mStarting EOCE test: Erase Odd sector, Check Even sector VT...\033[0m"

      # 计算结束地址
      END_ADDR=$((START_ADDR + SIZE))

      # 擦除奇数扇区
      for ((ADDR=START_ADDR + CHUNK_SIZE; ADDR<END_ADDR; ADDR+=CHUNK_SIZE*2)); do
        echo -e "\033[34mErasing odd sector starting at $ADDR...\033[0m"
        python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE
      done

      # 检查偶数扇区
      for ((ADDR=START_ADDR; ADDR<END_ADDR; ADDR+=CHUNK_SIZE*2)); do
        echo -e "\033[34mReading back even sector data from $ADDR...\033[0m"
        python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_even

        # 比较偶数扇区的数据和源数据
        cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_even
        if [ $? -ne 0 ]; then
          echo -e "\033[31mError: Mismatch found at even sector address $ADDR\033[0m"
          exit 1
        fi
      done

      # 输出 EOCE 测试完成消息
      echo -e "\033[32mEOCE test mode: complete\033[0m"
    fi
  fi
else
  # 执行 esptool.py 脚本并传入剩余参数
  python "$ESPTOOL_PATH" "${REMAINING_ARGS[@]}"
fi
