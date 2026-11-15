package io.github.ccch1mneyyy.dsh_app.runtime

import io.github.ccch1mneyyy.dsh_app.files.GuestFiles
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import org.json.JSONObject

internal fun checkEngineCompatibility(
    baseDir: File, raw: JSONObject, version: String, abi: String,
    payloadTree: File = File(baseDir, "staging"),
): EngineUpgradeSpec {
    val rootfs = File(baseDir, "rootfs")
    if (Files.isSymbolicLink(rootfs.toPath()) || File(baseDir, "home.carry").exists()) {
        throw RuntimeUpgradeBlocked("legacy_interrupted")
    }
    val next = parseUpgrade(raw)
    val shipped = readRuntimeInfo(payloadTree)
    if (parseUpgrade(shipped) != next || shipped.optString("runtimeVersion") != version) {
        throw RuntimeUpgradeBlocked("manifest")
    }
    val base = if (raw.optInt("schema", 1) == 2) {
        parseBaseCompatibility(raw).also {
            if (parseBaseCompatibility(shipped) != it) throw RuntimeUpgradeBlocked("manifest")
        }
    } else null
    val previous = readRuntimeInfo(rootfs)
    if (File(baseDir, "rootfs.old").exists()) {
        // Legacy activation wrote this marker after restoring home and syncing data,
        // before deleting rootfs.old. A matching marker leaves only retired-tree cleanup.
        val committed = runCatching { File(baseDir, "rootfs.version").readText() }.getOrNull()
        if (committed.isNullOrEmpty() || committed != previous.optString("runtimeVersion")) {
            throw RuntimeUpgradeBlocked("legacy_interrupted")
        }
        File(baseDir, "rootfs.old").deleteRecursivelySafely()
    }
    if (previous.optString("abi") != abi || shipped.optString("abi") != abi ||
        osIdentity(rootfs) != (base?.osRelease ?: osIdentity(payloadTree))) throw RuntimeUpgradeBlocked("base")
    if (previous.has("upgrade")) {
        val prior = parseUpgrade(previous)
        if (prior.baseId != next.baseId) {
            // baseId 覆盖整个 Linux 系统，apt 装的额外包也算在内。一次日常安全更新就会改它，
            // 却不碰这次升级保留的任何路径；所以不因为 baseId 变了就拦住升级，改为要求
            // 「升级保留的系统部分一致」：ABI 与发行版上面已校验，这里再比 Python 和
            // 引擎二进制链接的系统库（libc / libstdc++ / libgcc_s）。
            if (prior.ubuntuVersion != next.ubuntuVersion || !samePython(rootfs, payloadTree) ||
                !sameRuntimeLibraries(rootfs, payloadTree, abi)) throw RuntimeUpgradeBlocked("base")
        }
    } else {
        // One-time adoption of old bundles. Do not infer compatibility just
        // from rNN or Node versions. Keep Python and all user pip packages.
        if (previous.optString("ubuntuVersion") != next.ubuntuVersion ||
            !(if (base != null) matchesPython(rootfs, base.python3Sha256) else samePython(rootfs, payloadTree))) {
            throw RuntimeUpgradeBlocked("base")
        }
    }
    return next
}

/** Both layers have been extracted; verify their shared base identity before the first activation. */
internal fun checkLayeredFirstInstall(tree: File, raw: JSONObject, version: String, abi: String) {
    val shipped = readRuntimeInfo(tree)
    if (parseUpgrade(shipped) != parseUpgrade(raw) || shipped.optString("runtimeVersion") != version) {
        throw RuntimeUpgradeBlocked("manifest")
    }
    val base = parseBaseCompatibility(raw)
    if (parseBaseCompatibility(shipped) != base) throw RuntimeUpgradeBlocked("manifest")
    if (shipped.optString("abi") != abi || osIdentity(tree) != base.osRelease) {
        throw RuntimeUpgradeBlocked("base")
    }
    val pythonMatches = if (base.python3Sha256 != null) matchesPython(tree, base.python3Sha256)
        else !Files.exists(File(tree, "opt/python/bin/python3").toPath(), java.nio.file.LinkOption.NOFOLLOW_LINKS)
    if (!pythonMatches) throw RuntimeUpgradeBlocked("base")
}

private data class BaseCompatibility(val osRelease: List<String>, val python3Sha256: String?)

private fun parseBaseCompatibility(raw: JSONObject): BaseCompatibility = try {
    val base = raw.getJSONObject("baseCompatibility")
    if (base.getInt("schema") != 1 || !base.has("python3Sha256")) throw RuntimeUpgradeBlocked("manifest")
    val os = base.getJSONObject("osRelease")
    val python = if (base.isNull("python3Sha256")) null else base.getString("python3Sha256")
    if (python != null && !python.matches(Regex("[0-9a-f]{64}"))) throw RuntimeUpgradeBlocked("manifest")
    BaseCompatibility(listOf(os.getString("ID"), os.getString("VERSION_ID")), python)
} catch (_: Exception) {
    throw RuntimeUpgradeBlocked("manifest")
}

private fun readRuntimeInfo(tree: File): JSONObject = try {
    // An existing image may still hold a tawc backup token before any new launch.
    val file = File(tree, "etc/dsh-app/runtime.json").takeIf { it.isFile }
        ?: GuestFiles.resolve(tree, "/etc/dsh-app/runtime.json", PhoneStorage.GUEST_PATH)
        ?: throw RuntimeUpgradeBlocked("manifest")
    JSONObject(file.readText())
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
    val file = File(tree, "etc/os-release").takeIf { it.isFile }
        ?: io.github.ccch1mneyyy.dsh_app.files.GuestFiles.resolve(
            tree, "/etc/os-release", PhoneStorage.GUEST_PATH,
        )
        ?: throw RuntimeUpgradeBlocked("base")
    val rows = file.readLines()
    listOf("ID", "VERSION_ID").map { key ->
        rows.single { it.startsWith("$key=") }.substringAfter('=').trim().trim('"', '\'')
    }
} catch (_: Exception) {
    throw RuntimeUpgradeBlocked("base")
}

private fun pythonDigest(tree: File): List<Byte> {
    val hash = MessageDigest.getInstance("SHA-256")
    File(tree, "opt/python/bin/python3").inputStream().use { input ->
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
    pythonDigest(old) == pythonDigest(next)
} catch (_: Exception) { false }

private fun matchesPython(tree: File, expected: String?): Boolean = try {
    expected != null && pythonDigest(tree).joinToString("") { "%02x".format(it) } == expected
} catch (_: Exception) { false }

/// 引擎二进制直接链接的系统库；apt 刷新它们会改 baseId，但只要内容一致就不影响升级。
private val runtimeLibraries = listOf("libc.so.6", "libstdc++.so.6", "libgcc_s.so.1")

private fun sameRuntimeLibraries(old: File, next: File, abi: String): Boolean = try {
    val triple = if (abi == "x86_64") "x86_64-linux-gnu" else "aarch64-linux-gnu"
    runtimeLibraries.all { name ->
        val relative = "usr/lib/$triple/$name"
        fileDigest(File(old, relative)) == fileDigest(File(next, relative))
    }
} catch (_: Exception) { false }

private fun fileDigest(file: File): List<Byte> {
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

