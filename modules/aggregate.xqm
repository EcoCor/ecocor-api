xquery version "3.1";

(:~
 : Aggregate / summary endpoints for the EcoCor API.
 :
 : Pre-computed, per-text summaries of annotation data. Computation is
 : triggered by POST (admin); reads are served from the cached XML
 : store at `{corpus}/{text}/aggregates/entities.xml`.
 :
 : Corpus-wide GET reads all per-text caches and merges them at query
 : time — that merge is cheap because each per-text aggregate is small
 : compared to the raw annotations it was computed from.
 :)
module namespace aggregate = "http://ecocor.org/ns/exist/aggregate";

import module namespace config = "http://ecocor.org/ns/exist/config"
  at "config.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: ========================================================================
 : Helpers
 : ======================================================================== :)

(:~
 : Token-id → surface map. O(1) lookups inside a text.
 :)
declare function aggregate:build-token-map(
  $tokenized as element(tei:TEI)?
) as map(*) {
  if (not($tokenized)) then map {}
  else map:merge(
    for $t in $tokenized//tei:text//(tei:w|tei:pc)[@xml:id]
    return map:entry(string($t/@xml:id), string($t))
  )
};

(:~
 : Token-id → lemma map, from the linguistic annotation layer.
 :)
declare function aggregate:build-lemma-map(
  $linguistic as element(tei:TEI)?
) as map(*) {
  if (not($linguistic)) then map {}
  else map:merge(
    for $a in $linguistic//tei:annotation
    let $lemma := normalize-space($a/tei:note[@type = "lemma"])
    where $lemma != ""
    for $tref in tokenize(string($a/@target), '\s+')
    let $tid := replace($tref, '^#', '')
    where $tid != ""
    return map:entry($tid, $lemma)
  )
};

(:~
 : Grouping key: lemma (fallback lowercase surface) | surface | wikidata.
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
 : Map a TEI xml:id (internal form `..._tokenized`) to the public
 : resource id used in the API.
 :)
declare function aggregate:resource-id(
  $tokenized as element(tei:TEI)
) as xs:string {
  replace(string($tokenized/@xml:id), '_tokenized$', '')
};

(:~
 : Locate the tokenized TEI for one text in a corpus.
 :)
declare function aggregate:tokenized-for(
  $corpus as xs:string,
  $resource-id as xs:string
) as element(tei:TEI)? {
  (
    collection($config:corpora-root || "/" || $corpus)//tei:TEI[
      @type = "tokenized" and @xml:id = $resource-id || "_tokenized"
    ]
  )[1]
};

(: ========================================================================
 : Per-text entity aggregation
 : ======================================================================== :)

(:~
 : Compute the per-text entity aggregation and return it as XML.
 : Groups by lemma (canonical), stored form; other groupBy modes are
 : applied on read.
 :)
declare function aggregate:compute-entities(
  $tokenized as element(tei:TEI)
) as element(aggregate) {
  let $segs := tokenize(base-uri($tokenized), '/')
  let $text-collection := string-join($segs[position() < last()], '/')
  let $resource-id := aggregate:resource-id($tokenized)
  let $token-map := aggregate:build-token-map($tokenized)
  let $linguistic := (
    doc($text-collection || "/annotations/linguistic.xml")/tei:TEI
  )[1]
  let $lemma-map := aggregate:build-lemma-map($linguistic)

  let $ann-collection := $text-collection || "/annotations"
  let $entity-layers :=
    if (xmldb:collection-available($ann-collection)) then
      collection($ann-collection)/tei:TEI[
        .//tei:listAnnotation/@type = "entities"
      ]
    else ()

  let $rows :=
    for $layer-tei in $entity-layers
    let $layer-file := tokenize(base-uri($layer-tei), '/')[last()]
    let $layer-name := replace($layer-file, '\.xml$', '')
    for $a in $layer-tei//tei:annotation
    let $cat := replace(string($a/@ana), '^#', '')
    let $corresp := string($a/@corresp)
    for $tref in tokenize(string($a/@target), '\s+')
    let $tid := replace($tref, '^#', '')
    let $surface := ($token-map($tid), "")[1]
    let $lemma := ($lemma-map($tid), "")[1]
    let $key := if ($lemma) then $lemma else lower-case($surface)
    where $key != ""
    return map {
      "key": $key,
      "surface": $surface,
      "lemma": $lemma,
      "category": $cat,
      "corresp": $corresp,
      "layer": $layer-name
    }

  let $entities :=
    for $row in $rows
    group by $k := $row?key
    let $count := count($row)
    let $surfaces := distinct-values($row?surface[. != ""])
    let $categories := distinct-values($row?category[. != ""])
    let $wikidatas := distinct-values($row?corresp[. != ""])
    let $layers := distinct-values($row?layer)
    order by $count descending, $k
    return
      <entity key="{ $k }" mentionCount="{ $count }">
        <surfaceForms>
          { for $s in $surfaces return <form>{ $s }</form> }
        </surfaceForms>
        <categories>
          { for $c in $categories return <category>{ $c }</category> }
        </categories>
        <wikidataIds>
          { for $w in $wikidatas return <id>{ $w }</id> }
        </wikidataIds>
        <layers>
          { for $l in $layers return <layer>{ $l }</layer> }
        </layers>
      </entity>

  return
    <aggregate
      type="entities"
      resource="{ $resource-id }"
      computed="{ current-dateTime() }"
      totalMentions="{ count($rows) }"
      distinctEntities="{ count($entities) }">
      { $entities }
    </aggregate>
};

