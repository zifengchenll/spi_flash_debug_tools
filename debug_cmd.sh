#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ESPTOOL_PATH="$SCRIPT_DIR/tools/esptool/esptool.py"

# 检查 esptool.py 是否存在
if [ ! -f "$ESPTOOL_PATH" ]; then
    echo -e "\033[31m##########################################################
错误：未在 $ESPTOOL_PATH 找到 esptool.py
##########################################################\033[0m"
    exit 1
fi

# 帮助信息
show_help() {
    echo -e "\033[33m##########################################################
用法: $0 [命令] [选项]
##########################################################\033[0m"
    echo
    echo "命令:"
    echo "  single_read_write_check   遍历所有扇区，对每个扇区进行擦除、写入、读取、校验"
    echo "  eeco                      整片硬存擦除，写入全零，擦除偶数扇区，检查奇数扇区"
    echo "  eoce                      整片硬存擦除，写入全零，擦除奇数扇区，检查偶数扇区"
    echo "  help                      显示帮助信息"
    echo
    echo "选项:"
    echo
    echo "说明:如果输入的参数命令不存在，则会传递给 esptool.py"
    echo "示例:"
    echo "  flash_id                                                            读取FLASHID"
    echo "  erase_flash                                                         整片硬存擦除，可以显示擦除耗时"
    echo "  erase_region 0x20000 0x4000                                         要擦除硬存的某个区域，起始地址是0x20000，长度为0x4000字节"
    echo "  -p /dev/ttyUSB0 write_flash 0x1000 ./flash_bin/zero_4k_file         将二进制数据通过/dev/ttyUSB0写入硬存，写入地址0x1000开始"
    echo "  -p /dev/ttyUSB0 -b 460800 read_flash 0 0x200000 flash_contents.bin  将硬存中数据通过/dev/ttyUSB0串口读出，使用的波特率是460800，起始地址0，长度0x200000，保存的文件名flash_contents.bin"
    echo "  -p /dev/ttyUSB0 -b 460800 read_flash 0 ALL flash_contents.bin       将硬存中数据通过/dev/ttyUSB0串口读出，使用的波特率是460800，起始地址0，长度硬存容量，保存的文件名flash_contents.bin"
    echo "  write_flash_status --bytes 2 --non-volatile 0                       --bytes决定了写入多少个状态寄存器字节，分别对应WRSR(01h)，WRSR2(31h)，WRSR3(11h)"
    echo "  read_flash_status  --bytes 2                                        --bytes决定了读取多少个状态寄存器字节，分别对应RDSR(05h)，RDSR2(35h)，RDSR3(15h)"
}

# 默认设置
COMMAND=""
ERROR_SECTORS=()
ERROR_HANDLING=""

# 捕获 Ctrl+C 信号并打印错误扇区地址
trap 'print_errors_and_exit' SIGINT

