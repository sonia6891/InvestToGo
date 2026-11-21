package com.sonia.etftogo.core

import kotlinx.serialization.json.JsonNull

/** Every shared vector kind Kotlin answers, keyed by the vector's `kind` (the Swift side is `vectorHandlers`). */
val vectorHandlers: Map<String, VectorHandler> = mapOf(
    "Vector.echo" to { input -> VectorIO.obj(input)["value"] ?: JsonNull },
)
