xquery version "3.1";

(:~
 : Module providing TEI extraction functions for ecocor.
 :)
module namespace ectei = "http://ecocor.org/ns/exist/tei";

import module namespace config = "http://ecocor.org/ns/exist/config" at "config.xqm";
import module namespace ecutil = "http://ecocor.org/ns/exist/util" at "util.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : Get teiCorpus element for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return teiCorpus element
 :)
declare function ectei:get-corpus(
  $corpusname as xs:string
) as element()* {
  collection($config:data-root)//tei:teiCorpus[
    tei:teiHeader//tei:publicationStmt/tei:idno[
      @type="URI" and
      @xml:base="https://ecocor.org/" and
      . = $corpusname
    ]
  ]
};

(:~
 : Extract DraCor ID of a text.
 :
 : @param $tei TEI document
 :)
declare function ectei:get-ecocor-id($tei as element(tei:TEI)) as xs:string* {
  $tei/@xml:id/normalize-space()
};

(:~
 : Extract title and subtitle.
 :
 : @param $tei TEI document
 :)
declare function ectei:get-titles( $tei as element(tei:TEI) ) as map() {
  let $title := $tei//tei:fileDesc/tei:titleStmt/tei:title[1]/normalize-space()
  let $subtitle :=
    $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
  return map:merge((
    if ($title) then map {'main': $title} else (),
    if ($subtitle) then map {'sub': $subtitle} else ()
  ))
};

(:~
 : Retrieve title and subtitle from TEI by language.
 :
 : @param $tei TEI document
 : @param $lang 3-letter language code
 :)
declare function ectei:get-titles(
  $tei as element(tei:TEI),
  $lang as xs:string
) as map() {
  if($lang = $tei/@xml:lang) then
    ectei:get-titles($tei)
  else
  let $title :=
    $tei//tei:fileDesc/tei:titleStmt
      /tei:title[@xml:lang = $lang and not(@type = 'sub')][1]
      /normalize-space()
  let $subtitle :=
    $tei//tei:titleStmt/tei:title[@type = 'sub' and @xml:lang = $lang][1]
      /normalize-space()
  return map:merge((
    if ($title) then map {'main': $title} else (),
    if ($subtitle) then map {'sub': $subtitle} else ()
  ))
};

(:~
 : Extract text paragraphs.
 :
 : @param $tei TEI document
 :)
declare function ectei:get-text-paras($tei as element(tei:TEI)) as element(tei:p)* {
  $tei//tei:text//tei:p[@xml:id]
};

(:~
 : Extract Wikidata ID for play from standOff.
 :
 : @param $tei TEI element
 :)
declare function ectei:get-text-wikidata-id ($tei as element(tei:TEI)) {
  let $uri := $tei//tei:standOff/tei:listRelation
    /tei:relation[@name="wikidata"][1]/@passive/string()
  return if (starts-with($uri, 'http://www.wikidata.org/entity/')) then
    tokenize($uri, '/')[last()]
  else ()
};

(:~
 : Extract full name from author element.
 :
 : @param $author author element
 : @return string
 :)
declare function ectei:get-full-name ($author as element(tei:author)) {
  if ($author/tei:persName) then
    normalize-space($author/tei:persName[1])
  else if ($author/tei:name) then
    normalize-space($author/tei:name[1])
  else normalize-space($author)
};

(:~
 : Extract full name from author element by language.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function ectei:get-full-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  if ($author/tei:persName[@xml:lang=$lang]) then
    normalize-space($author/tei:persName[@xml:lang=$lang][1])
  else if ($author/tei:name[@xml:lang=$lang]) then
    normalize-space($author/tei:name[@xml:lang=$lang][1])
  else ()
};

declare function local:build-short-name ($name as element()) {
  if ($name/tei:surname) then
    let $n := if ($name/tei:surname[@sort="1"]) then
      $name/tei:surname[@sort="1"] else $name/tei:surname[1]
    return normalize-space($n)
  else normalize-space($name)
};

(:~
 : Extract short name from author element.
 :
 : @param $author author element
 : @return string
 :)
declare function ectei:get-short-name ($author as element(tei:author)) {
  let $name := if ($author/tei:persName) then
    $author/tei:persName[1]
  else if ($author/tei:name) then
    $author/tei:name[1]
  else ()

  return if (not($name)) then
    normalize-space($author)
  else local:build-short-name($name)
};