(:~
 : Store the XML aggregate under {text}/aggregates/entities.xml.
 :)
declare function aggregate:store-entities(
  $corpus as xs:string,
  $resource-id as xs:string,
  $xml as element(aggregate)
) as xs:string? {
  let $segs := tokenize(base-uri(aggregate:tokenized-for($corpus, $resource-id)), '/')
  let $text-col := string-join($segs[position() < last()], '/')
  let $ann-col := $text-col || "/aggregates"
  let $_ := if (not(xmldb:collection-available($ann-col)))
    then xmldb:create-collection($text-col, "aggregates")
    else ()
  return xmldb:store($ann-col, "entities.xml", $xml)
};

(:~
 : Find the per-text aggregate element for a resource id. Scans only
 : aggregate root elements (not TEI documents), so it stays fast even
 : across a full corpus.
 :)
declare function aggregate:cache-for(
  $corpus as xs:string,
  $resource-id as xs:string
) as element(aggregate)? {
  let $corpus-path := $config:corpora-root || "/" || $corpus
  return (
    collection($corpus-path)/aggregate[
      @type = "entities" and @resource = $resource-id
    ]
  )[1]
};

(:~
 : Convert the stored <aggregate> XML to the response map for one
 : text. Applies filter and paging.
 :)
declare function aggregate:xml-to-map(
  $xml as element(aggregate),
  $corpus as xs:string,
  $category as xs:string*,
  $off as xs:integer,
  $lim as xs:integer
) as map(*) {
  let $all := $xml/entity
  let $filtered := if ($category) then
    $all[categories/category = $category]
  else $all
  let $total := count($filtered)
  let $page := subsequence($filtered, $off + 1, $lim)
  let $total-mentions := sum($filtered/xs:integer(@mentionCount))
  return map {
    "scope": map {
      "corpus": $corpus,
      "id": $xml/@resource/string()
    },
    "groupBy": "lemma",
    "computed": $xml/@computed/string(),
    "totalMentions": $total-mentions,
    "distinctEntities": $total,
    "offset": $off,
    "limit": $lim,
    "entities": array {
      for $e in $page
      return map {
        "key": $e/@key/string(),
        "mentionCount": xs:integer($e/@mentionCount),
        "textCount": 1,
        "texts": array { $xml/@resource/string() },
        "surfaceForms": array { $e/surfaceForms/form/string() },
        "categories": array { $e/categories/category/string() },
        "wikidataIds": array { $e/wikidataIds/id/string() },
        "layers": array { $e/layers/layer/string() }
      }
    }
  }
};

(:~
 : Merge per-text <aggregate> elements into a single response map.
 :)
declare function aggregate:merge-aggregates(
  $xmls as element(aggregate)*,
  $corpus as xs:string,
  $category as xs:string*,
  $off as xs:integer,
  $lim as xs:integer
) as map(*) {
  let $rows :=
    for $xml in $xmls
    let $resource := $xml/@resource/string()
    for $e in $xml/entity
    let $ecategories := $e/categories/category/string()
    where not($category) or $category = $ecategories
    return map {
      "key": $e/@key/string(),
      "resource": $resource,
      "mentionCount": xs:integer($e/@mentionCount),
      "surfaces": $e/surfaceForms/form/string(),
      "categories": $ecategories,
      "wikidatas": $e/wikidataIds/id/string(),
      "layers": $e/layers/layer/string()
    }

  let $merged :=
    for $row in $rows
    group by $k := $row?key
    let $count := sum($row ! .?mentionCount)
    let $resources := distinct-values($row ! .?resource)
    let $surfaces := distinct-values($row ! .?surfaces)
    let $cats := distinct-values($row ! .?categories)
    let $wikis := distinct-values($row ! .?wikidatas)
    let $layers := distinct-values($row ! .?layers)
    order by $count descending, $k
    return map {
      "key": $k,
      "mentionCount": $count,
      "textCount": count($resources),
      "texts": array { $resources },
      "surfaceForms": array { $surfaces },
      "categories": array { $cats },
      "wikidataIds": array { $wikis },
      "layers": array { $layers }
    }

  let $total := count($merged)
  let $page := subsequence($merged, $off + 1, $lim)
  return map {
    "scope": map { "corpus": $corpus },
    "groupBy": "lemma",
    "totalMentions": sum($merged ! .?mentionCount),
    "distinctEntities": $total,
    "offset": $off,
    "limit": $lim,
    "entities": array { $page }
  }
};

