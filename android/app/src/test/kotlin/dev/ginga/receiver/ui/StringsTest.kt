package dev.ginga.receiver.ui

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.w3c.dom.Element

/**
 * The UI is Portuguese (Brazil) first and English second: every translatable English string has a
 * Portuguese one with the same format arguments, and no string shows the internal name.
 */
class StringsTest {
    private val mainDir = File(System.getProperty("ginga.appMainDir") ?: "src/main")

    private fun strings(dir: String): Map<String, Element> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File(mainDir, "res/$dir/strings.xml"))
        val nodes = document.getElementsByTagName("string")
        return (0 until nodes.length).map { nodes.item(it) as Element }.associateBy { it.getAttribute("name") }
    }

    private val formatArgument = Regex("%\\d+\\$[sd]")

    @Test
    fun portugueseCoversEveryEnglishString() {
        val english = strings("values").filterValues { it.getAttribute("translatable") != "false" }
        val portuguese = strings("values-pt-rBR")
        assertEquals(english.keys, portuguese.keys, "pt-BR and English must have the same strings")
        for ((name, element) in english) {
            val expected = formatArgument.findAll(element.textContent).map { it.value }.toSortedSet()
            val actual = formatArgument.findAll(portuguese.getValue(name).textContent).map { it.value }.toSortedSet()
            assertEquals(expected, actual, "format arguments of $name")
        }
    }

    @Test
    fun theProductIsGinga() {
        for (dir in listOf("values", "values-pt-rBR")) {
            val all = strings(dir)
            assertEquals("Ginga", all.getValue("app_name").textContent, dir)
        }
    }

    @Test
    fun specsUseTheMultiplicationSign() {
        // brand-book: numbers in mono, "×" and not "x" (2560×1600).
        assertTrue(strings("values").values.none { Regex("\\d+x\\d+").containsMatchIn(it.textContent) })
    }
}
