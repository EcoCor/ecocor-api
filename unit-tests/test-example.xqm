xquery version "3.1";

(:~
 : A minimal xqsuite test module that proves the wiring works.
 :
 : Run the whole suite against a single test module with:
 :
 :   curl -s -u admin: --data-urlencode "_query=
 :     import module namespace test = 'http://exist-db.org/xquery/xqsuite'
 :       at 'resource:org/exist/xquery/lib/xqsuite/xqsuite.xql';
 :     test:suite(inspect:module-functions(
 :       xs:anyURI('xmldb:exist:///db/apps/ecocor/unit-tests/test-example.xqm')))
 :   " http://localhost:8090/exist/rest/db/
 :
 : The higher-level `make xqsuite` target loads every *.xqm file under
 : `unit-tests/` and runs them.
 :)
module namespace ex = "http://ecocor.org/ns/exist/test/example";

declare namespace test = "http://exist-db.org/xquery/xqsuite";

(:~
 : Sanity: arithmetic still works. If this ever fails, XQuery itself
 : is broken and the rest of the suite is meaningless.
 :)
declare
  %test:assertEquals("2")
function ex:arithmetic-sanity() as xs:string {
  string(1 + 1)
};

(:~
 : Verify that xqsuite's `assertEquals` matches on sequences, not just
 : strings — confirms the multi-arg assertion pattern works in this
 : build.
 :)
declare
  %test:assertEquals("a", "b", "c")
function ex:sequence-assertion() as xs:string+ {
  ("a", "b", "c")
};
