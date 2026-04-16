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

(:~
 : Metadata search — title and author substring match across texts.
 :
 : Unlike the fulltext /search endpoint (which returns paragraph hits),
 : this returns text-level hits with bibliographic metadata.
 :
 : @param $q Matches in title OR author (substring, case-insensitive)
 : @param $title Substring match on title
 : @param $author Substring match on author names
 : @param $corpus Optional corpus name to restrict search
 : @param $limit Results per page (default 50)
 : @param $offset Zero-based offset (default 0)
 :)
declare
  %rest:GET
  %rest:path("/ecocor/search/metadata")
  %rest:query-param("q", "{$q}")
  %rest:query-param("title", "{$title}")
  %rest:query-param("author", "{$author}")
  %rest:query-param("corpus", "{$corpus}")
  %rest:query-param("limit", "{$limit}")
  %rest:query-param("offset", "{$offset}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function search:metadata(
  $q as xs:string*,
  $title as xs:string*,
  $author as xs:string*,
  $corpus as xs:string*,
  $limit as xs:string*,
  $offset as xs:string*
) as item()+ {
  let $lim := if ($limit) then xs:integer($limit) else 50
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
    else if (not($q) and not($title) and not($author)) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {
          "error": "Bad Request",
          "message": "At least one of 'q', 'title', or 'author' is required."
        }
      )
    else
      let $teis := collection($collection-path)//tei:TEI[@type = "tokenized"]

      (: Lucene ft:query on tei:title and tei:author inside titleStmt :)
      let $matches := $teis[
        (not($q)
          or .//tei:titleStmt/tei:title[ft:query(., $q)]
          or .//tei:titleStmt/tei:author[ft:query(., $q)])
        and
        (not($title)
          or .//tei:titleStmt/tei:title[ft:query(., $title)])
        and
        (not($author)
          or .//tei:titleStmt/tei:author[ft:query(., $author)])
      ]

      let $total := count($matches)
      let $page := subsequence($matches, $off + 1, $lim)
      let $dts-base := $config:api-base || "/dts"

      let $results := array {
        for $tei in $page
        let $resource-id := search:resource-id($tei)
        let $titles := ectei:get-titles($tei)
        let $authors := ectei:get-authors($tei)
        let $paths := ecutil:filepaths(base-uri($tei))
        return map {
          "id": $resource-id,
          "name": $paths?textname,
          "corpus": $paths?corpusname,
          "title": $titles?main,
          "authors": array {
            for $a in $authors return map { "name": $a?name }
          },
          "uri": $paths?uri,
          "collection": $dts-base || "/collection?id=" || $resource-id
        }
      }

      return map:merge((
        map {
          "query": map:merge((
            if ($q) then map:entry("q", $q) else (),
            if ($title) then map:entry("title", $title) else (),
            if ($author) then map:entry("author", $author) else (),
            if ($corpus) then map:entry("corpus", $corpus) else ()
          )),
          "totalHits": $total,
          "offset": $off,
          "limit": $lim,
          "results": $results
        }
      ))
};


(:~
 : Token-surface search. Finds `<w>` tokens matching a Lucene query,
 : optionally filtered to tokens that carry an annotation from a layer
 : of a given `listAnnotation/@type` (e.g. `entities`).
 :
 : Each result carries the list of annotations on the token across all
 : layers — so clients see which layers detected it and with what body.
 :
 : @param $q Surface-form query (Lucene syntax, required)
 : @param $layerType Restrict to tokens annotated by a layer whose
 :                   `listAnnotation/@type` equals this value (e.g.
 :                   "entities"). Omit to return all matches.
 : @param $corpus Optional corpus name
 : @param $id Optional resource id (public form)
 : @param $limit Results per page (default 20)
 : @param $offset Zero-based offset (default 0)
 :)
declare
  %rest:GET
  %rest:path("/ecocor/search/tokens")
  %rest:query-param("q", "{$q}")
  %rest:query-param("layerType", "{$layerType}")
  %rest:query-param("corpus", "{$corpus}")
  %rest:query-param("id", "{$id}")
  %rest:query-param("limit", "{$limit}")
  %rest:query-param("offset", "{$offset}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function search:tokens(
  $q as xs:string*,
  $layerType as xs:string*,
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
          let $all-hits := $scope//tei:w[ft:query(., $q)]

          (: layer-type filter: keep only tokens with ≥1 annotation from
             a layer where listAnnotation/@type = $layerType :)
          let $filtered := if ($layerType) then
            $all-hits[search:has-annotation-of-type(., $layerType)]
          else
            $all-hits

          let $total := count($filtered)
          let $page := subsequence($filtered, $off + 1, $lim)
          let $dts-base := $config:api-base || "/dts"

          let $results := array {
            for $hit in $page
            let $tei := $hit/ancestor::tei:TEI
            let $resource-id := search:resource-id($tei)
            let $paths := ecutil:filepaths(base-uri($tei))
            let $token-id := string($hit/@xml:id)
            let $paragraph := $hit/ancestor::tei:p[@xml:id][1]
            let $cite-ref := if ($paragraph)
              then string($paragraph/@xml:id)
              else ()
            return map:merge((
              map {
                "id": $resource-id,
                "name": $paths?textname,
                "corpus": $paths?corpusname,
                "token": map {
                  "id": $token-id,
                  "text": string($hit),
                  "type": local-name($hit)
                },
                "annotations": search:annotations-for-token($tei, $token-id)
              },
              if ($cite-ref) then (
                map:entry("citableUnit", $cite-ref),
                map:entry(
                  "document",
                  $dts-base || "/document?resource=" || $resource-id
                    || "&amp;ref=" || $cite-ref
                )
              ) else (),
              map:entry(
                "tokenUri",
                $paths?uri || "/tokens/" || $token-id
              )
            ))
          }

          return map:merge((
            map {
              "query": map:merge((
                map:entry("q", $q),
                if ($layerType) then map:entry("layerType", $layerType) else (),
                if ($corpus) then map:entry("corpus", $corpus) else (),
                if ($id) then map:entry("id", $id) else ()
              )),
              "totalHits": $total,
              "offset": $off,
              "limit": $lim,
              "results": $results
            }
          ))
};

(:~
 : True if the token carries at least one annotation from a layer
 : whose `listAnnotation/@type` equals `$layer-type`.
 :)
declare function search:has-annotation-of-type(
  $token as element(tei:w),
  $layer-type as xs:string
) as xs:boolean {
  let $tei := $token/ancestor::tei:TEI
  let $segments := tokenize(base-uri($tei), '/')
  let $text-collection := string-join($segments[position() < last()], "/")
  let $ann-collection := $text-collection || "/annotations"
  return
    if (not(xmldb:collection-available($ann-collection))) then false()
    else
      let $target-ref := "#" || string($token/@xml:id)
      return exists(
        collection($ann-collection)
          //tei:listAnnotation[@type = $layer-type]
          //tei:annotation[tokenize(@target, '\s+') = $target-ref]
      )
};

(:~
 : Annotations (flat across layers) targeting a given token id. Each
 : entry carries the source layer name and a body of key/value pairs.
 :)
declare function search:annotations-for-token(
  $tei as element(tei:TEI),
  $token-id as xs:string
) as array(*) {
  let $segments := tokenize(base-uri($tei), '/')
  let $text-collection := string-join($segments[position() < last()], "/")
  let $ann-collection := $text-collection || "/annotations"
  let $target-ref := "#" || $token-id
  return array {
    if (not(xmldb:collection-available($ann-collection))) then () else
    for $resource in xmldb:get-child-resources($ann-collection)
    let $doc := doc($ann-collection || "/" || $resource)
    let $layername := replace($resource, '\.xml$', '')
    let $layer-type := string($doc//tei:listAnnotation/@type)
    for $a in $doc//tei:annotation[
      tokenize(@target, '\s+') = $target-ref
    ]
    return map {
      "layer": $layername,
      "layerType": $layer-type,
      "body": array {
        for $attr in $a/(@ana, @corresp)
        return map {
          "key": local-name($attr),
          "value": string($attr)
        },
        for $note in $a/tei:note[@type]
        return map {
          "key": string($note/@type),
          "value": normalize-space($note)
        }
      }
    }
  }
};
