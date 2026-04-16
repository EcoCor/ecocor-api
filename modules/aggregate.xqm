xquery version "3.1";

(:~
 : Aggregate / summary endpoints for the EcoCor API.
 :
 : Computed views over annotation layers. Distinct from the raw
 : per-layer endpoints (which stream annotations as-stored) and from
 : /search (which returns hits). This module returns grouped,
 : summarised data for "what's in the corpus?" questions.
 :)
module namespace aggregate = "http://ecocor.org/ns/exist/aggregate";

import module namespace config = "http://ecocor.org/ns/exist/config"
  at "config.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : Strip the leading # and return clean category key.
 :)
declare function aggregate:clean-ref(
  $ref as xs:string?
) as xs:string? {
  if ($ref) then replace($ref, '^#', '') else ()
};

(:~
 : Resolve a token id to its surface text from the tokenized TEI
 : of the containing text. Empty string if not found.
 :)
declare function aggregate:token-text(
  $tokenized as element(tei:TEI)?,
  $token-id as xs:string
) as xs:string {
  if (not($tokenized)) then ""
  else
    let $t := $tokenized//*[@xml:id = $token-id][
      local-name(.) = ("w", "pc")
    ]
    return if ($t) then string($t) else ""
};

(:~
 : Look up the lemma for a token via the linguistic layer if present.
 : Returns empty string when no linguistic layer / no lemma found.
 :)
declare function aggregate:token-lemma(
  $linguistic as element(tei:TEI)?,
  $token-id as xs:string
) as xs:string {
  if (not($linguistic)) then ""
  else
    let $target-ref := "#" || $token-id
    let $note := (
      $linguistic//tei:annotation[
        tokenize(@target, '\s+') = $target-ref
      ]/tei:note[@type = "lemma"]
    )[1]
    return if ($note) then normalize-space($note) else ""
};

(:~
 : Build the grouping key for one token of an annotation.
 :
 : Precedence:
 :   groupBy=lemma (default)  → lemma if present, else lowercase surface
 :   groupBy=surface          → lowercase surface
 :   groupBy=wikidata         → @corresp, else "" (excluded)
 :)
declare function aggregate:group-key(
  $surface as xs:string,
  $lemma as xs:string,
  $corresp as xs:string?,
  $groupBy as xs:string
) as xs:string {
  if ($groupBy = "wikidata") then
    if ($corresp) then $corresp else ""
  else if ($groupBy = "surface") then
    lower-case($surface)
  else
    if ($lemma) then $lemma else lower-case($surface)
};

