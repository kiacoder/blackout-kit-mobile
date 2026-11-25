package com.blackoutkit.vpn;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.channels.FileLock;
import java.util.concurrent.atomic.AtomicReference;

/** Runs only in the explicitly opted-in guard test package. */
public final class ProcessGuardAcceptance extends Instrumentation {
    private static final long TIMEOUT_MS = 5000;
    private File guard;
    private File fixture;
    private int passed;

    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            require("com.blackoutkit.vpn.guardtest".equals(getTargetContext().getPackageName()),
                    "Wrong test target; refusing to run");
            File libs = new File(getTargetContext().getApplicationInfo().nativeLibraryDir);
            guard = new File(libs, "libprocess_guard.so");
            fixture = new File(libs, "libprocess_guard_fixture.so");
            require(guard.isFile() && guard.canExecute(), "Supervisor not executable");
            require(fixture.isFile() && fixture.canExecute(), "Fixture not executable");
            testNormalExit();
            testStop("eof", false);
            testStop("term", false);
            testStop("eof", true);
            if (Build.VERSION.SDK_INT >= 26) testStop("kill", false);
            result.putString("stream", "\nPROCESS_GUARD_ACCEPTANCE_PASS cases=" + passed + "\n");
            finish(Activity.RESULT_OK, result);
        } catch (Exception | AssertionError failure) {
            result.putString("stream", "\nPROCESS_GUARD_ACCEPTANCE_FAIL: " + failure + "\n");
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private Process launch(String... args) throws IOException {
        String[] command = new String[args.length + 2];
        command[0] = guard.getAbsolutePath();
        command[1] = fixture.getAbsolutePath();
        System.arraycopy(args, 0, command, 2, args.length);
        return new ProcessBuilder(command).redirectErrorStream(true).start();
    }

    private void testNormalExit() throws Exception {
        Process process = launch("exit23");
        try {
            require(awaitExit(process) == 23, "Exit status was not propagated");
            passed++;
        } finally {
            cleanup(process);
        }
    }

    private void testStop(String action, boolean shortLivedThread) throws Exception {
        File lockFile = File.createTempFile("guard-acceptance-", ".lock", getTargetContext().getCacheDir());
        Process process = null;
        try {
            process = shortLivedThread ? launchOnWorker(lockFile) : launch("hold", lockFile.getAbsolutePath());
            awaitLock(lockFile, true);
            require(isAlive(process), "Supervisor exited before stop");
            if ("eof".equals(action)) process.getOutputStream().close();
            else if ("term".equals(action)) process.destroy();
            else if ("kill".equals(action) && Build.VERSION.SDK_INT >= 26) process.destroyForcibly();
            else throw new AssertionError("Unsupported stop action");
            require(awaitExit(process) != 0, "Unexpected successful stop status");
            awaitLock(lockFile, false);
            passed++;
        } finally {
            if (process != null) cleanup(process);
            if (!lockFile.delete() && lockFile.exists()) throw new IOException("Fixture cleanup failed");
        }
    }

    private Process launchOnWorker(File file) throws Exception {
        AtomicReference<Process> process = new AtomicReference<>();
        AtomicReference<Exception> failure = new AtomicReference<>();
        Thread worker = new Thread(() -> {
            try {
                process.set(launch("hold", file.getAbsolutePath()));
            } catch (Exception error) {
                failure.set(error);
            }
        });
        worker.start();
        worker.join(TIMEOUT_MS);
        require(!worker.isAlive(), "Launcher thread failed to finish");
        if (failure.get() != null) throw failure.get();
        return process.get();
    }

    // A separate process holds a real POSIX record lock. File length alone
    // does not prove liveness, and supervisor exit alone does not prove cleanup.
    private void awaitLock(File file, boolean held) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + TIMEOUT_MS;
        do {
            if (file.length() == 1) {
                try (RandomAccessFile access = new RandomAccessFile(file, "rw");
                     FileLock lock = access.getChannel().tryLock()) {
                    if ((lock == null) == held) return;
                }
            }
            SystemClock.sleep(20);
        } while (SystemClock.elapsedRealtime() < deadline);
        throw new AssertionError(held ? "Child never acquired lock" : "Child still owns lock");
    }

    private static boolean isAlive(Process process) {
        try { process.exitValue(); return false; }
        catch (IllegalThreadStateException running) { return true; }
    }

    private static int awaitExit(Process process) {
        long deadline = SystemClock.elapsedRealtime() + TIMEOUT_MS;
        while (isAlive(process) && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20);
        require(!isAlive(process), "Supervisor exit deadline exceeded");
        return process.exitValue();
    }

    private static void cleanup(Process process) throws IOException {
        try {
            process.getOutputStream().close();
        } finally {
            if (isAlive(process)) process.destroy();
            if (isAlive(process) && Build.VERSION.SDK_INT >= 26) process.destroyForcibly();
            awaitExit(process);
            process.getInputStream().close();
            process.getErrorStream().close();
        }
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