(:~
 : Extract short name from author element by language.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function ectei:get-short-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  let $name := if ($author/tei:persName[@xml:lang=$lang]) then
    $author/tei:persName[@xml:lang=$lang][1]
  else if ($author/tei:name[@xml:lang=$lang]) then
    $author/tei:name[@xml:lang=$lang][1]
  else ()

  return if (not($name)) then () else local:build-short-name($name)
};

declare function local:build-sort-name ($name as element()) {
  (:
   : If there is a surname and it is not the first element in the name we
   : rearrange the name to put it first. Otherwise we just return the normalized
   : text as written in the document.
   :)
  if ($name/tei:surname and not($name/tei:*[1] = $name/tei:surname)) then
    let $start := if ($name/tei:surname[@sort="1"]) then
      $name/tei:surname[@sort="1"] else $name/tei:surname[1]

    return string-join(
      ($start, $start/(following-sibling::text()|following-sibling::*)), ""
    ) => normalize-space()
    || ", "
    || string-join(
      $start/(preceding-sibling::text()|preceding-sibling::*), ""
    ) => normalize-space()
  else normalize-space($name)
};

(:~
 : Extract name from author element that is suitable for sorting.
 :
 : @param $author author element
 : @return string
 :)
declare function ectei:get-sort-name ($author as element(tei:author) ) {
  let $name := if ($author/tei:persName) then
    $author/tei:persName[1]
  else if ($author/tei:name) then
    $author/tei:name[1]
  else ()

  return if (not($name)) then
    normalize-space($author)
  else local:build-sort-name($name)
};

(:~
 : Extract name by language from author element that is suitable for sorting.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function ectei:get-sort-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  let $name := if ($author/tei:persName[@xml:lang=$lang]) then
    $author/tei:persName[@xml:lang=$lang][1]
  else if ($author/tei:name[@xml:lang=$lang]) then
    $author/tei:name[@xml:lang=$lang][1]
  else ()

  return if (not($name)) then () else local:build-sort-name($name)
};

(:~
 : Retrieve author data from TEI.
 :
 : @param $tei TEI document
 :)
declare function ectei:get-authors($tei as node()) as map()* {
  for $author in $tei//tei:fileDesc/tei:titleStmt/tei:author[
    not(@role="illustrator")
  ]
  let $name := ectei:get-sort-name($author)
  let $fullname := ectei:get-full-name($author)
  let $shortname := ectei:get-short-name($author)
  let $nameEn := ectei:get-sort-name($author, 'eng')
  let $fullnameEn := ectei:get-full-name($author, 'eng')
  let $shortnameEn := ectei:get-short-name($author, 'eng')
  let $wikidata-id := tokenize($author/@ref, 'https://www.wikidata.org/wiki/')[2]
  let $refs := array {
    if ($wikidata-id) then map{ "wikidata": $wikidata-id } else ()
  }
  let $aka := array {
    for $name in $author/tei:persName[position() > 1]
    return $name => normalize-space()
  }

  return map:merge((
    map {
      "name": $name,
      "fullname": $fullname,
      "shortname": $shortname,
      "refs": $refs
    },
    if ($nameEn) then map {"nameEn": $nameEn} else (),
    if ($fullnameEn) then map {"fullnameEn": $fullnameEn} else (),
    if ($shortnameEn) then map {"shortnameEn": $shortnameEn} else (),
    if (array:size($aka) > 0) then map {"alsoKnownAs": $aka} else ()
  ))
};

(:~
 : Extract meta data for a text.
 :
 : @param $corpusname
 : @param $textname
 :)