(:~
 : Aggregated entity view for a corpus (or a single text within a
 : corpus). Groups entity annotations by lemma / surface / wikidata
 : and returns one row per distinct key.
 :
 : @param $corpus Corpus name (required)
 : @param $id Optional resource id (restrict to one text)
 : @param $category Optional category filter (@ana without leading #)
 : @param $groupBy "lemma" (default) | "surface" | "wikidata"
 : @param $limit Results per page (default 50)
 : @param $offset Zero-based offset (default 0)
 :)
declare
  %rest:GET
  %rest:path("/ecocor/aggregate/entities")
  %rest:query-param("corpus", "{$corpus}")
  %rest:query-param("id", "{$id}")
  %rest:query-param("category", "{$category}")
  %rest:query-param("groupBy", "{$groupBy}", "lemma")
  %rest:query-param("limit", "{$limit}")
  %rest:query-param("offset", "{$offset}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function aggregate:entities(
  $corpus, $id, $category, $groupBy, $limit, $offset
) {
  if (not($corpus) or $corpus = "") then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameter 'corpus' is required."
      }
    )
  else if (not($groupBy = ("lemma", "surface", "wikidata"))) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameter 'groupBy' must be 'lemma', 'surface', or 'wikidata'."
      }
    )
  else

  let $corpus-path := $config:corpora-root || "/" || $corpus
  return
    if (not(xmldb:collection-available($corpus-path))) then
      (
        <rest:response><http:response status="404"/></rest:response>,
        map {
          "error": "Not Found",
          "message": "Corpus '" || $corpus || "' does not exist."
        }
      )
    else
      let $lim := if ($limit) then xs:integer($limit) else 50
      let $off := if ($offset) then xs:integer($offset) else 0

      (: Scope to one text if `id` given :)
      let $text-scope :=
        if ($id) then
          let $tei := (
            collection($corpus-path)//tei:TEI[
              @type = "tokenized" and @xml:id = $id || "_tokenized"
            ]
          )[1]
          return
            if ($tei) then
              let $segs := tokenize(base-uri($tei), '/')
              return $corpus-path || "/" || $segs[last() - 1]
            else ()
        else $corpus-path

      return
        if ($id and empty($text-scope)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map {
              "error": "Not Found",
              "message": "Text '" || $id || "' does not exist."
            }
          )
        else
          (: Every entity-type layer file in scope :)
          let $entity-layers :=
            collection($text-scope)/tei:TEI[
              .//tei:listAnnotation/@type = "entities"
            ]

          (: Unfold to per-mention rows. One row per (annotation, token-id). :)
          let $rows :=
            for $layer-tei in $entity-layers
            let $layer-file :=
              tokenize(base-uri($layer-tei), '/')[last()]
            let $layer-name := replace($layer-file, '\.xml$', '')
            let $text-collection :=
              string-join(
                tokenize(base-uri($layer-tei), '/')[position() < (last() - 1)],
                '/'
              )
            let $tokenized :=
              (doc($text-collection || "/tokenized.xml")/tei:TEI)[1]
            let $linguistic :=
              (doc($text-collection || "/annotations/linguistic.xml")/tei:TEI)[1]
            let $resource-id :=
              if ($tokenized) then
                replace(string($tokenized/@xml:id), '_tokenized$', '')
              else ""
            for $a in $layer-tei//tei:annotation
            let $cat := aggregate:clean-ref($a/@ana)
            where not($category) or $cat = $category
            for $tref in tokenize(string($a/@target), '\s+')
            let $token-id := replace($tref, '^#', '')
            let $surface := aggregate:token-text($tokenized, $token-id)
            let $lemma := aggregate:token-lemma($linguistic, $token-id)
            let $corresp := string($a/@corresp)
            let $key := aggregate:group-key(
              $surface, $lemma, $corresp, $groupBy
            )
            where $key != ""
            return map {
              "key": $key,
              "surface": $surface,
              "lemma": $lemma,
              "category": $cat,
              "corresp": $corresp,
              "layer": $layer-name,
              "resource": $resource-id
            }

          (: Group by key :)
          let $grouped :=
            for $row in $rows
            group by $k := $row?key
            let $surfaces := distinct-values($row?surface[. != ""])
            let $categories := distinct-values($row?category[. != ""])
            let $wikidata := distinct-values($row?corresp[. != ""])
            let $layers := distinct-values($row?layer)
            let $texts := distinct-values($row?resource[. != ""])
            let $count := count($row)
            order by $count descending, $k
            return map {
              "key": $k,
              "mentionCount": $count,
              "textCount": count($texts),
              "surfaceForms": array { $surfaces },
              "categories": array { $categories },
              "wikidataIds": array { $wikidata },
              "layers": array { $layers }
            }

          let $total := count($grouped)
          let $page := subsequence($grouped, $off + 1, $lim)

          return map:merge((
            map {
              "scope": map:merge((
                map:entry("corpus", $corpus),
                if ($id) then map:entry("id", $id) else ()
              )),
              "groupBy": $groupBy,
              "category": if ($category) then $category else (),
              "totalMentions": sum($grouped ! .?mentionCount),
              "distinctEntities": $total,
              "offset": $off,
              "limit": $lim,
              "entities": array { $page }
            }
          ))
};
