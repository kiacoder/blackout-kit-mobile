"""Linux-only regression tests for the experimental process lifetime pipe."""
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path


def start(guard, code):
    return subprocess.Popen(
        [guard, sys.executable, "-c", code],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True,
    )


def wait_gone(pid):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        path = Path(f"/proc/{pid}/stat")
        try:
            # A killed orphan may be a zombie until its new parent reaps it.
            if path.read_text().rsplit(")", 1)[1].split()[0] == "Z":
                return
        except FileNotFoundError:
            return
        time.sleep(0.01)
    raise AssertionError("Child remained alive")


def test_shutdown(guard, action):
    with start(guard, "import os,time; print(os.getpid(),flush=True); time.sleep(60)") as proc:
        pid = int(proc.stdout.readline())
        try:
            action(proc)
            assert proc.wait(timeout=5) != 0
            wait_gone(pid)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)


def test_thread_turnover(guard):
    result = []
    worker = threading.Thread(target=lambda: result.append(
        start(guard, "import time; print('ready',flush=True); time.sleep(60)")
    ))
    worker.start()
    worker.join(timeout=5)
    assert not worker.is_alive()
    with result[0] as proc:
        try:
            assert proc.stdout.readline().strip() == "ready"
            time.sleep(0.2)
            assert proc.poll() is None
            proc.stdin.close()
            assert proc.wait(timeout=5) != 0
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)


def test_owner_death(guard):
    # The intermediate process is the sole lifetime-pipe writer.
    owner_code = (
        "import subprocess,sys,time; "
        "p=subprocess.Popen([sys.argv[1],sys.executable,'-c',"
        "'import os,time; print(os.getpid(),flush=True); time.sleep(60)'],"
        "stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True); "
        "print(p.pid,p.stdout.readline().strip(),flush=True); time.sleep(60)"
    )
    with subprocess.Popen([sys.executable, "-c", owner_code, guard],
                          stdout=subprocess.PIPE, text=True) as owner:
        try:
            supervisor, child = map(int, owner.stdout.readline().split())
            owner.kill()
            owner.wait(timeout=5)
            wait_gone(supervisor)
            wait_gone(child)
        finally:
            if owner.poll() is None:
                owner.kill()
                owner.wait(timeout=5)


def main():
    guard = str(Path(sys.argv[1]).resolve())
    with start(guard, "raise SystemExit(23)") as proc:
        assert proc.wait(timeout=5) == 23
    test_shutdown(guard, lambda proc: proc.stdin.close())
    test_shutdown(guard, lambda proc: proc.send_signal(signal.SIGTERM))
    test_shutdown(guard, lambda proc: proc.kill())
    test_thread_turnover(guard)
    test_owner_death(guard)
    print("Six process-supervisor regressions passed.")


if __name__ == "__main__":
    main()
