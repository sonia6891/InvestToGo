package com.sonia.etftogo.core.support

/** PocketCore's `AppDataError`: a failure whose text is shown to the person as is. */
class AppDataError(val text: String) : Exception(text)
