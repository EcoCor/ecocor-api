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
      "citationTrees": ecdts:citation-trees($tei),
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

(: ========================================================================
 : Citable-unit id scheme
 :
 : For a Resource with public id `R`:
 :   <p xml:id="P">          → "P"  (xml:id used as-is)
 :   <div type="chapter">    → "R_chNNN"  (flat counter over all chapters)
 :   <div type="group">      → "R_gNNN"
 :   <div type="front">      → "R_front"
 :   <div type="back">       → "R_back"
 :   other <div>             → "R_divNNN"
 :
 : Counters are computed by counting matching `preceding::div` in document
 : order, so ids are deterministic per-request but not stable across
 : content edits. Real xml:ids on divs are the long-term plan.
 : ======================================================================== :)

(:~
 : Is this element a CitableUnit in our scheme?
 :)
declare function ecdts:is-citable(
  $elem as element()
) as xs:boolean {
  local-name($elem) = "div" or
  (local-name($elem) = "p" and exists($elem/@xml:id))
};

(:~
 : Compute the public identifier of a single CitableUnit.
 :)
declare function ecdts:citable-id(
  $elem as element(),
  $resource-id as xs:string
) as xs:string {
  let $name := local-name($elem)
  return
    if ($name = "p") then string($elem/@xml:id)
    else if ($name = "div") then
      let $type := string($elem/@type)
      return
        if ($type = "front") then $resource-id || "_front"
        else if ($type = "back") then $resource-id || "_back"
        else
          let $tei := $elem/ancestor::tei:TEI
          let $all :=
            if ($type = ("chapter", "group")) then
              $tei//tei:div[@type = $type]
            else
              $tei//tei:div[not(@type = ("chapter", "group", "front", "back"))]
          let $prefix :=
            if ($type = "chapter") then "ch"
            else if ($type = "group") then "g"
            else "div"
          let $pos := (for $d at $i in $all where $d is $elem return $i)[1]
          let $padded := format-number($pos, "000")
          return $resource-id || "_" || $prefix || $padded
    else ()
};

(:~
 : citeType for a CitableUnit — used in both the citation tree shape
 : and the CitableUnit object.
 :)
declare function ecdts:cite-type(
  $elem as element()
) as xs:string {
  let $name := local-name($elem)
  return
    if ($name = "p") then "paragraph"
    else if ($name = "div") then
      let $type := string($elem/@type)
      return
        if ($type = "chapter") then "chapter"
        else if ($type = "group") then "group"
        else if ($type = "front") then "front"
        else if ($type = "back") then "back"
        else "div"
    else ""
};

(:~
 : Parent ref for a CitableUnit, or empty if top-level (under <front>,
 : <body>, or <back>).
 :)
declare function ecdts:parent-ref(
  $elem as element(),
  $resource-id as xs:string
) as xs:string? {
  let $parent := $elem/parent::*
  return
    if ($parent and ecdts:is-citable($parent)) then
      ecdts:citable-id($parent, $resource-id)
    else ()
};

