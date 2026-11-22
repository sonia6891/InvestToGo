package com.sonia.etftogo.core.support

import kotlinx.serialization.Serializable
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals

class CoreJsonTests {
    @Serializable
    data class Sample(
        @Serializable(with = SwiftDateSerializer::class) val at: Instant,
        @Serializable(with = UppercaseUUIDSerializer::class) val id: UUID,
        val note: String? = null,
    )

    @Test fun datesAreSecondsSince2001LikeSwift() {
        val text = CoreJson.json.encodeToString(Sample.serializer(), Sample(Instant.parse("2001-01-01T00:01:00Z"), UUID(0, 0)))
        assertEquals("""{"at":60.0,"id":"00000000-0000-0000-0000-000000000000"}""", text)
    }

    @Test fun uuidIsUppercaseAndReadsEitherCase() {
        val id = UUID.fromString("5fef0885-6a6b-555c-8bec-451862548983")
        val text = CoreJson.json.encodeToString(Sample.serializer(), Sample(Instant.parse("2001-01-01T00:00:00Z"), id))
        assertEquals("""{"at":0.0,"id":"5FEF0885-6A6B-555C-8BEC-451862548983"}""", text)
        assertEquals(id, CoreJson.json.decodeFromString(Sample.serializer(), """{"at":0,"id":"5fef0885-6a6b-555c-8bec-451862548983"}""").id)
    }

    @Serializable
    data class Shape(val count: Int, val on: Boolean, val name: String, val list: List<Double> = emptyList())

    @Test fun typesAreNotConvertedLikeSwift() {
        CoreJson.decode(Shape.serializer(), """{"count":1,"on":true,"name":"a","list":[1,2.5]}""")
        for (bad in listOf("""{"count":"1","on":true,"name":"a"}""", """{"count":1,"on":"true","name":"a"}""",
                "{\"count\":1,\"on\":true,\"name\":5}", """{"count":1,"on":true,"name":"a","list":["1"]}""")) {
            kotlin.test.assertFailsWith<kotlinx.serialization.SerializationException>(bad) { CoreJson.decode(Shape.serializer(), bad) }
        }
    }

    @Test fun fractionalSecondsSurvive() {
        val back = CoreJson.json.decodeFromString(Sample.serializer(), """{"at":1.5,"id":"00000000-0000-0000-0000-000000000000","extra":1}""")
        assertEquals(Instant.parse("2001-01-01T00:00:01.500Z"), back.at)
    }
}
