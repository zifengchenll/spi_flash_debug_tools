import subprocess
import sys
import os

def run_esptool(args=None):
    esptool_path = os.path.join(".", "tools", "esptool", "esptool.py")
    
    if not os.path.exists(esptool_path):
        print(f"Error: esptool.py not found at {esptool_path}")
        return

    if args is None:
        args = []  # 默认操作，可以根据需要修改
        print("No arguments provided. Using default operation.")
    
    command = ["python", esptool_path] + args

    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        while True:
            output = process.stdout.readline()
            if output:
                print(output.strip())
            error = process.stderr.readline()
            if error:
                print(error.strip(), file=sys.stderr)
            if output == "" and process.poll() is not None:
                break

        rc = process.poll()
        return rc
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        run_esptool()  # 无参数时调用默认操作
    else:
        run_esptool(sys.argv[1:])
