package io.github.ccch1mneyyy.dsh_app.runtime

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import org.json.JSONObject

internal fun checkEngineCompatibility(
    baseDir: File,
    raw: JSONObject,
    version: String,
    abi: String,
    onLog: (String) -> Unit = {},
): EngineUpgradeSpec {
    val rootfs = File(baseDir, "rootfs")
    val staging = File(baseDir, "staging")
    if (Files.isSymbolicLink(rootfs.toPath()) || File(baseDir, "home.carry").exists() ||
        File(baseDir, "rootfs.old").exists()) throw RuntimeUpgradeBlocked("legacy_interrupted")
    val next = parseUpgrade(raw)
    val shipped = readRuntimeInfo(staging)
    if (parseUpgrade(shipped) != next || shipped.optString("runtimeVersion") != version) {
        throw RuntimeUpgradeBlocked("manifest")
    }
    val previous = readRuntimeInfo(rootfs)
    if (previous.optString("abi") != abi || shipped.optString("abi") != abi ||
        osIdentity(rootfs) != osIdentity(staging)) throw RuntimeUpgradeBlocked("base")
    if (previous.has("upgrade")) {
        val prior = parseUpgrade(previous)
        if (prior.baseId != next.baseId) {
            // baseId covers the whole Linux system, extra Ubuntu packages included. A
            // routine security refresh of those packages changes it without touching
            // anything this upgrade replaces, so require the system the upgrade keeps to
            // be identical instead of blocking every release: ABI and release are checked
            // above; Python and the C runtime the engine binaries link against are here.
            if (prior.ubuntuVersion != next.ubuntuVersion || !samePython(rootfs, staging) ||
                !sameRuntimeLibraries(rootfs, staging, abi)) throw RuntimeUpgradeBlocked("base")
            onLog("[dsh-app] base identity changed outside the engine paths; " +
                "release, Python and system libraries match, upgrading engine")
        }
    } else {
        // One-time adoption of old bundles. Do not infer compatibility just
        // from rNN or Node versions. Keep Python and all user pip packages.
        if (previous.optString("ubuntuVersion") != next.ubuntuVersion ||
            !samePython(rootfs, staging)) throw RuntimeUpgradeBlocked("base")
    }
    return next
}

private fun readRuntimeInfo(tree: File): JSONObject = try {
    JSONObject(File(tree, "etc/dsh-app/runtime.json").readText())
} catch (_: Exception) {
    throw RuntimeUpgradeBlocked("manifest")
}

private fun parseUpgrade(json: JSONObject): EngineUpgradeSpec = try {
    val upgrade = json.getJSONObject("upgrade")
    if (upgrade.getInt("schema") != 1) throw RuntimeUpgradeBlocked("manifest")
    val paths = upgrade.getJSONArray("paths")
    EngineUpgradeSpec(upgrade.getString("baseId"), upgrade.getString("ubuntuVersion"),
        List(paths.length()) { paths.getString(it) }).also { it.validate() }
} catch (_: Exception) {
    throw RuntimeUpgradeBlocked("manifest")
}

private fun osIdentity(tree: File): List<String> = try {
    val rows = File(tree, "etc/os-release").readLines()
    listOf("ID", "VERSION_ID").map { key ->
        rows.single { it.startsWith("$key=") }.substringAfter('=').trim().trim('"', '\'')
    }
} catch (_: Exception) {
    throw RuntimeUpgradeBlocked("base")
}

/** The C/C++ runtime the bundled Node links against; an engine upgrade never replaces it. */
private val RUNTIME_LIBRARIES = listOf("libc.so.6", "libstdc++.so.6", "libgcc_s.so.1")

private fun sameRuntimeLibraries(old: File, next: File, abi: String): Boolean = try {
    val triple = if (abi == "x86_64") "x86_64-linux-gnu" else "aarch64-linux-gnu"
    RUNTIME_LIBRARIES.all { name ->
        val relative = "usr/lib/$triple/$name"
        digest(File(old, relative)) == digest(File(next, relative))
    }
} catch (_: Exception) { false }

private fun digest(file: File): List<Byte> {
    val hash = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(65536)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            hash.update(buffer, 0, count)
        }
    }
    return hash.digest().toList()
}

private fun samePython(old: File, next: File): Boolean = try {
    digest(File(old, "opt/python/bin/python3")) == digest(File(next, "opt/python/bin/python3"))
} catch (_: Exception) { false }