(:~
 : Level = depth from <text> ancestor.
 : <text>/<body>/<p>     → 1  (text and body don't count as citable)
 : <text>/<body>/<div>   → 1
 : <text>/<body>/<div>/<div>/<p>  → 3
 :)
declare function ecdts:citable-level(
  $elem as element()
) as xs:integer {
  count($elem/ancestor::*[ecdts:is-citable(.)]) + 1
};

(:~
 : Resolve a ref to an element in the TEI. Returns the element or
 : empty sequence.
 :)
declare function ecdts:resolve-ref(
  $tei as element(tei:TEI),
  $resource-id as xs:string,
  $ref as xs:string
) as element()? {
  let $stripped := substring-after($ref, $resource-id || "_")
  return
    if ($stripped = "front") then
      $tei//tei:front/tei:div[@type = "front"][1]
    else if ($stripped = "back") then
      $tei//tei:back/tei:div[@type = "back"][1]
    else if (matches($stripped, '^ch(\d+)$')) then
      let $n := xs:integer(replace($stripped, '^ch', ''))
      return ($tei//tei:div[@type = "chapter"])[$n]
    else if (matches($stripped, '^g(\d+)$')) then
      let $n := xs:integer(replace($stripped, '^g', ''))
      return ($tei//tei:div[@type = "group"])[$n]
    else if (matches($stripped, '^div(\d+)$')) then
      let $n := xs:integer(replace($stripped, '^div', ''))
      return ($tei//tei:div[
        not(@type = ("chapter", "group", "front", "back"))
      ])[$n]
    else
      (: assume xml:id (paragraphs use their own xml:id as the full ref) :)
      $tei//*[@xml:id = $ref]
};

(:~
 : Build a CitableUnit map.
 :)
declare function ecdts:citable-unit(
  $elem as element(),
  $resource-id as xs:string
) as map(*) {
  let $id := ecdts:citable-id($elem, $resource-id)
  let $level := ecdts:citable-level($elem)
  let $parent := ecdts:parent-ref($elem, $resource-id)
  let $cite-type := ecdts:cite-type($elem)
  let $head := $elem/tei:head[1]
  return map:merge((
    map {
      "identifier": $id,
      "@type": "CitableUnit",
      "level": $level,
      "parent": if ($parent) then $parent else (),
      "citeType": $cite-type
    },
    if ($head) then
      map:entry("dublinCore", map {
        "title": normalize-space($head)
      })
    else ()
  ))
};

(:~
 : Top-level citable children of <text> (the immediate children of
 : <front>, <body>, <back>).
 :)
declare function ecdts:top-level-units(
  $tei as element(tei:TEI)
) as element()* {
  $tei/tei:text/(tei:front | tei:body | tei:back)/*[ecdts:is-citable(.)]
};

(:~
 : Direct citable children of an element.
 :)
declare function ecdts:citable-children(
  $elem as element()
) as element()* {
  $elem/*[ecdts:is-citable(.)]
};

(: ========================================================================
 : Citation tree (citeStructure) — per-Resource shape descriptor
 : ======================================================================== :)

(:~
 : Build a citeStructure array by inspecting the actual structural
 : patterns present in the TEI. Emits nested {citeType, citeStructure}
 : maps.
 :)
declare function ecdts:cite-structure(
  $tei as element(tei:TEI)
) as array(*) {
  let $top := ecdts:top-level-units($tei)
  let $by-type := distinct-values(for $t in $top return ecdts:cite-type($t))
  return array {
    for $type in $by-type
    let $exemplar := ($top[ecdts:cite-type(.) = $type])[1]
    return ecdts:cite-structure-node($exemplar)
  }
};

(:~
 : Recursive node for citeStructure. Emits only the citeTypes that
 : actually appear at each level.
 :)
declare function ecdts:cite-structure-node(
  $elem as element()
) as map(*) {
  let $citeType := ecdts:cite-type($elem)
  let $children := ecdts:citable-children($elem)
  let $child-types := distinct-values(
    for $c in $children return ecdts:cite-type($c)
  )
  return map:merge((
    map {
      "@type": "CiteStructure",
      "citeType": $citeType
    },
    if (count($child-types) > 0) then
      map:entry("citeStructure", array {
        for $t in $child-types
        let $exemplar := ($children[ecdts:cite-type(.) = $t])[1]
        return ecdts:cite-structure-node($exemplar)
      })
    else ()
  ))
};

(:~
 : The citationTrees property on a Resource. Currently one default
 : tree with no identifier.
 :)
declare function ecdts:citation-trees(
  $tei as element(tei:TEI)
) as array(*) {
  array {
    map {
      "@type": "CitationTree",
      "citeStructure": ecdts:cite-structure($tei)
    }
  }
};

(: ========================================================================
 : Navigation endpoint
 : ======================================================================== :)

(:~
 : Tree walk from root to a given depth (1-based; -1 = unbounded).
 :)
declare function ecdts:descendants-from-root(
  $tei as element(tei:TEI),
  $resource-id as xs:string,
  $max-level as xs:integer
) as map(*)* {
  ecdts:descendants-of($tei, ecdts:top-level-units($tei), $resource-id, $max-level)
};

(:~
 : Tree walk from a given parent to max-level.
 :)
declare function ecdts:descendants-of(
  $tei as element(tei:TEI),
  $nodes as element()*,
  $resource-id as xs:string,
  $max-level as xs:integer
) as map(*)* {
  for $node in $nodes
  let $level := ecdts:citable-level($node)
  where $max-level = -1 or $level <= $max-level
  return (
    ecdts:citable-unit($node, $resource-id),
    ecdts:descendants-of($tei, ecdts:citable-children($node), $resource-id, $max-level)
  )
};

(:~
 : Siblings of an element (including itself) in document order.
 :)
declare function ecdts:siblings(
  $elem as element()
) as element()* {
  let $parent := $elem/parent::*
  return
    if ($parent and ecdts:is-citable($parent)) then
      ecdts:citable-children($parent)
    else
      (: top-level: siblings are the other top-level units :)
      ecdts:top-level-units($elem/ancestor::tei:TEI)
};

(:~
 : Build the nested Resource object for the Navigation response.
 :)
declare function ecdts:navigation-resource(
  $tei as element(tei:TEI),
  $corpusname as xs:string
) as map(*) {
  map:merge((
    ecdts:resource-member($tei, $corpusname),
    map {
      "citationTrees": ecdts:citation-trees($tei),
      "mediaTypes": array { "application/tei+xml" }
    }
  ))
};

(:~
 : Build the Navigation response @id (current request URL).
 :)
declare function ecdts:navigation-request-id(
  $resource-id as xs:string,
  $ref as xs:string?,
  $start as xs:string?,
  $end as xs:string?,
  $down as xs:string?
) as xs:string {
  let $params := string-join((
    "resource=" || encode-for-uri($resource-id),
    if ($ref) then "ref=" || encode-for-uri($ref) else (),
    if ($start) then "start=" || encode-for-uri($start) else (),
    if ($end) then "end=" || encode-for-uri($end) else (),
    if ($down) then "down=" || $down else ()
  ), "&amp;")
  return $ecdts:navigation-base || "?" || $params
};

(:~
 : Navigation endpoint dispatcher.
 :)
declare
  %rest:GET
  %rest:path("/ecocor/dts/navigation")
  %rest:query-param("resource", "{$resource}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("start", "{$start}")
  %rest:query-param("end", "{$end}")
  %rest:query-param("down", "{$down}")
  %rest:query-param("tree", "{$tree}")
  %rest:query-param("page", "{$page}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ecdts:navigation(
  $resource, $ref, $start, $end, $down, $tree, $page
) {
  (: parameter validation :)
  if (not($resource)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameter 'resource' is required."
      }
    )
  else if ($ref and ($start or $end)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameters 'ref' and 'start'/'end' are mutually exclusive."
      }
    )
  else if (($start and not($end)) or ($end and not($start))) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameters 'start' and 'end' must be used together."
      }
    )
  else if ($down = "0" and not($ref)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameter 'down=0' requires 'ref'."
      }
    )
  else if (not($down) and not($ref) and not($start)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "At least one of 'down', 'ref', or 'start'/'end' is required."
      }
    )
  else
    let $resolved := ecdts:resolve-resource-id($resource)
    return
      if (empty($resolved)) then
        (
          <rest:response><http:response status="404"/></rest:response>,
          map {
            "error": "Not Found",
            "message": "No resource with id '" || $resource || "'."
          }
        )
      else
        ecdts:navigate(
          $resolved?tei, $resolved?corpusname, $resource,
          $ref, $start, $end,
          if ($down) then xs:integer($down) else ()
        )
};

(:~
 : Main Navigation dispatcher (parameter combinations implemented).
 :)
declare function ecdts:navigate(
  $tei as element(tei:TEI),
  $corpusname as xs:string,
  $resource-id as xs:string,
  $ref as xs:string?,
  $start as xs:string?,
  $end as xs:string?,
  $down as xs:integer?
) {
  let $base := map {
    "@context": $ecdts:jsonld-context,
    "@id": ecdts:navigation-request-id(
      $resource-id, $ref, $start, $end,
      if (exists($down)) then string($down) else ()
    ),
    "@type": "Navigation",
    "dtsVersion": $ecdts:spec-version,
    "resource": ecdts:navigation-resource($tei, $corpusname)
  }

  return
    (: Case: ref only, no down → info about ref, no member :)
    if ($ref and empty($down)) then
      let $elem := ecdts:resolve-ref($tei, $resource-id, $ref)
      return
        if (empty($elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map {
              "error": "Not Found",
              "message": "No CitableUnit with ref '" || $ref || "'."
            }
          )
        else
          map:merge((
            $base,
            map { "ref": ecdts:citable-unit($elem, $resource-id) }
          ))

    (: Case: down=0 + ref → ref plus siblings :)
    else if ($ref and $down = 0) then
      let $elem := ecdts:resolve-ref($tei, $resource-id, $ref)
      return
        if (empty($elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map {
              "error": "Not Found",
              "message": "No CitableUnit with ref '" || $ref || "'."
            }
          )
        else
          map:merge((
            $base,
            map {
              "ref": ecdts:citable-unit($elem, $resource-id),
              "member": array {
                for $sib in ecdts:siblings($elem)
                return ecdts:citable-unit($sib, $resource-id)
              }
            }
          ))

    (: Case: down>0 or down=-1, no ref, no start → from root to depth :)
    else if (exists($down) and not($ref) and not($start)) then
      let $target-level :=
        if ($down = -1) then -1
        else $down
      return map:merge((
        $base,
        map {
          "member": array {
            for $u in ecdts:descendants-from-root($tei, $resource-id, $target-level)
            return $u
          }
        }
      ))

    (: Case: down>0 or down=-1 + ref → from ref to depth :)
    else if (exists($down) and $ref) then
      let $elem := ecdts:resolve-ref($tei, $resource-id, $ref)
      return
        if (empty($elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map {
              "error": "Not Found",
              "message": "No CitableUnit with ref '" || $ref || "'."
            }
          )
        else
          let $base-level := ecdts:citable-level($elem)
          let $target-level :=
            if ($down = -1) then -1
            else $base-level + $down
          return map:merge((
            $base,
            map {
              "ref": ecdts:citable-unit($elem, $resource-id),
              "member": array {
                for $u in ecdts:descendants-of(
                  $tei, ecdts:citable-children($elem), $resource-id, $target-level
                )
                return $u
              }
            }
          ))

    (: Case: start/end, no down → info about start and end, no member :)
    else if ($start and $end and empty($down)) then
      let $start-elem := ecdts:resolve-ref($tei, $resource-id, $start)
      let $end-elem := ecdts:resolve-ref($tei, $resource-id, $end)
      return
        if (empty($start-elem) or empty($end-elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map {
              "error": "Not Found",
              "message": "Could not resolve start or end ref."
            }
          )
        else
          map:merge((
            $base,
            map {
              "start": ecdts:citable-unit($start-elem, $resource-id),
              "end": ecdts:citable-unit($end-elem, $resource-id)
            }
          ))

    (: start/end + down combinations not yet implemented :)
    else
      (
        <rest:response><http:response status="501"/></rest:response>,
        map {
          "error": "Not Implemented",
          "message": "The combination of 'start'/'end' with 'down' is not yet supported."
        }
      )
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
