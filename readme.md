
# SPI FLASH 分析工具

![项目Logo](docs/images/project_logo.png)

![GitHub Top Language](https://img.shields.io/github/languages/top/zifengchenll/circular_buffer.svg)
![GitHub Language Count](https://img.shields.io/github/languages/count/zifengchenll/circular_buffer.svg)
![GitHub Release](https://img.shields.io/github/license/zifengchenll/circular_buffer.svg)
![GitHub Release](https://img.shields.io/github/repo-size/zifengchenll/circular_buffer.svg)
![GitHub Release](https://img.shields.io/github/last-commit/zifengchenll/circular_buffer.svg)
![GitHub Release](https://img.shields.io/github/v/release/zifengchenll/circular_buffer.svg)

[English](readme_en.md) | [中文](./readme.md)

在物联网嵌入式设备场景中，存储非易失性数据，常见会使用SPI FLASH，对于SPI FLASH，我们需要有一个专用的分析工具，能够快速对FLASH进行数据分析，可以快速读取FLASH ID，辨识FLASH厂商、型号，支持对FLASH芯片进行擦除、写入、读取、校验功能。

另外说明，为了遵循高效的原则，并且作者不希望去实时维护一份FLASH驱动，故我们的FLASH分析工具，会引用乐鑫提供的驱动工具。

------

## 特性规格

| 规格         | 详细描述                             |
| ------------ | ------------------------------------ |
| FLASH ID读取 | 读取FLASH ID，辨识厂商、型号         |
| 擦除         | 支持整片擦除，支持指定区域擦除       |
| 写入         | 数据或者文件，写入到FLASH指定区域    |
| 读取         | 读取FLASH中的指定区域，保存成文件    |
| 校验         | 通过数据写入和检验，监测数据的一致性 |

## 实现原理

基于乐鑫的FLASH驱动工具，添加测试用例脚本，制作成一个专用于FLASH的分析工具

## 安装步骤

请按照以下步骤安装和配置项目：

克隆仓库：

```bash
git@github.com:zifengchenll/spi_flash_debug_tools.git
```

进入目录：

```bash
cd spi_flash_debug_tools/
```

## 使用说明

使用帮助指令，打印各个命令行的用途：（./debug_cmd.sh help）

```
##########################################################
用法: ./debug_cmd.sh [命令] [选项]
##########################################################

命令:
  single_read_write_check   遍历所有扇区，对每个扇区进行擦除、写入、读取、校验
  eeco                      整片硬存擦除，写入全零，擦除偶数扇区，检查奇数扇区
  eoce                      整片硬存擦除，写入全零，擦除奇数扇区，检查偶数扇区
  help                      显示帮助信息

选项:

说明:如果输入的参数命令不存在，则会传递给 esptool.py
示例:
  flash_id                                                            读取FLASHID
  erase_flash                                                         整片硬存擦除，可以显示擦除耗时
  erase_region 0x20000 0x4000                                         要擦除硬存的某个区域，起始地址是0x20000，长度为0x4000字节
  -p /dev/ttyUSB0 write_flash 0x1000 ./flash_bin/zero_4k_file         将二进制数据通过/dev/ttyUSB0写入硬存，写入地址0x1000开始
  -p /dev/ttyUSB0 -b 460800 read_flash 0 0x200000 flash_contents.bin  将硬存中数据通过/dev/ttyUSB0串口读出，使用的波特率是460800，起始地址0，长度0x200000，保存的文件名flash_contents.bin
  -p /dev/ttyUSB0 -b 460800 read_flash 0 ALL flash_contents.bin       将硬存中数据通过/dev/ttyUSB0串口读出，使用的波特率是460800，起始地址0，长度硬存容量，保存的文件名flash_contents.bin
  write_flash_status --bytes 2 --non-volatile 0                       --bytes决定了写入多少个状态寄存器字节，分别对应WRSR(01h)，WRSR2(31h)，WRSR3(11h)
  read_flash_status  --bytes 2                                        --bytes决定了读取多少个状态寄存器字节，分别对应RDSR(05h)，RDSR2(35h)，RDSR3(15h)

```

## 测试说明

支持的测试模型：

```
./debug_cmd.sh eeco
./debug_cmd.sh eoce
```

## 项目结构

```bash
.
├── debug_cmd.sh
├── debug_temp
├── docs
│   └── images
├── flash_bin
│   ├── zero_16mb_file
│   ├── zero_1mb_file
│   ├── zero_2mb_file
│   ├── zero_4k_file
│   ├── zero_4mb_file
│   └── zero_8mb_file
├── license
├── readme_en.md
├── readme.md
├── test_case
└── tools
    ├── esptool
    └── flash_id

```

## 注意事项

如果配置状态寄存器，一定要注意正确性，某些寄存器配置是非易失性的，可能产生永久影响

## 参考文献

- [乐鑫驱动：git@github.com:espressif/esptool.git](git@github.com:espressif/esptool.git)