(: ========================================================================
 : Endpoints
 : ======================================================================== :)

(:~
 : Read the precomputed entity aggregate.
 :
 : @param $corpus (required)
 : @param $id Restrict to one text
 : @param $category Filter by category (@ana without #)
 : @param $limit (default 50)
 : @param $offset (default 0)
 :)
declare
  %rest:GET
  %rest:path("/ecocor/aggregate/entities")
  %rest:query-param("corpus", "{$corpus}")
  %rest:query-param("id", "{$id}")
  %rest:query-param("category", "{$category}")
  %rest:query-param("limit", "{$limit}")
  %rest:query-param("offset", "{$offset}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function aggregate:get-entities(
  $corpus, $id, $category, $limit, $offset
) {
  if (not($corpus) or $corpus = "") then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameter 'corpus' is required."
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
        return
          if ($id) then
            let $cache := aggregate:cache-for($corpus, $id)
            return
              if (empty($cache)) then
                (
                  <rest:response><http:response status="404"/></rest:response>,
                  map {
                    "error": "Not Found",
                    "message": "No aggregate cached for '" || $id
                      || "'. POST to this endpoint to compute first."
                  }
                )
              else
                aggregate:xml-to-map($cache, $corpus, $category, $off, $lim)
          else
            let $xmls :=
              collection($corpus-path)/aggregate[@type = "entities"]
            return
              if (empty($xmls)) then
                (
                  <rest:response><http:response status="404"/></rest:response>,
                  map {
                    "error": "Not Found",
                    "message": "No aggregates cached for corpus '"
                      || $corpus || "'. POST to compute first."
                  }
                )
              else
                aggregate:merge-aggregates(
                  $xmls, $corpus, $category, $off, $lim
                )
};

(:~
 : Trigger computation of entity aggregates.
 :
 : Without `id`, computes every text in the corpus that has an
 : entity-type annotation layer. With `id`, computes one text.
 : Stores the result at {corpus}/{text}/aggregates/entities.xml.
 :
 : Requires authorization.
 :)
declare
  %rest:POST
  %rest:path("/ecocor/aggregate/entities")
  %rest:query-param("corpus", "{$corpus}")
  %rest:query-param("id", "{$id}")
  %rest:header-param("Authorization", "{$auth}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function aggregate:post-entities(
  $corpus, $id, $auth
) {
  if (not($auth)) then
    (
      <rest:response><http:response status="401"/></rest:response>,
      map { "message": "authorization required" }
    )
  else if (not($corpus) or $corpus = "") then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameter 'corpus' is required."
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
        let $teis :=
          if ($id) then
            let $t := aggregate:tokenized-for($corpus, $id)
            return
              if ($t) then $t else ()
          else
            collection($corpus-path)//tei:TEI[@type = "tokenized"]
        return
          if ($id and empty($teis)) then
            (
              <rest:response><http:response status="404"/></rest:response>,
              map {
                "error": "Not Found",
                "message": "Text '" || $id || "' does not exist."
              }
            )
          else
            let $results :=
              for $tei in $teis
              let $rid := aggregate:resource-id($tei)
              let $xml := aggregate:compute-entities($tei)
              let $stored := aggregate:store-entities($corpus, $rid, $xml)
              return map {
                "id": $rid,
                "distinctEntities":
                  xs:integer($xml/@distinctEntities),
                "totalMentions":
                  xs:integer($xml/@totalMentions),
                "stored": $stored
              }
            return (
              <rest:response><http:response status="201"/></rest:response>,
              map {
                "message": "aggregate computed",
                "computed": current-dateTime(),
                "textCount": count($results),
                "results": array { $results }
              }
            )
};
