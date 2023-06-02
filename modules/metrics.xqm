xquery version "3.1";

(:~
 : Module for calculating and updating corpus metrics.
 :)
module namespace metrics = "http://ecocor.org/ns/exist/metrics";

import module namespace config = "http://ecocor.org/ns/exist/config" at "config.xqm";
import module namespace dutil = "http://ecocor.org/ns/exist/util" at "util.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: Separator for word count tokenization :)
declare variable $metrics:separator := "\W+";

(:~
 : Count words in tei:text of a TEI document
 :
 : @param $tei TEI document
:)
declare function metrics:word-count($tei as element(tei:TEI)) {
  count(tokenize($tei//tei:text[1], $metrics:separator))
};

(:~
 : Calculate metrics for single text
 :
 : @param $url URL of the TEI document
:)
declare function metrics:calculate($url as xs:string) {
  let $tei := doc($url)/tei:TEI
  let $word-count := metrics:word-count($tei)
  return
  <metrics updated="{current-dateTime()}">
    <words>{$word-count}</words>
  </metrics>
};

(:~
 : Update metrics for single text
 :
 : @param $url URL of the TEI document
:)
declare function metrics:update($url as xs:string) {
  let $metrics := metrics:calculate($url)
  let $paths := dutil:filepaths($url)
  let $collection := $paths?collections?metrics
  let $resource := $paths?filename
  return (
    util:log-system-out('Metrics update: ' || $collection || '/' || $resource),
    xmldb:store($collection, $resource, $metrics)
  )
};

(:~
 : Update metrics for all texts in the database
:)
declare function metrics:update() as xs:string* {
  let $l := util:log-system-out("Updating metrics files")
  for $tei in collection($config:data-root)//tei:TEI
  let $url := $tei/base-uri()
  return metrics:update($url)
};

declare function metrics:corpus ($corpus as xs:string) {
  let $collection-uri := concat($config:data-root, "/", $corpus)
  let $col := collection($collection-uri)
  let $metrics-uri := concat($config:metrics-root, "/", $corpus)
  let $metrics := collection($metrics-uri)
  let $entities := collection(concat($config:entities-root, "/", $corpus))
  return map {
    "texts": count($col/tei:TEI),
    "authors": count(distinct-values($col//tei:titleStmt//tei:author)),
    "words": sum($metrics//words),
    "entities": count(distinct-values($entities//entities/entity/wikidata)),
    "animals": count(distinct-values($entities//entities/entity[category="Animal"]/wikidata)),
    "plants": count(distinct-values($entities//entities/entity[category="Plant"]/wikidata)),
    "updated": max($metrics//metrics/xs:dateTime(@updated))
  }
};