declare function ectei:get-text-info($tei as element(tei:TEI)) as map()? {
  if ($tei) then
    let $id := ectei:get-ecocor-id($tei)
    let $titles := ectei:get-titles($tei)
    let $titlesEn := ectei:get-titles($tei, 'eng')
    let $source := $tei//tei:sourceDesc/tei:bibl[@type="digitalSource"]
    let $orig-source := $tei//tei:bibl[@type="originalSource"][1]/normalize-space(.)
    let $authors := ectei:get-authors($tei)
    let $wikidata-id := ectei:get-text-wikidata-id($tei)
    let $paths := ecutil:filepaths($tei/base-uri())

    return map:merge((
      map {
        "id": $id,
        "name": $paths?textname,
        "corpus": $paths?corpusname,
        "title": $titles?main,
        "authors": array { for $author in $authors return $author }
      },
      if($titlesEn?main) then map:entry("titleEn", $titlesEn?main) else (),
      if($titles?sub) then map:entry("subtitle", $titles?sub) else (),
      if($titlesEn?sub) then map:entry("subtitleEn", $titlesEn?sub) else (),
      if($wikidata-id) then
        map:entry("wikidataId", $wikidata-id)
      else (),
      if($orig-source) then
        map:entry("originalSource", $orig-source)
      else (),
      if($source) then
        map:entry("source", map {
          "name": $source/tei:name/string(),
          "url": $source/tei:idno[@type="URL"][1]/string()
        })
      else ()
    ))
  else ()
};

(:~
 : Extract meta data for a text identified by corpus and text name.
 :
 : @param $corpusname
 : @param $textname
 :)
declare function ectei:get-text-info(
  $corpusname as xs:string,
  $textname as xs:string
) as map()? {
  let $doc := ecutil:get-doc($corpusname, $textname)
  return if ($doc) then ectei:get-text-info($doc//tei:TEI) else ()
};

(:~
 : Extract meta data for all texts in corpus identified by corpusname.
 :
 : @param $corpusname
 :)
declare function ectei:get-corpus-text-info(
  $corpusname as xs:string
) as map()* {
  for $tei in ecutil:get-corpus-docs($corpusname)
  return ectei:get-text-info($tei)
};

(:~
 : Extract corpus update timestamp from metrics.
 :
 : @param $corpusname
 :)
declare function ectei:get-corpus-update-time(
  $corpusname as xs:string
) as xs:dateTime* {
  let $metrics-uri := concat($config:metrics-root, "/", $corpusname)
  let $metrics := collection($metrics-uri)
  return max($metrics//metrics/xs:dateTime(@updated))
};

declare function local:to-markdown($input as element()) as item()* {
  for $child in $input/node()
  return
    if ($child instance of element())
    then (
      if (name($child) = 'ref')
      then "[" || $child/text() || "](" || $child/@target || ")"
      else if (name($child) = 'hi')
      then "**" || $child/text() || "**"
      else local:to-markdown($child)
    )
    else $child
};

declare function local:markdown($input as element()) as item()* {
  normalize-space(string-join(local:to-markdown($input), ''))
};

(:~
 : Get basic information for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return map
 :)
declare function ectei:get-corpus-info(
  $corpus as element(tei:teiCorpus)*
) as map(*)* {
  let $header := $corpus/tei:teiHeader
  let $name := $header//tei:publicationStmt/tei:idno[
    @type="URI" and @xml:base="https://ecocor.org/"
  ]/text()
  let $title := $header/tei:fileDesc/tei:titleStmt/tei:title[1]/text()
  let $acronym := $header/tei:fileDesc/tei:titleStmt/tei:title[@type="acronym"]/text()
  let $repo := $header//tei:publicationStmt/tei:idno[@type="repo"]/text()
  let $projectDesc := $header/tei:encodingDesc/tei:projectDesc
  let $licence := $header//tei:availability/tei:licence
  let $uri := $config:api-base || "/corpora/" || $name
  let $description := if ($projectDesc) then (
    for $p in $projectDesc/tei:p return local:markdown($p)
  ) else ()
  return if ($header) then (
    map:merge((
      map:entry("uri", $uri),
      map:entry("name", $name),
      map:entry("title", $title),
      map:entry("textsUrl", $uri || "/texts"),
      map:entry("entitiesUrl", $uri || "/entities"),
      if ($acronym) then map:entry("acronym", $acronym) else (),
      if ($repo) then map:entry("repository", $repo) else (),
      if ($description) then map:entry("description", $description) else (),
      if ($licence)
        then map:entry("licence", normalize-space($licence)) else (),
      if ($licence/@target)
        then map:entry("licenceUrl", $licence/@target/string()) else (),
      map:entry("updated", ectei:get-corpus-update-time($name))
    ))
  ) else ()
};

(:~
 : Get basic information for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return map
 :)
declare function ectei:get-corpus-info-by-name(
  $corpusname as xs:string
) as map(*)* {
  let $corpus := ectei:get-corpus($corpusname)
  return ectei:get-corpus-info($corpus)
};
