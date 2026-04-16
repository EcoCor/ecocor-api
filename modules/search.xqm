xquery version "3.1";

(:~
 : Full-text search for the EcoCor API.
 :
 : Searches the tokenized TEI (`tokenized.xml`) of every text with
 : Lucene's default analyzer, returning paragraph-level hits with KWIC
 : context and links into the DTS Collection / Navigation / Document
 : endpoints.
 :
 : Adapted from the ELTeC search module
 : (https://github.com/clscor-io/eltec-api/blob/main/modules/search.xqm).
 :)
module namespace search = "http://ecocor.org/ns/exist/search";

import module namespace config = "http://ecocor.org/ns/exist/config"
  at "config.xqm";
import module namespace ectei = "http://ecocor.org/ns/exist/tei"
  at "tei.xqm";
import module namespace ecutil = "http://ecocor.org/ns/exist/util"
  at "util.xqm";
import module namespace kwic = "http://exist-db.org/xquery/kwic";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : Public resource id — the tokenized TEI's xml:id with the
 : `_tokenized` suffix stripped. Matches the DTS Resource id convention.
 :)
declare function search:resource-id(
  $tei as element(tei:TEI)
) as xs:string {
  replace(string($tei/@xml:id), '_tokenized$', '')
};

(:~
 : Full-text search across the EcoCor corpora.
 :
 : @param $q Search query (required, Lucene syntax)
 : @param $corpus Optional corpus name to restrict search
 : @param $id Optional resource id (public form, no _tokenized suffix)
 : @param $limit Results per page (default 20)
 : @param $offset Zero-based offset (default 0)
 :)
declare
  %rest:GET
  %rest:path("/ecocor/search")
  %rest:query-param("q", "{$q}")
  %rest:query-param("corpus", "{$corpus}")
  %rest:query-param("id", "{$id}")
  %rest:query-param("limit", "{$limit}")
  %rest:query-param("offset", "{$offset}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function search:search(
  $q as xs:string*,
  $corpus as xs:string*,
  $id as xs:string*,
  $limit as xs:string*,
  $offset as xs:string*
) as item()+ {
  if (not($q) or $q = "") then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map { "error": "Bad Request", "message": "Parameter 'q' is required." }
    )
  else

  let $lim := if ($limit) then xs:integer($limit) else 20
  let $off := if ($offset) then xs:integer($offset) else 0

  let $collection-path :=
    if ($corpus and $corpus != "")
    then $config:corpora-root || "/" || $corpus
    else $config:corpora-root

  return
    if ($corpus and not(xmldb:collection-available($collection-path))) then
      (
        <rest:response><http:response status="404"/></rest:response>,
        map {
          "error": "Not Found",
          "message": "Corpus '" || $corpus || "' does not exist."
        }
      )
    (: restrict to tokenized TEIs; match resource id via _tokenized suffix :)
    else
      let $scope := collection($collection-path)//tei:TEI[@type = "tokenized"]
      let $scope := if ($id)
        then $scope[@xml:id = $id || "_tokenized"]
        else $scope
      return
        if ($id and empty($scope)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map {
              "error": "Not Found",
              "message": "Text '" || $id || "' does not exist."
            }
          )
        else
          let $hits := $scope//tei:p[ft:query(., $q)]
          let $total := count($hits)
          let $page := subsequence($hits, $off + 1, $lim)
          let $dts-base := $config:api-base || "/dts"

          let $results := array {
            for $hit in $page
            let $tei := $hit/ancestor::tei:TEI
            let $resource-id := search:resource-id($tei)
            let $titles := ectei:get-titles($tei)
            let $authors := ectei:get-authors($tei)
            let $paths := ecutil:filepaths(base-uri($tei))
            let $cite-ref := string($hit/@xml:id)
            let $summary := kwic:summarize($hit, <config width="40"/>)
            return map {
              "id": $resource-id,
              "name": $paths?textname,
              "corpus": $paths?corpusname,
              "title": $titles?main,
              "authors": array {
                for $a in $authors return map { "name": $a?name }
              },
              "citableUnit": $cite-ref,
              "kwic": normalize-space(string-join($summary//text(), " ")),
              "collection": $dts-base || "/collection?id=" || $resource-id,
              "navigation": $dts-base || "/navigation?resource=" || $resource-id
                || "&amp;ref=" || $cite-ref,
              "document": $dts-base || "/document?resource=" || $resource-id
                || "&amp;ref=" || $cite-ref
            }
          }

          return map {
            "query": $q,
            "totalHits": $total,
            "offset": $off,
            "limit": $lim,
            "results": $results
          }
};