# 打印错误扇区地址并退出
print_errors_and_exit() {
    if [ ${#ERROR_SECTORS[@]} -ne 0 ]; then
        echo -e "\033[33m##########################################################
接收到中断信号，记录错误...
##########################################################\033[0m"
        echo -e "\033[31m##########################################################
在以下扇区检测到错误:
##########################################################\033[0m"
        for sector in "${ERROR_SECTORS[@]}"; do
            printf "\033[31m扇区: 0x%08X\033[0m\n" $sector
        done
    fi
    exit 1
}

# 解析参数
if [ "$1" == "single_read_write_check" ]; then
    COMMAND="single_read_write_check"
    shift
elif [ "$1" == "eeco" ]; then
    COMMAND="eeco"
    shift
elif [ "$1" == "eoce" ]; then
    COMMAND="eoce"
    shift
elif [ "$1" == "help" ]; then
    show_help
    exit 0
else
    REMAINING_ARGS=("$@")
fi

# 对所有测试命令进行询问
if [ "$COMMAND" == "single_read_write_check" ] || [ "$COMMAND" == "eeco" ] || [ "$COMMAND" == "eoce" ]; then
    echo -e "\033[33m##########################################################
选择错误处理机制:
##########################################################\033[0m"
    echo "1) 检测到错误时立即退出"
    echo "2) 检测到错误时继续测试，完成后提供报告"
    read -p "请输入你的机制 (1 或 2): " choice

    if [ "$choice" == "1" ]; then
        ERROR_HANDLING="exit"
    elif [ "$choice" == "2" ]; then
        ERROR_HANDLING="record"
    else
        echo -e "\033[31m##########################################################
无效选择。正在退出。
##########################################################\033[0m"
        exit 1
    fi
fi

if [ -n "$COMMAND" ]; then
    echo -e "\033[34m##########################################################
读取 Flash 大小
##########################################################\033[0m"
    FLASH_SIZE_OUTPUT=$(python "$ESPTOOL_PATH" flash_id)
    FLASH_SIZE_LINE=$(echo "$FLASH_SIZE_OUTPUT" | grep "Detected flash size")
    FLASH_SIZE=$(echo "$FLASH_SIZE_LINE" | grep -oP '\d+MB')

    if [ -z "$FLASH_SIZE" ]; then
        echo -e "\033[31m##########################################################
错误：无法检测到 Flash 大小
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
错误：不支持的 Flash 大小 $FLASH_SIZE
##########################################################\033[0m"
        exit 1
        ;;
    esac

    START_ADDR=0x00000
    CHUNK_SIZE=0x1000 # 4K

    if [ "$COMMAND" == "single_read_write_check" ]; then
        echo -e "\033[34m##########################################################
开始单扇区读写检查
##########################################################\033[0m"

        # 计算结束地址
        END_ADDR=$((START_ADDR + SIZE))

        # 逐个4K空间进行擦除、写入和读取数据
        for ((ADDR = START_ADDR; ADDR < END_ADDR; ADDR += CHUNK_SIZE)); do
            echo -e "\033[34m##########################################################
擦除区域，起始地址 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
            python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE

            echo -e "\033[34m##########################################################
写入全零文件到 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
            python "$ESPTOOL_PATH" -p /dev/ttyUSB0 write_flash $ADDR ./flash_bin/zero_4k_file

            echo -e "\033[34m##########################################################
从 0x$(printf "%08X" $ADDR) 读取数据
##########################################################\033[0m"
            python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read

            # 比较写入的数据和读回的数据
            cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read
            if [ $? -ne 0 ]; then
                if [ "$ERROR_HANDLING" == "exit" ]; then
                    echo -e "\033[31m##########################################################
错误：地址 0x$(printf "%08X" $ADDR) 处数据不匹配
##########################################################\033[0m"
                    print_errors_and_exit
                else
                    echo -e "\033[33m##########################################################
记录错误，地址 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
                    ERROR_SECTORS+=("$ADDR")
                fi
            fi

        done

        # 输出测试模式激活的消息
        echo -e "\033[32m##########################################################
单扇区读写检查模式：完成
##########################################################\033[0m"
    elif [ "$COMMAND" == "eeco" ] || [ "$COMMAND" == "eoce" ]; then
        echo -e "\033[34m##########################################################
擦除整个 Flash
##########################################################\033[0m"
        python "$ESPTOOL_PATH" erase_flash

        echo -e "\033[34m##########################################################
用全零数据写入整个 Flash
##########################################################\033[0m"
        python "$ESPTOOL_PATH" -p /dev/ttyUSB0 write_flash $START_ADDR $ZERO_FILE

        if [ "$COMMAND" == "eeco" ]; then
            echo -e "\033[34m##########################################################
开始 EECO 测试：擦除偶数扇区，检查奇数扇区
##########################################################\033[0m"

            # 计算结束地址
            END_ADDR=$((START_ADDR + SIZE))

            # 擦除偶数扇区
            for ((ADDR = START_ADDR; ADDR < END_ADDR; ADDR += CHUNK_SIZE * 2)); do
                echo -e "\033[34m##########################################################
擦除偶数扇区，起始地址 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
                python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE
            done

            # 检查奇数扇区
            for ((ADDR = START_ADDR + CHUNK_SIZE; ADDR < END_ADDR; ADDR += CHUNK_SIZE * 2)); do
                echo -e "\033[34m##########################################################
读取奇数扇区数据，地址 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
                python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_odd

                # 比较奇数扇区的数据和源数据
                cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_odd
                if [ $? -ne 0 ]; then
                    if [ "$ERROR_HANDLING" == "exit" ]; then
                        echo -e "\033[31m##########################################################
错误：奇数扇区地址 0x$(printf "%08X" $ADDR) 处数据不匹配
##########################################################\033[0m"
                        print_errors_and_exit
                    else
                        echo -e "\033[33m##########################################################
记录错误，奇数扇区地址 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
                        ERROR_SECTORS+=("$ADDR")
                    fi
                fi
            done

            # 输出 EECO 测试完成消息
            echo -e "\033[32m##########################################################
EECO 测试模式：完成
##########################################################\033[0m"
        elif [ "$COMMAND" == "eoce" ]; then
            echo -e "\033[34m##########################################################
开始 EOCE 测试：擦除奇数扇区，检查偶数扇区
##########################################################\033[0m"

            # 计算结束地址
            END_ADDR=$((START_ADDR + SIZE))

            # 擦除奇数扇区
            for ((ADDR = START_ADDR + CHUNK_SIZE; ADDR < END_ADDR; ADDR += CHUNK_SIZE * 2)); do
                echo -e "\033[34m##########################################################
擦除奇数扇区，起始地址 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
                python "$ESPTOOL_PATH" erase_region $ADDR $CHUNK_SIZE
            done

            # 检查偶数扇区
            for ((ADDR = START_ADDR; ADDR < END_ADDR; ADDR += CHUNK_SIZE * 2)); do
                echo -e "\033[34m##########################################################
读取偶数扇区数据，地址 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
                python "$ESPTOOL_PATH" -p /dev/ttyUSB0 read_flash $ADDR $CHUNK_SIZE ./debug_temp/zero_4k_file_read_even

                # 比较偶数扇区的数据和源数据
                cmp ./flash_bin/zero_4k_file ./debug_temp/zero_4k_file_read_even
                if [ $? -ne 0 ]; then
                    if [ "$ERROR_HANDLING" == "exit" ]; then
                        echo -e "\033[31m##########################################################
错误：偶数扇区地址 0x$(printf "%08X" $ADDR) 处数据不匹配
##########################################################\033[0m"
                        print_errors_and_exit
                    else
                        echo -e "\033[33m##########################################################
记录错误，偶数扇区地址 0x$(printf "%08X" $ADDR)
##########################################################\033[0m"
                        ERROR_SECTORS+=("$ADDR")
                    fi
                fi
            done

            # 输出 EOCE 测试完成消息
            echo -e "\033[32m##########################################################
EOCE 测试模式：完成
##########################################################\033[0m"
        fi
    fi

    # 如果选择了记录错误模式，输出错误扇区地址
    if [ "$ERROR_HANDLING" == "record" ] && [ ${#ERROR_SECTORS[@]} -ne 0 ]; then
        echo -e "\033[31m##########################################################
在以下扇区检测到错误:
##########################################################\033[0m"
        for sector in "${ERROR_SECTORS[@]}"; do
            printf "\033[31m扇区: 0x%08X\033[0m\n" $sector
        done
    fi
else
    # 执行 esptool.py 脚本并传入剩余参数
    echo -e "\033[34m##########################################################
执行 esptool.py，传递的参数如下:
##########################################################\033[0m"
    python "$ESPTOOL_PATH" "${REMAINING_ARGS[@]}"
fi
