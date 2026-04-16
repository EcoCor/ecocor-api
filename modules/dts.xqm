xquery version "3.1";

(:~
 : Distributed Text Services (DTS) v1.0 API for EcoCor.
 :
 : Implements the four endpoints defined in
 : https://dtsapi.org/specifications/versions/v1.0/
 :
 :   - Entry Point  (GET /dts)
 :   - Collection   (GET /dts/collection{?id,page,nav})
 :   - Navigation   (GET /dts/navigation{?resource,ref,start,end,down,tree,page})
 :   - Document     (GET /dts/document{?resource,ref,start,end,tree,mediaType})
 :
 : The module prefix is `ecdts` because `dts` is reserved as the XML
 : namespace used in Document-endpoint responses (`<dts:wrapper>`).
 :)
module namespace ecdts = "http://ecocor.org/ns/exist/dts";

import module namespace config = "http://ecocor.org/ns/exist/config"
  at "config.xqm";
import module namespace ectei = "http://ecocor.org/ns/exist/tei"
  at "tei.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace dts = "https://dtsapi.org/v1.0#";

(: Non-negotiable constants from the spec :)
declare variable $ecdts:spec-version := "1.0";
declare variable $ecdts:jsonld-context := "https://dtsapi.org/context/v1.0.json";

(: Base URLs for the four endpoints :)
declare variable $ecdts:api-base := $config:api-base || "/dts";
declare variable $ecdts:collection-base := $ecdts:api-base || "/collection";
declare variable $ecdts:navigation-base := $ecdts:api-base || "/navigation";
declare variable $ecdts:document-base := $ecdts:api-base || "/document";

(:~
 : Entry Point — advertises the URI templates for the other three
 : endpoints so clients can discover them.
 :
 : Spec: https://dtsapi.org/specifications/versions/v1.0/#entry-endpoint
 :)
declare
  %rest:GET
  %rest:path("/ecocor/dts")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ecdts:entry-point() {
  map {
    "@context": $ecdts:jsonld-context,
    "@id": $ecdts:api-base,
    "@type": "EntryPoint",
    "dtsVersion": $ecdts:spec-version,
    "collection": $ecdts:collection-base || "{?id,page,nav}",
    "navigation": $ecdts:navigation-base
      || "{?resource,ref,start,end,down,tree,page}",
    "document": $ecdts:document-base
      || "{?resource,ref,start,end,tree,mediaType}"
  }
};

(: ========================================================================
 : Collection endpoint
 : ======================================================================== :)

(:~
 : Selector for base tokenized TEI documents only. Excludes
 : annotation layer TEIs (which have @type="annotation").
 :)
declare function ecdts:tokenized-teis(
  $corpusname as xs:string?
) as element(tei:TEI)* {
  let $scope := if ($corpusname)
    then collection($config:corpora-root || "/" || $corpusname)
    else collection($config:corpora-root)
  return $scope//tei:TEI[@type = "tokenized"]
};

(:~
 : Public Resource id for a tokenized TEI. Strips the `_tokenized`
 : suffix from the internal xml:id so clients see clean identifiers
 : like `eco_de_000033` instead of `eco_de_000033_tokenized`.
 :)
declare function ecdts:resource-id(
  $tei as element(tei:TEI)
) as xs:string {
  replace(string($tei/@xml:id), '_tokenized$', '')
};

(:~
 : Resolve a Resource id (public form, no `_tokenized` suffix) to
 : its location. Returns a map with the tei element, corpusname, and
 : textname; or empty if no such resource.
 :)
declare function ecdts:resolve-resource-id(
  $id as xs:string
) as map(*)? {
  let $internal-id := $id || "_tokenized"
  let $tei := (ecdts:tokenized-teis(())[@xml:id = $internal-id])[1]
  return
    if (not($tei)) then ()
    else
      let $segments := tokenize($tei/base-uri(), '/')
      return map {
        "tei": $tei,
        "corpusname": $segments[last() - 2],
        "textname": $segments[last() - 1]
      }
};

(:~
 : Collection member object for one corpus.
 :)
declare function ecdts:corpus-member(
  $corpus-info as map(*)
) as map(*) {
  let $name := $corpus-info?name
  let $texts := count(ecdts:tokenized-teis($name))
  return map:merge((
    map {
      "@id": $name,
      "@type": "Collection",
      "title": $corpus-info?title,
      "totalParents": 1,
      "totalChildren": $texts,
      "collection": $ecdts:collection-base || "{?id,page,nav}"
    },
    if ($corpus-info?description) then
      map:entry("description", $corpus-info?description)
    else ()
  ))
};

(:~
 : Resource member object for one text.
 :)
declare function ecdts:resource-member(
  $tei as element(tei:TEI),
  $corpusname as xs:string
) as map(*) {
  let $id := ecdts:resource-id($tei)
  let $titles := ectei:get-titles($tei)
  let $authors := ectei:get-authors($tei)
  let $author-names := string-join(
    for $a in $authors return $a?name, "; "
  )
  let $title := if ($author-names) then
    $author-names || ": " || $titles?main
  else $titles?main
  return map {
    "@id": $id,
    "@type": "Resource",
    "title": $title,
    "totalParents": 1,
    "totalChildren": 0,
    "collection": $ecdts:collection-base || "{?id,page,nav}",
    "navigation": $ecdts:navigation-base
      || "{?resource,ref,start,end,down,tree,page}",
    "document": $ecdts:document-base
      || "{?resource,ref,start,end,tree,mediaType}"
  }
};

(:~
 : Root collection — lists every corpus as a Collection member.
 :)
