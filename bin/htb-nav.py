#!/usr/bin/env python3

import subprocess
import sys
import os
import shutil
import signal

# -----------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------

AUTHOR = "Made by: z1rov (https://zirov.xyz)"
CONTACT = "OSCP | OSCP+ | CRTO"

# Dificultad por defecto al enviar flags (1 = "Piece of Cake")
DEFAULT_DIFFICULTY = "1"

# -----------------------------------------------------------------
# UTILITIES
# -----------------------------------------------------------------

def clear():
    os.system('clear' if os.name == 'posix' else 'cls')

def log_info(msg):
    print(f"[INFO] {msg}")

def log_ok(msg):
    print(f"[OK] {msg}")

def log_error(msg):
    print(f"[ERROR] {msg}")

def run_cmd(cmd):
    print()
    print("-" * 50)
    try:
        result = subprocess.run(cmd, text=True)
        return result
    except Exception as e:
        log_error(f"Error: {e}")
        return None

def wait():
    try:
        input("\n[>] Press ENTER to continue...")
    except KeyboardInterrupt:
        clean_exit()

def clean_exit():
    print()
    log_ok("Happy hacking!")
    sys.exit(0)

# -----------------------------------------------------------------
# INTERFACE
# -----------------------------------------------------------------

def header():
    clear()
    print()
    print("╔════════════════════════════════════════╗")
    print("║              HTB MENU                  ║")
    print("╠════════════════════════════════════════╣")
    print(f"║  {AUTHOR}    ║")
    print(f"║  {CONTACT}                   ║")
    print("╚════════════════════════════════════════╝")
    print()

def main_menu():
    header()
    print("[1] List machines")
    print("[2] Start machine")
    print("[3] Stop machine")
    print("[4] Machine info")
    print("[5] Submit flag")
    print("[6] My profile")
    print("[0] Exit")
    print()
    try:
        return input("[?] Option: ").strip()
    except KeyboardInterrupt:
        clean_exit()

# -----------------------------------------------------------------
# COMMANDS
# -----------------------------------------------------------------

def list_machines():
    clear()
    log_info("Getting active machines...")
    run_cmd(["htb-operator", "machine", "list", "--active", "--limit", "20"])
    wait()

def start_machine():
    clear()
    try:
        name = input("[?] Machine name: ").strip()
    except KeyboardInterrupt:
        clean_exit()

    if not name:
        log_error("Empty name")
        wait()
        return
    log_info(f"Starting {name}...")
    run_cmd(["htb-operator", "machine", "start", "--name", name])
    wait()

def stop_machine():
    clear()
    print("[1] By name")
    print("[2] Current active machine")

    try:
        opt = input("[?] Option: ").strip()
    except KeyboardInterrupt:
        clean_exit()

    if opt == "1":
        try:
            name = input("[?] Name: ").strip()
        except KeyboardInterrupt:
            clean_exit()

        if name:
            log_info(f"Stopping {name}...")
            run_cmd(["htb-operator", "machine", "stop", "--name", name])
    elif opt == "2":
        log_info("Stopping active machine...")
        run_cmd(["htb-operator", "machine", "stop"])
    else:
        log_error("Invalid option")
    wait()

def machine_info():
    clear()
    try:
        target = input("[?] Name or ID: ").strip()
    except KeyboardInterrupt:
        clean_exit()

    if not target:
        log_error("Empty input")
        wait()
        return

    if target.isdigit():
        run_cmd(["htb-operator", "machine", "info", "--id", target])
    else:
        run_cmd(["htb-operator", "machine", "info", "--name", target])
    wait()

def submit_flag():
    clear()
    print("[1] User flag")
    print("[2] Root flag")

    try:
        opt = input("[?] Option: ").strip()
    except KeyboardInterrupt:
        clean_exit()

    try:
        flag = input("[?] Flag: ").strip()
    except KeyboardInterrupt:
        clean_exit()

    if not flag:
        log_error("Empty flag")
        wait()
        return

    try:
        difficulty = input(
            f"[?] Difficulty (1-10) [default: {DEFAULT_DIFFICULTY} - Piece of Cake]: "
        ).strip()
    except KeyboardInterrupt:
        clean_exit()

    if not difficulty:
        difficulty = DEFAULT_DIFFICULTY

    if opt == "1":
        result = run_cmd(["htb-operator", "machine", "submit", "--user-flag", flag, "--difficulty", difficulty])
        if result is not None and result.returncode == 0:
            log_ok("User flag submitted")
        else:
            log_error("Failed to submit user flag")
    elif opt == "2":
        result = run_cmd(["htb-operator", "machine", "submit", "--root-flag", flag, "--difficulty", difficulty])
        if result is not None and result.returncode == 0:
            log_ok("Root flag submitted")
        else:
            log_error("Failed to submit root flag")
    else:
        log_error("Invalid option")
    wait()

def my_profile():
    clear()
    log_info("Loading profile...")
    run_cmd(["htb-operator", "info"])
    wait()

# -----------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------

def check_htb_operator():
    htb_path = shutil.which("htb-operator")
    if htb_path:
        return True
    try:
        result = subprocess.run(["htb-operator", "info"],
                              capture_output=True,
                              timeout=2)
        if result.returncode == 0 or "error" not in result.stderr.decode():
            return True
    except:
        pass
    return False

def signal_handler(sig, frame):
    print()
    log_ok("Happy hacking!")
    sys.exit(0)

def main():
    signal.signal(signal.SIGINT, signal_handler)

    if not check_htb_operator():
        log_error("htb-operator not found")
        print("\nSolution: export PATH=\"$HOME/.local/bin:$PATH\"")
        sys.exit(1)

    actions = {
        "1": list_machines,
        "2": start_machine,
        "3": stop_machine,
        "4": machine_info,
        "5": submit_flag,
        "6": my_profile,
    }

    while True:
        try:
            choice = main_menu()
        except KeyboardInterrupt:
            clean_exit()

        if choice == "0":
            clean_exit()
        elif choice in actions:
            actions[choice]()
        else:
            log_error("Invalid option")
            wait()

if __name__ == "__main__":
    main()
