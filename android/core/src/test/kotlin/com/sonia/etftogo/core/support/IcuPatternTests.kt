package com.sonia.etftogo.core.support

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * iPhone's patterns run on ICU, where `\s`, `\d` and `\p{Han}` are Unicode-aware. Android's java.util.regex is ICU too but
 * refuses Pattern.UNICODE_CHARACTER_CLASS, and the test JVM spells the Han script differently, so [icuPattern] writes the
 * Unicode classes out in a form both runtimes read.
 */
class IcuPatternTests {
    @Test fun unicodeClassesMatchLikeICU() {
        assertTrue(icuPattern("^\\s+$").matcher("　 \t\n\u0085").matches(), "Ideographic and no-break spaces are spaces")
        assertTrue(icuPattern("^\\d+$").matcher("２０２６").matches(), "Full-width digits are digits")
        assertTrue(icuPattern("^\\p{Han}+$").matcher("台積電").matches())
        assertTrue(icuPattern("[\\s,]").matcher("　").find(), "Inside a bracket too")
        assertEquals(false, icuPattern("^\\s$").matcher("x").matches())
    }

    /** Android throws "Unsupported flags" for UNICODE_CHARACTER_CLASS, and \p{IsHan} is the JVM's own spelling. */
    @Test fun mainSourcesUseOnlyPatternsAndroidAccepts() {
        val root = generateSequence(File("").absoluteFile) { it.parentFile }.map { File(it, "core/src/main/kotlin") }.first { it.isDirectory }
        val offenders = root.walkTopDown().filter { it.extension == "kt" }.flatMap { file ->
            file.readLines().mapIndexedNotNull { i, line ->
                if ("UNICODE_CHARACTER_CLASS" in line || "\\\\p{Is" in line) "${file.name}:${i + 1}" else null
            }
        }.filterNot { it.startsWith("IcuPattern.kt") }.toList()
        assertTrue(offenders.isEmpty(), "Compile with icuPattern(...) instead: ${offenders.joinToString()}")
    }
}
