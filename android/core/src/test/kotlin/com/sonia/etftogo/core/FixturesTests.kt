package com.sonia.etftogo.core

import com.sonia.etftogo.core.support.CoreResources
import kotlin.test.Test
import kotlin.test.assertTrue

class FixturesTests {
    @Test fun findsSharedFixtures() {
        assertTrue(Fixtures.root.resolve("official/expected-quotes.json").isFile)
    }

    @Test fun readsBundledCatalog() {
        assertTrue(CoreResources.read("catalog.json").decodeToString().contains("\"0050\""))
    }
}
