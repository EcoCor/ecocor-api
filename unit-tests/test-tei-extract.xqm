xquery version "3.1";

(:~
 : Unit tests for the TEI-value extractor functions in
 : `modules/tei.xqm`.
 :
 : These functions are one-XPath-per-value and therefore drift-prone:
 : small changes in the TEI header structure (or to the XPath itself)
 : can silently flip the extracted value. The tests run each function
 : against the in-database fixtures under
 : `/db/apps/ecocor/unit-tests/fixtures/` and pin expected outputs.
 :)
module namespace ttei = "http://ecocor.org/ns/exist/test/tei";

import module namespace ectei = "http://ecocor.org/ns/exist/tei"
  at "../modules/tei.xqm";

declare namespace test = "http://exist-db.org/xquery/xqsuite";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare variable $ttei:fixtures :=
  "/db/apps/ecocor/unit-tests/fixtures";

declare variable $ttei:minimal :=
  doc($ttei:fixtures || "/tei-minimal.xml")/tei:TEI;

declare variable $ttei:years :=
  doc($ttei:fixtures || "/tei-year-variants.xml")/tei:TEI;

(: =====================================================================
 : get-titles: main + sub come from the titleStmt, NEVER from sourceDesc.
 : ===================================================================== :)

declare
  %test:assertEquals("Unit Test Main Title")
function ttei:get-titles-main() as xs:string {
  ectei:get-titles($ttei:minimal)?main
};

declare
  %test:assertEquals("A Subtitle for Testing")
function ttei:get-titles-sub() as xs:string {
  ectei:get-titles($ttei:minimal)?sub
};

(: Regression guard: if the XPath loosens and picks up
 : `<bibl><title>Trap Title — ...</title></bibl>` the main title
 : would change. This assertion fails immediately in that case. :)
declare
  %test:assertTrue
function ttei:get-titles-ignores-bibl-titles() as xs:boolean {
  not(contains(ectei:get-titles($ttei:minimal)?main, "Trap"))
};

(: =====================================================================
 : get-year: four branches (@when, \d{4}, \d{4}-\d{4}, analyze-string).
 : Each date element is labelled with an xml:id in the fixture so we
 : can pick it directly.
 : ===================================================================== :)

declare
  %test:assertEquals("1810")
function ttei:get-year-from-when() as xs:string {
  ectei:get-year($ttei:years//tei:date[@xml:id = "y-when"])
};

declare
  %test:assertEquals("1810")
function ttei:get-year-from-plain-text() as xs:string {
  ectei:get-year($ttei:years//tei:date[@xml:id = "y-plain"])
};

declare
  %test:assertEquals("1795-1796")
function ttei:get-year-from-range-text() as xs:string {
  ectei:get-year($ttei:years//tei:date[@xml:id = "y-range"])
};

declare
  %test:assertEquals("1732")
function ttei:get-year-from-embedded-text() as xs:string {
  ectei:get-year($ttei:years//tei:date[@xml:id = "y-embedded"])
};

(: =====================================================================
 : get-reference-year: priority chain firstEdition > printSource >
 : digitalSource. The fixture provides all three with distinct years
 : so the assertion catches any reorder.
 : ===================================================================== :)

declare
  %test:assertEquals("1795")
function ttei:reference-year-priority-firstedition() as xs:string {
  ectei:get-reference-year($ttei:years)
};

(: =====================================================================
 : get-authors: selects titleStmt/author (not sourceDesc/author),
 : excludes role="illustrator", strips trailing parenthesized content.
 : ===================================================================== :)

declare
  %test:assertEquals(2)
function ttei:authors-count-excludes-illustrator() as xs:integer {
  count(ectei:get-authors($ttei:minimal))
};

declare
  %test:assertEquals("Goethe, Johann Wolfgang von")
function ttei:authors-strip-trailing-dates() as xs:string {
  (ectei:get-authors($ttei:minimal))[1]?name
};

declare
  %test:assertEquals("https://www.wikidata.org/entity/Q1")
function ttei:authors-carry-ref() as xs:string {
  (ectei:get-authors($ttei:minimal))[1]?ref
};

declare
  %test:assertTrue
function ttei:authors-skip-illustrator() as xs:boolean {
  not(
    some $a in ectei:get-authors($ttei:minimal)
    satisfies contains($a?name, "Picasso")
  )
};

(: =====================================================================
 : get-text-paras: only paragraphs with @xml:id; the fixture has 3
 : paragraphs total, 2 with ids, 1 without.
 : ===================================================================== :)

declare
  %test:assertEquals(2)
function ttei:text-paras-requires-id() as xs:integer {
  count(ectei:get-text-paras($ttei:minimal))
};

declare
  %test:assertEquals("p1", "p2")
function ttei:text-paras-returns-ids-in-order() as xs:string+ {
  for $p in ectei:get-text-paras($ttei:minimal)
  return string($p/@xml:id)
};
