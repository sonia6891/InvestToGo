package com.sonia.etftogo.core.support

import java.util.regex.Pattern

private const val UNICODE_SPACE = "[\\t\\n\\x0B\\f\\r\\x{85}\\p{Z}]"
private const val NOT_UNICODE_SPACE = "[^\\t\\n\\x0B\\f\\r\\x{85}\\p{Z}]"

/**
 * A pattern iPhone writes for NSRegularExpression (ICU), compiled so it means the same on the test JVM and on Android:
 * `\s`, `\S`, `\d` and `\D` are written out as their Unicode classes and the Han script as `\p{script=Han}`. Android's
 * regex is ICU but refuses the JVM's Unicode-class flag, so that flag is never used. `\b` is Unicode-aware on both.
 */
fun icuPattern(pattern: String, flags: Int = 0): Pattern {
    val out = StringBuilder()
    var i = 0
    while (i < pattern.length) {
        val c = pattern[i]
        if (c == '\\' && i + 1 < pattern.length) {
            when (pattern[i + 1]) {
                's' -> { out.append(UNICODE_SPACE); i += 2; continue }
                'S' -> { out.append(NOT_UNICODE_SPACE); i += 2; continue }
                'd' -> { out.append("\\p{Nd}"); i += 2; continue }
                'D' -> { out.append("\\P{Nd}"); i += 2; continue }
            }
            if (pattern.startsWith("\\p{Han}", i)) { out.append("\\p{script=Han}"); i += "\\p{Han}".length; continue }
            out.append(c).append(pattern[i + 1]); i += 2; continue
        }
        out.append(c); i += 1
    }
    return Pattern.compile(out.toString(), flags)
}
