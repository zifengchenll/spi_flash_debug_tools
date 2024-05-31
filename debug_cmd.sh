#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ESPTOOL_PATH="$SCRIPT_DIR/tools/esptool/esptool.py"

# 检查 esptool.py 是否存在
if [ ! -f "$ESPTOOL_PATH" ]; then
  echo -e "\033[31m##########################################################
Error: esptool.py not found in $ESPTOOL_PATH
##########################################################\033[0m"
  exit 1
fi

# 帮助信息
show_help() {
  echo -e "\033[33m##########################################################
Usage: $0 [command] [options]
##########################################################\033[0m"
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
ERROR_SECTORS=()
ERROR_HANDLING=""

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

# 对所有测试命令进行询问
if [ "$COMMAND" == "neighbor-test" ] || [ "$COMMAND" == "EECO" ] || [ "$COMMAND" == "EOCE" ]; then
  echo -e "\033[33m##########################################################
Select the error handling mechanism:
##########################################################\033[0m"
  echo "1) Exit immediately on error"
  echo "2) Record errors and continue, then report"
  read -p "Enter your choice (1 or 2): " choice

  if [ "$choice" == "1" ]; then
    ERROR_HANDLING="exit"
  elif [ "$choice" == "2" ]; then
    ERROR_HANDLING="record"
  else
    echo -e "\033[31m##########################################################
Invalid choice. Exiting.
##########################################################\033[0m"
    exit 1
  fi
fi

if [ -n "$COMMAND" ]; then
  echo -e "\033[34m##########################################################
Reading flash size
##########################################################\033[0m"
  FLASH_SIZE_OUTPUT=$(python "$ESPTOOL_PATH" flash_id)
  FLASH_SIZE_LINE=$(echo "$FLASH_SIZE_OUTPUT" | grep "Detected flash size")
  FLASH_SIZE=$(echo "$FLASH_SIZE_LINE" | grep -oP '\d+MB')

  if [ -z "$FLASH_SIZE" ]; then
    echo -e "\033[31m##########################################################
Error: Could not detect flash size
##########################################################\033[0m"
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
      echo -e "\033[31m##########################################################
Error: Unsupported flash size $FLASH_SIZE
##########################################################\033[0m"
      exit 1
      ;;
  esac

  START_ADDR=0x00000
  CHUNK_SIZE=0x1000  # 4K

  if [ "$COMMAND" == "neighbor-test" ]; then
    echo -e "\033[34m##########################################################
Starting neighboring channel test
##########################################################\033[0m"

    # 计算结束地址
    END_ADDR=$((START_ADDR + SIZE))

    # 逐个4K空间进行擦除、写入和读取数据
    for ((ADDR=START_ADDR; ADDR<END_ADDR; ADDR+=CHUNK_SIZE)); do
      echo -e "\033[34m##########################################################
Erasing region starting at $ADDR
##########################################################\033[0m"
      python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE

      echo -e "\033[34m##########################################################
Writing zero_4k_file to $ADDR
##########################################################\033[0m"
      python "$ESPTOOL_PATH" -p /dev/ttyUSB0 write_flash $ADDR ./flash_bin/zero_4k_file

      echo -e "\033[34m##########################################################
Reading back written data from $ADDR
##########################################################\033[0m"
      python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read

      # 比较写入的数据和读回的数据
      cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read
      if [ $? -ne 0 ]; then
        if [ "$ERROR_HANDLING" == "exit" ]; then
          echo -e "\033[31m##########################################################
Error: Mismatch found at address $ADDR
##########################################################\033[0m"
          exit 1
        else
          ERROR_SECTORS+=("$ADDR")
        fi
      fi

      # 邻道读取（前一个块）
      if [ $ADDR -ne 0 ]; then
        PREV_ADDR=$((ADDR - CHUNK_SIZE))
        echo -e "\033[34m##########################################################
Reading back neighboring data from $PREV_ADDR
##########################################################\033[0m"
        python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $PREV_ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_neighbor

        # 比较前一个块的数据和源数据
        cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_neighbor
        if [ $? -ne 0 ]; then
          if [ "$ERROR_HANDLING" == "exit" ]; then
            echo -e "\033[31m##########################################################
Error: Mismatch found at neighboring address $PREV_ADDR
##########################################################\033[0m"
            exit 1
          else
            ERROR_SECTORS+=("$PREV_ADDR")
          fi
        fi
      fi
    done

    # 输出邻道测试模式激活的消息
    echo -e "\033[32m##########################################################
Neighboring channel test mode: active
##########################################################\033[0m"
  elif [ "$COMMAND" == "EECO" ] || [ "$COMMAND" == "EOCE" ]; then
    echo -e "\033[34m##########################################################
Erasing entire flash
##########################################################\033[0m"
    python "$ESPTOOL_PATH" erase_flash

    echo -e "\033[34m##########################################################
Writing entire flash with zero data from $ZERO_FILE
##########################################################\033[0m"
    python "$ESPTOOL_PATH" -p /dev/ttyUSB0 write_flash $START_ADDR $ZERO_FILE

    if [ "$COMMAND" == "EECO" ]; then
      echo -e "\033[34m##########################################################
Starting EECO test: Erase Even sector, Check Odd sector VT
##########################################################\033[0m"

      # 计算结束地址
      END_ADDR=$((START_ADDR + SIZE))

      # 擦除偶数扇区
      for ((ADDR=START_ADDR; ADDR<END_ADDR; ADDR+=CHUNK_SIZE*2)); do
        echo -e "\033[34m##########################################################
Erasing even sector starting at $ADDR
##########################################################\033[0m"
        python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE
      done

      # 检查奇数扇区
      for ((ADDR=START_ADDR + CHUNK_SIZE; ADDR<END_ADDR; ADDR+=CHUNK_SIZE*2)); do
        echo -e "\033[34m##########################################################
Reading back odd sector data from $ADDR
##########################################################\033[0m"
        python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_odd

        # 比较奇数扇区的数据和源数据
        cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_odd
        if [ $? -ne 0 ]; then
          if [ "$ERROR_HANDLING" == "exit" ]; then
            echo -e "\033[31m##########################################################
Error: Mismatch found at odd sector address $ADDR
##########################################################\033[0m"
            exit 1
          else
            ERROR_SECTORS+=("$ADDR")
          fi
        fi
      done

      # 输出 EECO 测试完成消息
      echo -e "\033[32m##########################################################
EECO test mode: complete
##########################################################\033[0m"
    elif [ "$COMMAND" == "EOCE" ]; then
      echo -e "\033[34m##########################################################
Starting EOCE test: Erase Odd sector, Check Even sector VT
##########################################################\033[0m"

      # 计算结束地址
      END_ADDR=$((START_ADDR + SIZE))

      # 擦除奇数扇区
      for ((ADDR=START_ADDR + CHUNK_SIZE; ADDR<END_ADDR; ADDR+=CHUNK_SIZE*2)); do
        echo -e "\033[34m##########################################################
Erasing odd sector starting at $ADDR
##########################################################\033[0m"
        python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE
      done

      # 检查偶数扇区
      for ((ADDR=START_ADDR; ADDR<END_ADDR; ADDR+=CHUNK_SIZE*2)); do
        echo -e "\033[34m##########################################################
Reading back even sector data from $ADDR
##########################################################\033[0m"
        python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_even

        # 比较偶数扇区的数据和源数据
        cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_even
        if [ $? -ne 0 ]; then
          if [ "$ERROR_HANDLING" == "exit" ]; then
            echo -e "\033[31m##########################################################
Error: Mismatch found at even sector address $ADDR
##########################################################\033[0m"
            exit 1
          else
            ERROR_SECTORS+=("$ADDR")
          fi
        fi
      done

      # 输出 EOCE 测试完成消息
      echo -e "\033[32m##########################################################
EOCE test mode: complete
##########################################################\033[0m"
    fi
  fi

  # 如果选择了记录错误模式，输出错误扇区地址
  if [ "$ERROR_HANDLING" == "record" ] && [ ${#ERROR_SECTORS[@]} -ne 0 ]; then
    echo -e "\033[31m##########################################################
Errors detected in the following sectors:
##########################################################\033[0m"
    for sector in "${ERROR_SECTORS[@]}"; do
      echo -e "\033[31mSector: $sector\033[0m"
    done
  fi
else
  # 执行 esptool.py 脚本并传入剩余参数
  echo -e "\033[34m##########################################################
Executing esptool.py with the provided arguments
##########################################################\033[0m"
  python "$ESPTOOL_PATH" "${REMAINING_ARGS[@]}"
fi