declare function ecdts:root-collection() as map(*) {
  let $corpora := collection($config:corpora-root)//tei:teiCorpus
  let $infos := for $c in $corpora return ectei:get-corpus-info($c)
  return map {
    "@context": $ecdts:jsonld-context,
    "@id": "ecocor",
    "@type": "Collection",
    "dtsVersion": $ecdts:spec-version,
    "title": "EcoCor",
    "totalParents": 0,
    "totalChildren": count($infos),
    "collection": $ecdts:collection-base || "{?id,page,nav}",
    "member": array {
      for $info in $infos
      order by $info?name
      return ecdts:corpus-member($info)
    }
  }
};

(:~
 : Corpus collection — one corpus with all its texts as Resource
 : members.
 :)
declare function ecdts:corpus-collection(
  $corpusname as xs:string
) as map(*) {
  let $info := ectei:get-corpus-info-by-name($corpusname)
  let $texts :=
    for $tei in ecdts:tokenized-teis($corpusname)
    order by string($tei/@xml:id)
    return $tei
  return map:merge((
    map {
      "@context": $ecdts:jsonld-context,
      "@id": $corpusname,
      "@type": "Collection",
      "dtsVersion": $ecdts:spec-version,
      "title": $info?title,
      "totalParents": 1,
      "totalChildren": count($texts),
      "collection": $ecdts:collection-base || "{?id,page,nav}",
      "member": array {
        for $tei in $texts
        return ecdts:resource-member($tei, $corpusname)
      }
    },
    if ($info?description) then
      map:entry("description", $info?description)
    else ()
  ))
};

(:~
 : Full single Resource response.
 : citationTrees is an empty array for now — proper citation trees
 : will be computed when the Navigation endpoint is implemented.
 :)
declare function ecdts:resource(
  $tei as element(tei:TEI),
  $corpusname as xs:string
) as map(*) {
  let $member := ecdts:resource-member($tei, $corpusname)
  return map:merge((
    map {
      "@context": $ecdts:jsonld-context,
      "dtsVersion": $ecdts:spec-version,
      "citationTrees": array { },
      "mediaTypes": array { "application/tei+xml" }
    },
    $member
  ))
};

(:~
 : nav=parents response for a corpus. Replaces the member array with
 : the single parent (the root).
 :)
declare function ecdts:corpus-collection-with-parents(
  $corpusname as xs:string
) as map(*) {
  let $info := ectei:get-corpus-info-by-name($corpusname)
  let $root-stub := map {
    "@id": "ecocor",
    "@type": "Collection",
    "title": "EcoCor",
    "totalParents": 0,
    "totalChildren": count(
      collection($config:corpora-root)//tei:teiCorpus
    ),
    "collection": $ecdts:collection-base || "{?id,page,nav}"
  }
  return map:merge((
    map {
      "@context": $ecdts:jsonld-context,
      "@id": $corpusname,
      "@type": "Collection",
      "dtsVersion": $ecdts:spec-version,
      "title": $info?title,
      "totalParents": 1,
      "totalChildren": 0,
      "collection": $ecdts:collection-base || "{?id,page,nav}",
      "member": array { $root-stub }
    },
    if ($info?description) then
      map:entry("description", $info?description)
    else ()
  ))
};

(:~
 : nav=parents response for a Resource. member is the owning corpus.
 :)
declare function ecdts:resource-with-parents(
  $tei as element(tei:TEI),
  $corpusname as xs:string
) as map(*) {
  let $info := ectei:get-corpus-info-by-name($corpusname)
  let $texts := count(ecdts:tokenized-teis($corpusname))
  let $corpus-stub := map:merge((
    map {
      "@id": $corpusname,
      "@type": "Collection",
      "title": $info?title,
      "totalParents": 1,
      "totalChildren": $texts,
      "collection": $ecdts:collection-base || "{?id,page,nav}"
    },
    if ($info?description) then
      map:entry("description", $info?description)
    else ()
  ))
  let $self := ecdts:resource-member($tei, $corpusname)
  return map:merge((
    map {
      "@context": $ecdts:jsonld-context,
      "dtsVersion": $ecdts:spec-version,
      "citationTrees": array { },
      "mediaTypes": array { "application/tei+xml" },
      "member": array { $corpus-stub }
    },
    $self
  ))
};

(:~
 : Collection endpoint dispatcher.
 :
 : Spec: https://dtsapi.org/specifications/versions/v1.0/#collection-endpoint
 :
 : Handles:
 :   - no id              → root collection
 :   - id=<corpus>        → corpus collection
 :   - id=<TEI xml:id>    → Resource
 :   - nav=parents        → parent collection(s) in member
 :)
declare
  %rest:GET
  %rest:path("/ecocor/dts/collection")
  %rest:query-param("id", "{$id}")
  %rest:query-param("nav", "{$nav}")
  %rest:query-param("page", "{$page}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ecdts:collection($id, $nav, $page) {
  if ($nav and not($nav = ("children", "parents"))) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameter 'nav' must be 'children' or 'parents'."
      }
    )
  else if (not($id)) then
    ecdts:root-collection()
  else
    let $corpus := ectei:get-corpus($id)
    let $resource := if ($corpus) then () else ecdts:resolve-resource-id($id)
    return
      if ($corpus) then
        if ($nav = "parents") then
          ecdts:corpus-collection-with-parents($id)
        else
          ecdts:corpus-collection($id)
      else if (exists($resource)) then
        if ($nav = "parents") then
          ecdts:resource-with-parents($resource?tei, $resource?corpusname)
        else
          ecdts:resource($resource?tei, $resource?corpusname)
      else
        (
          <rest:response><http:response status="404"/></rest:response>,
          map {
            "error": "Not Found",
            "message": "No collection or resource with id '" || $id || "'."
          }
        )
};
