#!/usr/bin/env python3
"""Run a command on a pseudo-terminal and answer its prompts from a file.

usage: pty_feed.py <answers-file> <command> [args...]

Each time the command's output ends with ": " or "? " (a prompt) the next
line of the answers file is typed. No EOF is ever sent, so the command sees a
real terminal. Output is copied to stdout. Exits with the command's status,
or 124 after 90 s.
"""
import os
import pty
import select
import sys
import time


def main():
    answers = open(sys.argv[1]).read().split("\n")
    if answers and answers[-1] == "":
        answers.pop()
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(sys.argv[2], sys.argv[2:])
    deadline = time.time() + 90
    tail = b""
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                data = os.read(fd, 4096)
            except OSError:
                break
            if not data:
                break
            sys.stdout.buffer.write(data)
            sys.stdout.flush()
            tail = (tail + data)[-200:]
            continue
        if tail.endswith((b": ", b"? ")) and answers:
            os.write(fd, (answers.pop(0) + "\n").encode())
            tail = b""
    else:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
        return 124
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    sys.exit(main())
